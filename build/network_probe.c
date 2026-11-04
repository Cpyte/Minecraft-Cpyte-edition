#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

/* The socket, poll and terminal layer below is written once and given a
 * per-platform vocabulary: Winsock keeps handles in a SOCKET, reports failures
 * through WSAGetLastError rather than errno, cannot poll a console, and takes
 * timeouts as a DWORD count of milliseconds. Everything else in this file is
 * shared, so the wire codec, the buffering and the line reader behave the same
 * on both hosts. */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <io.h>
#include <process.h>

typedef SOCKET mc_socket;
typedef SSIZE_T mc_ssize;
typedef WSAPOLLFD mc_pollfd;
#define mc_socket_invalid INVALID_SOCKET
#define mc_socket_error SOCKET_ERROR
#define mc_close_socket closesocket
#define mc_poll_socket WSAPoll
#define mc_last_error() WSAGetLastError()
#define mc_is_interrupted(code) ((code) == WSAEINTR)
#define mc_is_would_block(code) ((code) == WSAEWOULDBLOCK)
#define mc_stdin_fd() _fileno(stdin)

static int winsock_started = 0;

static void mc_start_winsock(void) {
    WSADATA data;
    if (winsock_started) return;
    if (WSAStartup(MAKEWORD(2, 2), &data) == 0) winsock_started = 1;
}

#else
#include <dlfcn.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

typedef int mc_socket;
typedef ssize_t mc_ssize;
typedef struct pollfd mc_pollfd;
#define mc_socket_invalid ((mc_socket)-1)
#define mc_socket_error (-1)
#define mc_close_socket close
#define mc_poll_socket poll
#define mc_last_error() errno
#define mc_is_interrupted(code) ((code) == EINTR)
#define mc_is_would_block(code) ((code) == EAGAIN || (code) == EWOULDBLOCK)
#define mc_stdin_fd() STDIN_FILENO

static void mc_start_winsock(void) {}

#endif

#define MC_CODEC_LIMIT 8388608

static int compression_threshold = -1;
static unsigned char *codec_input = NULL;
static size_t codec_input_length = 0;
static size_t codec_input_capacity = 0;
static unsigned char *codec_output = NULL;
static size_t codec_output_length = 0;

static void *load_zlib_symbol(const char *name) {
#ifdef _WIN32
    /* MinGW links zlib statically, so the symbols are already in the image and
     * there is no dynamic loader to ask. */
    if (strcmp(name, "uncompress") == 0) return (void *)uncompress;
    if (strcmp(name, "compress2") == 0) return (void *)compress2;
    return NULL;
#else
    static void *zlib_handle = NULL;
    static int attempted = 0;
    void *symbol;

    symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol != NULL) return symbol;
    if (!attempted) {
        attempted = 1;
#ifdef __APPLE__
        zlib_handle = dlopen("libz.dylib", RTLD_NOW | RTLD_LOCAL);
#else
        zlib_handle = dlopen("libz.so.1", RTLD_NOW | RTLD_LOCAL);
#endif
    }
    return zlib_handle == NULL ? NULL : dlsym(zlib_handle, name);
#endif
}

int64_t mc_set_compression_threshold(int64_t threshold) {
    if (threshold < -1 || threshold > MC_CODEC_LIMIT) return -1;
    compression_threshold = (int)threshold;
    return 0;
}

int64_t mc_get_compression_threshold(void) {
    return compression_threshold;
}

int64_t mc_codec_reset(void) {
    codec_input_length = 0;
    codec_output_length = 0;
    return 0;
}

int64_t mc_codec_input_byte(int64_t value) {
    unsigned char *grown;
    size_t capacity;
    if (value < 0 || value > 255 || codec_input_length >= MC_CODEC_LIMIT) return -1;
    if (codec_input_length == codec_input_capacity) {
        capacity = codec_input_capacity == 0 ? 4096 : codec_input_capacity * 2;
        if (capacity > MC_CODEC_LIMIT) capacity = MC_CODEC_LIMIT;
        grown = (unsigned char *)realloc(codec_input, capacity);
        if (grown == NULL) return -1;
        codec_input = grown;
        codec_input_capacity = capacity;
    }
    codec_input[codec_input_length++] = (unsigned char)value;
    return 0;
}

int64_t mc_codec_run(int64_t inflate, int64_t expected_length) {
    typedef int (*uncompress_function)(Bytef *, uLongf *, const Bytef *, uLong);
    typedef int (*compress2_function)(Bytef *, uLongf *, const Bytef *, uLong, int);
    uncompress_function inflate_data = NULL;
    compress2_function deflate_data = NULL;
    void *symbol;
    uLongf output_length;
    size_t capacity;
    int result;

    if (codec_input_length == 0) return -1;
    if (inflate) {
        if (expected_length < 0 || expected_length > MC_CODEC_LIMIT) return -1;
        capacity = (size_t)expected_length;
    } else {
        capacity = codec_input_length + (codec_input_length >> 12) +
                   (codec_input_length >> 14) + (codec_input_length >> 25) + 64;
        if (capacity > MC_CODEC_LIMIT) return -1;
    }
    free(codec_output);
    codec_output = (unsigned char *)malloc(capacity == 0 ? 1 : capacity);
    if (codec_output == NULL) return -1;
    output_length = (uLongf)capacity;

    symbol = load_zlib_symbol(inflate ? "uncompress" : "compress2");
    if (symbol == NULL) return -1;
    if (inflate) {
        memcpy(&inflate_data, &symbol, sizeof(inflate_data));
        result = inflate_data(codec_output, &output_length, codec_input,
                              (uLong)codec_input_length);
    } else {
        memcpy(&deflate_data, &symbol, sizeof(deflate_data));
        result = deflate_data(codec_output, &output_length, codec_input,
                              (uLong)codec_input_length, Z_BEST_SPEED);
    }
    if (result != Z_OK || (inflate && output_length != (uLongf)expected_length)) {
        codec_output_length = 0;
        return -1;
    }
    codec_output_length = (size_t)output_length;
    return 0;
}

int64_t mc_codec_output_length(void) {
    return (int64_t)codec_output_length;
}

int64_t mc_codec_output_byte(int64_t index) {
    if (index < 0 || (uint64_t)index >= (uint64_t)codec_output_length) return -1;
    return codec_output[index];
}

double mc_double_from_be(int64_t b0, int64_t b1, int64_t b2, int64_t b3,
                         int64_t b4, int64_t b5, int64_t b6, int64_t b7) {
    uint64_t bits = ((uint64_t)(uint8_t)b0 << 56) | ((uint64_t)(uint8_t)b1 << 48) |
                    ((uint64_t)(uint8_t)b2 << 40) | ((uint64_t)(uint8_t)b3 << 32) |
                    ((uint64_t)(uint8_t)b4 << 24) | ((uint64_t)(uint8_t)b5 << 16) |
                    ((uint64_t)(uint8_t)b6 << 8) | (uint64_t)(uint8_t)b7;
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

double mc_float_from_be(int64_t b0, int64_t b1, int64_t b2, int64_t b3) {
    uint32_t bits = ((uint32_t)(uint8_t)b0 << 24) | ((uint32_t)(uint8_t)b1 << 16) |
                    ((uint32_t)(uint8_t)b2 << 8) | (uint32_t)(uint8_t)b3;
    float value;
    memcpy(&value, &bits, sizeof(value));
    return (double)value;
}

int64_t mc_double_be_byte(double value, int64_t index) {
    uint64_t bits;
    if (index < 0 || index >= 8) return -1;
    memcpy(&bits, &value, sizeof(bits));
    return (int64_t)((bits >> ((7 - index) * 8)) & 0xff);
}

int64_t mc_float_be_byte(double input, int64_t index) {
    uint32_t bits;
    float value = (float)input;
    if (index < 0 || index >= 4) return -1;
    memcpy(&bits, &value, sizeof(bits));
    return (int64_t)((bits >> ((3 - index) * 8)) & 0xff);
}

int64_t mc_tcp_connect(char *host, int64_t port) {
    char service[16];
    struct addrinfo hints;
    struct addrinfo *addresses = NULL;
    struct addrinfo *address;
    mc_socket fd = mc_socket_invalid;

    if (host == NULL || port < 1 || port > 65535) return -1;
    mc_start_winsock();
    compression_threshold = -1;
    snprintf(service, sizeof(service), "%lld", (long long)port);
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    if (getaddrinfo(host, service, &hints, &addresses) != 0) return -1;

    for (address = addresses; address != NULL; address = address->ai_next) {
        fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
        if (fd == mc_socket_invalid) continue;

#ifdef _WIN32
        {
            DWORD timeout = 10000;
#else
        {
            struct timeval timeout;
            timeout.tv_sec = 10;
            timeout.tv_usec = 0;
#endif
            if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout,
                           sizeof(timeout)) != 0 ||
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, (const char *)&timeout,
                           sizeof(timeout)) != 0) {
                mc_close_socket(fd);
                fd = mc_socket_invalid;
                continue;
            }
        }
#ifdef SO_NOSIGPIPE
        {
            int enabled = 1;
            if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled)) != 0) {
                mc_close_socket(fd);
                fd = mc_socket_invalid;
                continue;
            }
        }
#endif

        if (connect(fd, address->ai_addr, address->ai_addrlen) == 0) break;
        mc_close_socket(fd);
        fd = mc_socket_invalid;
    }

    freeaddrinfo(addresses);
    if (fd == mc_socket_invalid) return -1;
    return (int64_t)fd;
}

static unsigned char send_buffer[4096];
static size_t send_length = 0;
static mc_socket send_socket = mc_socket_invalid;

static int64_t flush_send_buffer(void) {
    size_t sent = 0;
    while (sent < send_length) {
        mc_ssize result;
#ifdef MSG_NOSIGNAL
        result = send(send_socket, (const char *)(send_buffer + sent),
                      (int)(send_length - sent), MSG_NOSIGNAL);
#else
        result = send(send_socket, (const char *)(send_buffer + sent),
                      (int)(send_length - sent), 0);
#endif
        if (result < 0 && mc_is_interrupted(mc_last_error())) continue;
        if (result <= 0) return -1;
        sent += (size_t)result;
    }
    send_length = 0;
    return 0;
}

int64_t mc_tcp_send_begin(int64_t socket_handle) {
    send_socket = (mc_socket)socket_handle;
    send_length = 0;
    return 0;
}

int64_t mc_tcp_send_byte(int64_t value) {
    if (value < 0 || value > 255) return -1;
    if (send_length == sizeof(send_buffer) && flush_send_buffer() != 0) return -1;
    send_buffer[send_length++] = (unsigned char)value;
    return 0;
}

int64_t mc_tcp_send_end(void) {
    return flush_send_buffer();
}

static unsigned char receive_buffer[4096];
static size_t receive_offset = 0;
static size_t receive_length = 0;
static mc_socket receive_socket = mc_socket_invalid;

int64_t mc_tcp_recv_byte(int64_t socket_handle) {
    mc_socket fd = (mc_socket)socket_handle;
    mc_ssize received;
    if (receive_socket != fd) {
        receive_socket = fd;
        receive_offset = 0;
        receive_length = 0;
    }
    if (receive_offset == receive_length) {
        do {
            received = recv(fd, (char *)receive_buffer, (int)sizeof(receive_buffer), 0);
        } while (received < 0 && mc_is_interrupted(mc_last_error()));
        if (received <= 0) return -1;
        receive_offset = 0;
        receive_length = (size_t)received;
    }
    return receive_buffer[receive_offset++];
}

int64_t mc_tcp_close(int64_t socket_handle) {
    compression_threshold = -1;
    if (receive_socket == (mc_socket)socket_handle) {
        receive_socket = mc_socket_invalid;
        receive_offset = 0;
        receive_length = 0;
    }
    if (send_socket == (mc_socket)socket_handle) send_socket = mc_socket_invalid;
    return (int64_t)mc_close_socket((mc_socket)socket_handle);
}

static char stdin_line[4097];
static char stdin_line_copies[8][4097];
static unsigned char stdin_pending[8192];
static size_t stdin_pending_length = 0;
static size_t stdin_line_length = 0;
static int stdin_line_ready = 0;
static int stdin_closed = 0;
static int stdin_input_error = 0;

static int extract_stdin_line(void) {
    size_t line_length = 0;
    size_t consumed = 0;

    if (stdin_line_ready) return 1;
    while (consumed < stdin_pending_length && stdin_pending[consumed] != '\n') {
        consumed++;
    }
    if (consumed == stdin_pending_length && !stdin_closed) return 0;
    line_length = consumed;
    if (line_length > 0 && stdin_pending[line_length - 1] == '\r') {
        line_length--;
    }
    if (line_length >= sizeof(stdin_line)) {
        stdin_input_error = 1;
        if (consumed < stdin_pending_length) consumed++;
        memmove(stdin_pending, stdin_pending + consumed, stdin_pending_length - consumed);
        stdin_pending_length -= consumed;
        return -1;
    }
    memcpy(stdin_line, stdin_pending, line_length);
    stdin_line[line_length] = '\0';
    stdin_line_length = line_length;
    stdin_line_ready = 1;
    if (consumed < stdin_pending_length) consumed++;
    memmove(stdin_pending, stdin_pending + consumed, stdin_pending_length - consumed);
    stdin_pending_length -= consumed;
    return 1;
}

#ifdef _WIN32
/* WSAPoll only understands sockets, so the terminal cannot sit in the same
 * poll set as the connection the way it does on POSIX. A worker thread blocks
 * in a terminal read instead and hands bytes over through stdin_pending:
 * stdin_lock guards that buffer, stdin_data_ready wakes whoever waits for
 * input, and stdin_space_ready wakes the worker once the consumer drains it. */
static CRITICAL_SECTION stdin_lock;
static CONDITION_VARIABLE stdin_data_ready;
static CONDITION_VARIABLE stdin_space_ready;
static HANDLE stdin_worker = NULL;

static unsigned __stdcall stdin_worker_thread(void *argument) {
    unsigned char input[4096];
    size_t room;
    int received;

    (void)argument;
    for (;;) {
        EnterCriticalSection(&stdin_lock);
        while (stdin_pending_length == sizeof(stdin_pending) && !stdin_input_error) {
            WakeConditionVariable(&stdin_space_ready);
            SleepConditionVariableCS(&stdin_data_ready, &stdin_lock, 200);
        }
        room = sizeof(stdin_pending) - stdin_pending_length;
        LeaveCriticalSection(&stdin_lock);

        received = _read(mc_stdin_fd(), input,
                         room < sizeof(input) ? (unsigned)room : (unsigned)sizeof(input));
        if (received <= 0) {
            EnterCriticalSection(&stdin_lock);
            fprintf(stderr, "[w%lu] terminal received=%d closed=%d pending=%u\n",
                    (unsigned long)GetTickCount(), received, stdin_closed,
                    (unsigned)stdin_pending_length);
            if (received == 0) stdin_closed = 1; else stdin_input_error = 1;
            WakeAllConditionVariable(&stdin_data_ready);
            LeaveCriticalSection(&stdin_lock);
            return 0;
        }
        fprintf(stderr, "[w%lu] append %d -> pending=%u\n",
                (unsigned long)GetTickCount(), received,
                (unsigned)stdin_pending_length);
        EnterCriticalSection(&stdin_lock);
        memcpy(stdin_pending + stdin_pending_length, input, (size_t)received);
        stdin_pending_length += (size_t)received;
        WakeAllConditionVariable(&stdin_data_ready);
        LeaveCriticalSection(&stdin_lock);
    }
}
#endif

static int collect_stdin_line(void) {
#ifdef _WIN32
    int extracted;

    EnterCriticalSection(&stdin_lock);
    extracted = extract_stdin_line();
    if (extracted == 0 && !stdin_closed && !stdin_input_error) {
        WakeConditionVariable(&stdin_space_ready);
        SleepConditionVariableCS(&stdin_data_ready, &stdin_lock, 20);
        extracted = extract_stdin_line();
    }
    if (extracted > 0) WakeConditionVariable(&stdin_space_ready);
    LeaveCriticalSection(&stdin_lock);
    if (extracted == 0 && stdin_pending_length == sizeof(stdin_pending)) {
        stdin_input_error = 1;
        return -1;
    }
    return extracted;
#else
    unsigned char input[4096];
    mc_ssize received;
    int extracted = extract_stdin_line();

    if (extracted != 0) return extracted;
    if (stdin_pending_length == sizeof(stdin_pending)) {
        stdin_input_error = 1;
        return -1;
    }
    do {
        received = read(STDIN_FILENO, input,
                        sizeof(stdin_pending) - stdin_pending_length < sizeof(input)
                            ? sizeof(stdin_pending) - stdin_pending_length
                            : sizeof(input));
    } while (received < 0 && mc_is_interrupted(mc_last_error()));
    if (received == 0) {
        stdin_closed = 1;
    } else if (received < 0) {
        if (mc_is_would_block(mc_last_error())) return 0;
        stdin_input_error = 1;
        return -1;
    } else {
        memcpy(stdin_pending + stdin_pending_length, input, (size_t)received);
        stdin_pending_length += (size_t)received;
    }
    return extract_stdin_line();
#endif
}

int64_t mc_prepare_stdin(void) {
#ifdef _WIN32
    uintptr_t handle;
    if (stdin_worker != NULL) return 0;
    InitializeCriticalSection(&stdin_lock);
    InitializeConditionVariable(&stdin_data_ready);
    InitializeConditionVariable(&stdin_space_ready);
    handle = _beginthreadex(NULL, 0, stdin_worker_thread, NULL, 0, NULL);
    if (handle == 0) return -1;
    stdin_worker = (HANDLE)handle;
    return 0;
#else
    return 0;
#endif
}

int64_t mc_poll_events(int64_t socket_handle) {
    int events = 0;
#ifdef _WIN32
    mc_pollfd descriptor;
    mc_socket fd = (mc_socket)socket_handle;
    int collected;
    int result;

    mc_start_winsock();
    if (receive_socket == fd && receive_offset < receive_length) return 1;

    descriptor.fd = fd;
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    result = mc_poll_socket(&descriptor, 1, 80);
    if (result == mc_socket_error && !mc_is_would_block(mc_last_error())) return -1;
    if (result > 0 && (descriptor.revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL))) {
        return 1;
    }

    if (stdin_line_ready) return 2;
    if (stdin_closed) return 4;
    collected = collect_stdin_line();
    if (collected < 0 || stdin_input_error) return -1;
    if (collected > 0) events |= 2;
    return events;
#else
    struct pollfd descriptors[2];
    int result;
    int buffered_socket_data =
        receive_socket == (int)socket_handle && receive_offset < receive_length;

    descriptors[0].fd = buffered_socket_data ? -1 : (int)socket_handle;
    descriptors[0].events = buffered_socket_data ? 0 : POLLIN;
    descriptors[0].revents = 0;
    descriptors[1].fd = STDIN_FILENO;
    descriptors[1].events = stdin_closed || stdin_line_ready || stdin_input_error ? 0 : POLLIN;
    descriptors[1].revents = 0;
    if (buffered_socket_data) events |= 1;
    do {
        result = poll(descriptors, 2, 100);
    } while (result < 0 && errno == EINTR);
    if (result < 0) return -1;

    if (descriptors[0].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
        events |= 1;
    }
    if (events & 1) return events;
    if (stdin_line_ready) {
        events |= 2;
    } else if (!stdin_closed &&
               descriptors[1].revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)) {
        int collected = collect_stdin_line();
        if (collected < 0) return -1;
        if (collected > 0) events |= 2;
    } else if (stdin_closed) {
        events |= 4;
    }
    if (stdin_input_error) return -1;
    return events;
#endif
}

int64_t mc_stdin_line_length(void) {
    return stdin_line_ready ? (int64_t)stdin_line_length : -1;
}

int64_t mc_stdin_read_line(void) {
#ifdef _WIN32
    int64_t result;

    EnterCriticalSection(&stdin_lock);
    result = stdin_line_ready ? (int64_t)stdin_line_length : -1;
    while (result < 0 && !stdin_input_error) {
        int extracted = extract_stdin_line();
        fprintf(stderr, "[r%lu] extract=%d ready=%d len=%u\n",
                (unsigned long)GetTickCount(), extracted, stdin_line_ready,
                (unsigned)stdin_line_length);
        if (extracted > 0) {
            result = (int64_t)stdin_line_length;
            break;
        }
        if (extracted < 0) {
            result = -3;
            break;
        }
        fprintf(stderr, "[r%lu] pre-sleep closed=%d pending=%u ready=%d\n",
                (unsigned long)GetTickCount(), stdin_closed,
                (unsigned)stdin_pending_length, stdin_line_ready);
        WakeConditionVariable(&stdin_space_ready);
        SleepConditionVariableCS(&stdin_data_ready, &stdin_lock, 3000);
        fprintf(stderr, "[r%lu] post-wake closed=%d pending=%u ready=%d\n",
                (unsigned long)GetTickCount(), stdin_closed,
                (unsigned)stdin_pending_length, stdin_line_ready);
    }
    if (result >= 0) WakeConditionVariable(&stdin_space_ready);
    LeaveCriticalSection(&stdin_lock);
    return result;
#else
    unsigned char input[4096];
    if (stdin_line_ready) return (int64_t)stdin_line_length;
    while (!stdin_input_error) {
        int extracted = extract_stdin_line();
        if (extracted < 0) return -3;
        if (extracted > 0) return (int64_t)stdin_line_length;
        ssize_t received;
        do {
            received = read(STDIN_FILENO, input,
                            sizeof(stdin_pending) - stdin_pending_length < sizeof(input)
                                ? sizeof(stdin_pending) - stdin_pending_length
                                : sizeof(input));
        } while (received < 0 && errno == EINTR);
        if (received == 0) {
            stdin_closed = 1;
            extracted = extract_stdin_line();
            return extracted > 0 ? (int64_t)stdin_line_length : -2;
        }
        if (received < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                struct pollfd descriptor = {STDIN_FILENO, POLLIN, 0};
                int result;
                do {
                    result = poll(&descriptor, 1, -1);
                } while (result < 0 && errno == EINTR);
                if (result > 0 &&
                    (descriptor.revents & (POLLIN | POLLHUP | POLLERR))) {
                    continue;
                }
                stdin_input_error = 1;
                return -1;
            }
            stdin_input_error = 1;
            return -1;
        }
        if (stdin_pending_length + (size_t)received > sizeof(stdin_pending)) {
            stdin_input_error = 1;
            return -3;
        }
        memcpy(stdin_pending + stdin_pending_length, input, (size_t)received);
        stdin_pending_length += (size_t)received;
    }
    return -1;
#endif
}

int64_t mc_stdin_line_byte(int64_t index) {
    if (!stdin_line_ready || index < 0 || (uint64_t)index >= stdin_line_length) {
        return -1;
    }
    return (unsigned char)stdin_line[index];
}

char* mc_stdin_line_copy(int64_t slot) {
    if (!stdin_line_ready || slot < 0 || slot >= 8) return NULL;
    memcpy(stdin_line_copies[slot], stdin_line, stdin_line_length + 1);
    return stdin_line_copies[slot];
}

int64_t mc_stdin_line_done(void) {
#ifdef _WIN32
    EnterCriticalSection(&stdin_lock);
#endif
    stdin_line_length = 0;
    stdin_line_ready = 0;
    stdin_line[0] = '\0';
    if (stdin_closed && stdin_pending_length > 0) stdin_closed = 0;
#ifdef _WIN32
    WakeConditionVariable(&stdin_space_ready);
    LeaveCriticalSection(&stdin_lock);
#endif
    return 0;
}

double mc_parse_finite_stdin_line(void) {
    char *end = NULL;
    double value;
    if (!stdin_line_ready) return NAN;
    value = strtod(stdin_line, &end);
    if (end == stdin_line || *end != '\0' || !isfinite(value)) return NAN;
    return value;
}

int64_t mc_time_millis(void) {
#ifdef _WIN32
    /* FILETIME counts 100 ns steps from 1601-01-01; the difference to the Unix
     * epoch is 116444736e9 of those steps. */
    FILETIME now;
    ULARGE_INTEGER units;
    GetSystemTimeAsFileTime(&now);
    units.LowPart = now.dwLowDateTime;
    units.HighPart = now.dwHighDateTime;
    if (units.QuadPart < 116444736000000000ULL) return -1;
    return (int64_t)((units.QuadPart - 116444736000000000ULL) / 10000ULL);
#else
    struct timeval now;
    if (gettimeofday(&now, NULL) != 0) return -1;
    return (int64_t)now.tv_sec * 1000 + (int64_t)now.tv_usec / 1000;
#endif
}

int64_t mc_string_length(char *text) {
    return text == NULL ? -1 : (int64_t)strlen(text);
}

int64_t mc_string_byte(char *text, int64_t index) {
    size_t length;
    if (text == NULL || index < 0) return -1;
    length = strlen(text);
    if ((uint64_t)index >= (uint64_t)length) return -1;
    return (unsigned char)text[index];
}

double mc_parse_finite_double(char *text) {
    char *end = NULL;
    double value;
    if (text == NULL) return NAN;
    value = strtod(text, &end);
    if (end == text || *end != '\0' || !isfinite(value)) return NAN;
    return value;
}

int64_t mc_is_finite_double(double value) {
    return isfinite(value) ? 1 : 0;
}

int64_t mc_offline_uuid_byte(char *name, int64_t index) {
    static const uint32_t shifts[64] = {
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    };
    static const uint32_t constants[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    };
    unsigned char block[64] = {0};
    uint32_t words[16];
    uint32_t a0 = 0x67452301, b0 = 0xefcdab89;
    uint32_t c0 = 0x98badcfe, d0 = 0x10325476;
    uint32_t a, b, c, d;
    size_t name_length;
    size_t message_length;
    int i;

    if (name == NULL || index < 0 || index >= 16) return -1;
    name_length = strlen(name);
    if (name_length < 1 || name_length > 16) return -1;
    memcpy(block, "OfflinePlayer:", 14);
    memcpy(block + 14, name, name_length);
    message_length = 14 + name_length;
    block[message_length] = 0x80;
    block[56] = (unsigned char)((message_length * 8) & 0xff);
    block[57] = (unsigned char)(((message_length * 8) >> 8) & 0xff);
    block[58] = (unsigned char)(((message_length * 8) >> 16) & 0xff);
    block[59] = (unsigned char)(((message_length * 8) >> 24) & 0xff);
    for (i = 0; i < 16; i++) {
        words[i] = (uint32_t)block[i * 4] |
                   ((uint32_t)block[i * 4 + 1] << 8) |
                   ((uint32_t)block[i * 4 + 2] << 16) |
                   ((uint32_t)block[i * 4 + 3] << 24);
    }

    a = a0; b = b0; c = c0; d = d0;
    for (i = 0; i < 64; i++) {
        uint32_t f;
        uint32_t g;
        if (i < 16) {
            f = (b & c) | (~b & d);
            g = (uint32_t)i;
        } else if (i < 32) {
            f = (d & b) | (~d & c);
            g = (uint32_t)((5 * i + 1) % 16);
        } else if (i < 48) {
            f = b ^ c ^ d;
            g = (uint32_t)((3 * i + 5) % 16);
        } else {
            f = c ^ (b | ~d);
            g = (uint32_t)((7 * i) % 16);
        }
        f += a + constants[i] + words[g];
        a = d;
        d = c;
        c = b;
        b += (f << shifts[i]) | (f >> (32 - shifts[i]));
    }
    a0 += a; b0 += b; c0 += c; d0 += d;
    {
        uint32_t state[4] = {a0, b0, c0, d0};
        unsigned char digest[16];
        int j;
        for (j = 0; j < 4; j++) {
            digest[j * 4] = (unsigned char)(state[j] & 0xff);
            digest[j * 4 + 1] = (unsigned char)((state[j] >> 8) & 0xff);
            digest[j * 4 + 2] = (unsigned char)((state[j] >> 16) & 0xff);
            digest[j * 4 + 3] = (unsigned char)((state[j] >> 24) & 0xff);
        }
        digest[6] = (unsigned char)((digest[6] & 0x0f) | 0x30);
        digest[8] = (unsigned char)((digest[8] & 0x3f) | 0x80);
        return digest[index];
    }
}

void mc_write_byte(int64_t value) {
    if (value >= 0 && value <= 255) {
        unsigned char byte = (unsigned char)value;
        fwrite(&byte, 1, 1, stdout);
    }
}
