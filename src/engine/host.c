/* Vortex - the in-process single-player server.
 *
 * Single player and multiplayer live in one executable. The world itself is a
 * Rust library (server/) that boots Pumpkin on its own threads and speaks to
 * this file through two byte queues, and that library is opened at run time
 * rather than linked: a client built without it reports that single player is
 * unavailable and still connects to any server over the network.
 *
 * Once loaded, the queue pair is installed with mc_install_transport() for the
 * negative handle pk_host_connect() returns, so every read and write the
 * protocol layer performs on that handle ends up here and the Login,
 * Configuration and Play code cannot tell it from a socket. No packet is ever
 * handed to a network stack.
 *
 * The protocol layer is byte-at-a-time because that is how the TCP path works,
 * so this file owns the buffering: a send gathers a whole packet before queuing
 * it, and a read refills a block at a time and waits on the pipe's condvar
 * instead of spinning. */

#ifdef _WIN32
#include <windows.h>
#define VT_SP_LIBNAME "pumpkin_host.dll"
static void *sp_dlopen(const char *path) { return (void *)LoadLibraryA(path); }
static void *sp_dlsym(void *library, const char *name) {
    return (void *)GetProcAddress((HMODULE)library, name);
}
static void sp_dlclose(void *library) { FreeLibrary((HMODULE)library); }
#else
#include <dlfcn.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#define VT_SP_LIBNAME "libpumpkin_host.dylib"
#else
#define VT_SP_LIBNAME "libpumpkin_host.so"
#endif
static void *sp_dlopen(const char *path) { return dlopen(path, RTLD_NOW | RTLD_LOCAL); }
static void *sp_dlsym(void *library, const char *name) { return dlsym(library, name); }
static void sp_dlclose(void *library) { dlclose(library); }
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <unistd.h>
#endif

/* A packet is gathered whole before it is queued: the pipe's client-to-server
 * direction never blocks, so a partial write would leave the server waiting on
 * an incomplete frame. 1 MiB covers the largest frame this client encodes. */
#define VT_SP_SEND_SIZE (1024 * 1024)
#define VT_SP_RECV_SIZE 4096
/* How long a read waits for the server before trying again. The poll loop only
 * gets here once the pipe reports data, so this is the safety net for a
 * shutdown race rather than the normal path. */
#define VT_SP_WAIT_MS 50

typedef int64_t (*vt_pk_start)(int64_t, int64_t, int64_t);
typedef int64_t (*vt_pk_connect)(void);
typedef int64_t (*vt_pk_stop)(void);
typedef int64_t (*vt_pk_write)(int64_t, const unsigned char *, int64_t);
typedef int64_t (*vt_pk_read)(int64_t, unsigned char *, int64_t);
typedef int64_t (*vt_pk_ready)(int64_t);
typedef int64_t (*vt_pk_wait)(int64_t, int64_t);
typedef int64_t (*vt_pk_close)(int64_t);

static struct {
    void *library;
    vt_pk_start start;
    vt_pk_connect connect;
    vt_pk_stop stop;
    vt_pk_write write;
    vt_pk_read read;
    vt_pk_ready ready;
    vt_pk_wait wait;
    vt_pk_close close;
} sp;

static char sp_message[256] = "single player not attempted";

static unsigned char *sp_send;
static size_t sp_send_length;
static int64_t sp_handle;
static unsigned char sp_recv[VT_SP_RECV_SIZE];
static size_t sp_recv_offset;
static size_t sp_recv_length;
static int sp_recv_eof;

/* src/network.c. */
int64_t mc_install_transport(int64_t handle, int64_t send_begin, int64_t send_byte,
                             int64_t send_end, int64_t recv_byte, int64_t close_fn,
                             int64_t ready);

static void sp_note(const char *text) {
    snprintf(sp_message, sizeof(sp_message), "%s", text);
}

static void *sp_sym(void *library, const char *name) {
    return sp_dlsym(library, name);
}

/* The directory holding this executable, with a trailing separator, so the
 * library can sit beside the client the way every game ships its optional
 * native modules. */
static int sp_exe_directory(char *out, size_t capacity) {
    char path[4096];
#if defined(__APPLE__)
    uint32_t size = sizeof(path);
    if (_NSGetExecutablePath(path, &size) != 0) return -1;
#elif defined(_WIN32)
    DWORD length = GetModuleFileNameA(NULL, path, sizeof(path));
    if (length == 0 || length >= sizeof(path)) return -1;
#else
    ssize_t length = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (length <= 0 || (size_t)length >= sizeof(path)) return -1;
    path[length] = '\0';
#endif
    char *separator = strrchr(path, '/');
#if defined(_WIN32)
    char *backslash = strrchr(path, '\\');
    if (backslash != 0 && (separator == 0 || backslash > separator)) separator = backslash;
#endif
    if (separator == 0) return -1;
    size_t used = (size_t)(separator - path) + 1;
    if (used >= capacity) return -1;
    memcpy(out, path, used);
    out[used] = '\0';
    return 0;
}

/* Open one candidate path and resolve every entry point it needs. A library
 * without the pipe symbols is a different program, so it is not used. */
static int sp_try_path(const char *path) {
    void *library;
    void *start;
    if (path == 0 || path[0] == '\0') return -1;
    library = sp_dlopen(path);
    if (library == 0) return -1;
    start = sp_sym(library, "pk_host_start");
    if (start == 0) {
        sp_dlclose(library);
        sp_note(path);
        return -1;
    }
    sp.library = library;
    sp.start = (vt_pk_start)start;
    sp.connect = (vt_pk_connect)sp_sym(library, "pk_host_connect");
    sp.stop = (vt_pk_stop)sp_sym(library, "pk_host_stop");
    sp.write = (vt_pk_write)sp_sym(library, "pk_pipe_write");
    sp.read = (vt_pk_read)sp_sym(library, "pk_pipe_read");
    sp.ready = (vt_pk_ready)sp_sym(library, "pk_pipe_ready");
    sp.wait = (vt_pk_wait)sp_sym(library, "pk_pipe_wait");
    sp.close = (vt_pk_close)sp_sym(library, "pk_pipe_close");
    if (sp.connect == 0 || sp.stop == 0 || sp.write == 0 || sp.read == 0
        || sp.ready == 0 || sp.wait == 0 || sp.close == 0) {
        sp_note(path);
        sp.library = 0;
        return -1;
    }
    sp_note(path);
    return 0;
}

/* Load the server library if it is present. Search order: VORTEX_SERVER_LIB
 * (a full path), beside the executable, in the working directory, then the
 * development tree. */
static int sp_load(void) {
    char candidate[4096];
    const char *override;
    if (sp.library != 0) return 0;
    override = getenv("VORTEX_SERVER_LIB");
    if (override != 0 && override[0] != '\0') {
        if (sp_try_path(override) == 0) return 0;
        sp_note("VORTEX_SERVER_LIB does not point at a usable server library");
        return -1;
    }
    if (sp_exe_directory(candidate, sizeof(candidate)) == 0) {
        snprintf(candidate + strlen(candidate), sizeof(candidate) - strlen(candidate),
                 "%s", VT_SP_LIBNAME);
        if (sp_try_path(candidate) == 0) return 0;
    }
    if (sp_try_path(VT_SP_LIBNAME) == 0) return 0;
    snprintf(candidate, sizeof(candidate), "server/target/release/%s", VT_SP_LIBNAME);
    if (sp_try_path(candidate) == 0) return 0;
    sp_note("single player needs the server library; run ./tools/pumpkin_host.sh, then put it beside the client or set VORTEX_SERVER_LIB");
    return -1;
}

static int64_t sp_flush(void) {
    size_t sent = 0;
    while (sent < sp_send_length) {
        int64_t taken = sp.write(sp_handle, sp_send + sent,
                                 (int64_t)(sp_send_length - sent));
        if (taken <= 0) {
            sp_send_length = 0;
            return -1;
        }
        sent += (size_t)taken;
    }
    sp_send_length = 0;
    return 0;
}

static int64_t sp_send_begin(int64_t handle) {
    sp_handle = handle;
    sp_send_length = 0;
    return 0;
}

static int64_t sp_send_byte(int64_t value) {
    if (value < 0 || value > 255) return -1;
    if (sp_send == 0) {
        sp_send = (unsigned char *)malloc(VT_SP_SEND_SIZE);
        if (sp_send == 0) return -1;
    }
    if (sp_send_length == VT_SP_SEND_SIZE && sp_flush() != 0) return -1;
    sp_send[sp_send_length++] = (unsigned char)value;
    return 0;
}

static int64_t sp_send_end(void) {
    if (sp_send_length == 0) return 0;
    return sp_flush();
}

static int64_t sp_recv_byte(int64_t handle) {
    if (sp_recv_eof) return -1;
    if (sp_recv_offset == sp_recv_length) {
        for (;;) {
            int64_t received = sp.read(handle, sp_recv, VT_SP_RECV_SIZE);
            if (received > 0) {
                sp_recv_offset = 0;
                sp_recv_length = (size_t)received;
                break;
            }
            if (received == -2) {
                sp_recv_eof = 1;
                return -1;
            }
            /* -1: nothing yet. Wait, because the TCP read this replaces blocks
             * as well. */
            sp.wait(handle, VT_SP_WAIT_MS);
        }
    }
    return sp_recv[sp_recv_offset++];
}

static int64_t sp_close(int64_t handle) {
    sp_recv_offset = 0;
    sp_recv_length = 0;
    sp_recv_eof = 0;
    sp_send_length = 0;
    sp_handle = 0;
    return sp.close(handle);
}

static int64_t sp_ready(int64_t handle) {
    if (sp_recv_offset < sp_recv_length || sp_recv_eof) return 1;
    return sp.ready(handle);
}

/* Whether an embedded world can be started in this process. Returns 0 when it
 * can, and vt_host_error() then says which library was loaded. */
int64_t vt_host_available(void) {
    return sp_load() == 0 ? 0 : 1;
}

/* What the last load attempt did, for the message the client prints. */
char *vt_host_error(void) {
    return sp_message;
}

/* Bring the embedded world up. `seed` is the world seed, `view_distance` the
 * server's chunk radius and `tps` the tick rate (0 uses 20). The world is
 * created in the working directory. */
int64_t vt_host_start(int64_t seed, int64_t view_distance, int64_t tps) {
    if (sp_load() != 0) return -1;
    return sp.start(seed, view_distance, tps);
}

/* Attach this process's client to the embedded server and install the pipe as
 * the transport for the handle returned, which the caller passes to the normal
 * session code in place of a socket descriptor. */
int64_t vt_host_connect(void) {
    int64_t handle;
    if (sp_load() != 0) return -1;
    handle = sp.connect();
    if (handle >= 0) {
        sp_note("the server refused the embedded connection");
        return -1;
    }
    if (mc_install_transport(handle, (int64_t)(intptr_t)sp_send_begin,
                             (int64_t)(intptr_t)sp_send_byte,
                             (int64_t)(intptr_t)sp_send_end,
                             (int64_t)(intptr_t)sp_recv_byte,
                             (int64_t)(intptr_t)sp_close,
                             (int64_t)(intptr_t)sp_ready) != 0) {
        sp.close(handle);
        sp_note("could not install the embedded transport");
        return -1;
    }
    sp_note("embedded session attached");
    return handle;
}

/* Close every pipe and run the server's shutdown saves. The library stays
 * loaded, so a second world in the same process costs nothing extra. */
int64_t vt_host_stop(void) {
    int64_t result;
    if (sp.library == 0) return 0;
    result = sp.stop();
    if (sp_send != 0) {
        free(sp_send);
        sp_send = 0;
    }
    sp_send_length = 0;
    sp_recv_offset = 0;
    sp_recv_length = 0;
    sp_recv_eof = 0;
    sp_handle = 0;
    return result;
}
