/* Vortex engine - parallel greedy section mesher.
 *
 * The Cpyte mesher in world/mesher.cpy is the readable reference and the
 * small-world API. This file is the production path: sections are meshed by a
 * persistent worker pool, per-section snapshots remove the paletted-container
 * and light decoding from the inner face loop, and each worker writes into its
 * own growable vertex/index buffers so no locks are taken while meshing.
 *
 * Workers never allocate through the Cpyte GC. They only read decoded section
 * data through the accessor functions below and write malloc'd buffers; the
 * caller copies or uploads the result on the main thread. That keeps a
 * collection on the main thread from mistaking a worker's stack for a root
 * set, and keeps the GC out of the mesh critical path.
 *
 * A face's neighbour is at most one block outside the section, so a section
 * job needs the centre section plus the six face-adjacent sections. The
 * boundary planes of those neighbours are decoded once per job instead of a
 * world lookup per face.
 *
 * Cross-platform: pthreads on macOS/Linux, Win32 threads on Windows.
 */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <pthread.h>
#  include <unistd.h>
#endif

/* ---- Cpyte-side accessors (compiled in their own module) ------------------ */

extern int sec_block_at(void* section, int x, int y, int z);
extern int sec_block_at_index(void* section, int index);
extern int sec_light_packed_at(void* section, int x, int y, int z);
extern int sec_light_packed_index(void* section, int index);
extern void* vworld_section(void* world, int chunk_x, int chunk_z, int section_y);
extern uint32_t vt_blockdb_render(int state);

/* ---- block flags, matching tools/gen_blockdb.py --------------------------- */

#define VT_AIR        1
#define VT_CUBE       4
#define VT_OPAQUE     8
#define VT_TRANSLUCENT 16
#define VT_LEAVES     32
#define VT_CROSS      64

#define VT_STRIDE 9
#define VT_KIND_SCALE 1000000000u
#define VT_UNKNOWN_LAYER 65535u
#define VT_FULL_SKY (15 * 16)

/* ---- growable int64 buffer ------------------------------------------------ */

typedef struct {
    int64_t* data;
    size_t len;
    size_t cap;
} VTBuf;

static int vtbuf_reserve(VTBuf* b, size_t extra) {
    size_t need = b->len + extra;
    size_t cap;
    int64_t* next;
    if (need <= b->cap) return 1;
    cap = b->cap > 0 ? b->cap : 1024;
    while (cap < need) {
        if (cap > (size_t)1 << 40) return 0;
        cap *= 2;
    }
    next = (int64_t*)realloc(b->data, cap * sizeof(int64_t));
    if (next == 0) return 0;
    b->data = next;
    b->cap = cap;
    return 1;
}

static void vtbuf_free(VTBuf* b) {
    free(b->data);
    b->data = 0;
    b->len = 0;
    b->cap = 0;
}

/* ---- per-section output --------------------------------------------------- */

typedef struct {
    VTBuf verts[2];
    VTBuf indices[2];
    int quads[2];
    int sections;
    int failed;
} VTOut;

static void vt_out_free(VTOut* out) {
    vtbuf_free(&out->verts[0]);
    vtbuf_free(&out->verts[1]);
    vtbuf_free(&out->indices[0]);
    vtbuf_free(&out->indices[1]);
    memset(out, 0, sizeof(*out));
}

/* ---- job and snapshot ----------------------------------------------------- */

typedef struct {
    void* center;
    void* neighbors[6];
    int base_x;
    int base_y;
    int base_z;
    int chunk_x;
    int chunk_y;
    int chunk_z;
} VTJob;

#define VT_SECTION_CELLS 4096
#define VT_PLANE_CELLS 256

typedef struct {
    uint32_t states[VT_SECTION_CELLS];
    uint32_t render[VT_SECTION_CELLS];
    uint8_t light[VT_SECTION_CELLS];
    uint16_t plane_state[6][VT_PLANE_CELLS];
    uint32_t plane_render[6][VT_PLANE_CELLS];
    uint8_t plane_light[6][VT_PLANE_CELLS];
} VTSnap;

static VTSnap* vt_snap_new(void) {
    VTSnap* snap = (VTSnap*)calloc(1, sizeof(VTSnap));
    return snap;
}

static void vt_snap_free(VTSnap* snap) {
    free(snap);
}

static int vt_face_hides(uint32_t near_render, uint32_t far_render) {
    uint32_t nf = near_render & 0xFFu;
    uint32_t ff = far_render & 0xFFu;
    uint32_t np, fp;
    if ((nf & VT_CUBE) == 0 || (nf & VT_AIR) != 0) return 0;
    if ((ff & VT_AIR) != 0) return 0;
    if ((ff & VT_OPAQUE) != 0) return 1;
    if ((nf & VT_LEAVES) != 0 && (ff & VT_LEAVES) != 0) return 1;
    if ((nf & VT_TRANSLUCENT) != 0 && (ff & VT_TRANSLUCENT) != 0) {
        np = near_render >> 8;
        fp = far_render >> 8;
        if (np != 0 && np == fp) return 1;
    }
    return 0;
}

static uint32_t vt_face_key(uint32_t state, uint32_t render, uint32_t light) {
    uint32_t flags = render & 0xFFu;
    uint32_t layer_code = render >> 8;
    uint32_t layer;
    uint32_t kind;
    if (state == 0) return 0;
    if ((flags & VT_CUBE) == 0) return 0;
    if (layer_code == 0) {
        layer = VT_UNKNOWN_LAYER;
    } else {
        layer = layer_code - 1;
    }
    kind = (flags & VT_TRANSLUCENT) != 0 ? 1u : 0u;
    return kind * VT_KIND_SCALE + (layer + 1) * 256u + light;
}

/* Centre index: x + z*16 + y*256. */
static int vt_cell_index(int x, int y, int z) {
    return x + (z << 4) + (y << 8);
}

/* Plane index for the face-adjacent section of direction dir. */
static int vt_plane_index(int dir, int a, int b) {
    if (dir == 0 || dir == 1) return b + (a << 4);   /* X: u=y, v=z */
    if (dir == 2 || dir == 3) return a + (b << 4);   /* Y: u=x, v=z */
    return a + (b << 4);                             /* Z: u=x, v=y */
}

static void vt_snapshot(VTSnap* snap, VTJob* job) {
    int i;
    int dir;
    if (job->center == 0) return;
    for (i = 0; i < VT_SECTION_CELLS; i++) {
        uint32_t state = (uint32_t)sec_block_at_index(job->center, i);
        snap->states[i] = state;
        snap->render[i] = vt_blockdb_render((int)state);
        snap->light[i] = (uint8_t)sec_light_packed_index(job->center, i);
    }
    for (dir = 0; dir < 6; dir++) {
        void* neighbor = job->neighbors[dir];
        int a, b;
        for (a = 0; a < 16; a++) {
            for (b = 0; b < 16; b++) {
                int p = vt_plane_index(dir, a, b);
                int x = 0, y = 0, z = 0;
                uint32_t state = 0;
                int light = VT_FULL_SKY;
                if (dir == 0) { x = 0; y = b; z = a; }
                else if (dir == 1) { x = 15; y = b; z = a; }
                else if (dir == 2) { x = a; y = 0; z = b; }
                else if (dir == 3) { x = a; y = 15; z = b; }
                else if (dir == 4) { x = a; y = b; z = 0; }
                else { x = a; y = b; z = 15; }
                if (neighbor != 0) {
                    state = (uint32_t)sec_block_at(neighbor, x, y, z);
                    light = sec_light_packed_at(neighbor, x, y, z);
                }
                snap->plane_state[dir][p] = (uint16_t)(state > 65535u ? 65535u : state);
                snap->plane_render[dir][p] = vt_blockdb_render((int)state);
                snap->plane_light[dir][p] = (uint8_t)light;
            }
        }
    }
}

/* ---- quad emission -------------------------------------------------------- */

static void vt_emit_quad(VTOut* out, int translucent,
                         int x0, int y0, int z0,
                         int x1, int y1, int z1,
                         int x2, int y2, int z2,
                         int x3, int y3, int z3,
                         int width, int height, uint32_t layer,
                         uint32_t sky, uint32_t block, uint32_t face) {
    VTBuf* verts = &out->verts[translucent];
    VTBuf* indices = &out->indices[translucent];
    int64_t base;
    int64_t* v;
    int64_t* ix;
    if (out->failed) return;
    if (!vtbuf_reserve(verts, VT_STRIDE * 4) || !vtbuf_reserve(indices, 6)) {
        out->failed = 1;
        return;
    }
    base = (int64_t)(verts->len / VT_STRIDE);
    v = verts->data + verts->len;
    v[0] = (int64_t)x0; v[1] = (int64_t)y0; v[2] = (int64_t)z0;
    v[3] = 0; v[4] = 0; v[5] = (int64_t)layer;
    v[6] = (int64_t)sky; v[7] = (int64_t)block; v[8] = (int64_t)face;
    v[9] = (int64_t)x1; v[10] = (int64_t)y1; v[11] = (int64_t)z1;
    v[12] = (int64_t)width; v[13] = 0; v[14] = (int64_t)layer;
    v[15] = (int64_t)sky; v[16] = (int64_t)block; v[17] = (int64_t)face;
    v[18] = (int64_t)x2; v[19] = (int64_t)y2; v[20] = (int64_t)z2;
    v[21] = (int64_t)width; v[22] = (int64_t)height; v[23] = (int64_t)layer;
    v[24] = (int64_t)sky; v[25] = (int64_t)block; v[26] = (int64_t)face;
    v[27] = (int64_t)x3; v[28] = (int64_t)y3; v[29] = (int64_t)z3;
    v[30] = 0; v[31] = (int64_t)height; v[32] = (int64_t)layer;
    v[33] = (int64_t)sky; v[34] = (int64_t)block; v[35] = (int64_t)face;
    verts->len += VT_STRIDE * 4;
    ix = indices->data + indices->len;
    ix[0] = base; ix[1] = base + 1; ix[2] = base + 2;
    ix[3] = base; ix[4] = base + 2; ix[5] = base + 3;
    indices->len += 6;
    out->quads[translucent] += 1;
}

static void vt_emit_rect(VTOut* out, int translucent, int dir, int slice,
                         int base_x, int base_y, int base_z,
                         int a, int b, int width_a, int width_b,
                         uint32_t layer, uint32_t sky, uint32_t block) {
    int x = base_x + slice;
    int y = base_y + slice;
    int z = base_z + slice;
    switch (dir) {
    case 0:
        vt_emit_quad(out, translucent,
                     x + 1, base_y + b, base_z + a,
                     x + 1, base_y + b + width_b, base_z + a,
                     x + 1, base_y + b + width_b, base_z + a + width_a,
                     x + 1, base_y + b, base_z + a + width_a,
                     width_b, width_a, layer, sky, block, (uint32_t)dir);
        break;
    case 1:
        vt_emit_quad(out, translucent,
                     x, base_y + b, base_z + a + width_a,
                     x, base_y + b + width_b, base_z + a + width_a,
                     x, base_y + b + width_b, base_z + a,
                     x, base_y + b, base_z + a,
                     width_b, width_a, layer, sky, block, (uint32_t)dir);
        break;
    case 2:
        vt_emit_quad(out, translucent,
                     base_x + a, y + 1, base_z + b,
                     base_x + a, y + 1, base_z + b + width_b,
                     base_x + a + width_a, y + 1, base_z + b + width_b,
                     base_x + a + width_a, y + 1, base_z + b,
                     width_a, width_b, layer, sky, block, (uint32_t)dir);
        break;
    case 3:
        vt_emit_quad(out, translucent,
                     base_x + a, y, base_z + b,
                     base_x + a + width_a, y, base_z + b,
                     base_x + a + width_a, y, base_z + b + width_b,
                     base_x + a, y, base_z + b + width_b,
                     width_a, width_b, layer, sky, block, (uint32_t)dir);
        break;
    case 4:
        vt_emit_quad(out, translucent,
                     base_x + a, base_y + b, z + 1,
                     base_x + a + width_a, base_y + b, z + 1,
                     base_x + a + width_a, base_y + b + width_b, z + 1,
                     base_x + a, base_y + b + width_b, z + 1,
                     width_a, width_b, layer, sky, block, (uint32_t)dir);
        break;
    default:
        vt_emit_quad(out, translucent,
                     base_x + a + width_a, base_y + b, z,
                     base_x + a, base_y + b, z,
                     base_x + a, base_y + b + width_b, z,
                     base_x + a + width_a, base_y + b + width_b, z,
                     width_a, width_b, layer, sky, block, (uint32_t)dir);
        break;
    }
}

/* Merge equal mask cells into maximal rectangles, width along b then a. */
static void vt_greedy(VTOut* out, uint32_t* mask, int dir, int slice,
                      int base_x, int base_y, int base_z) {
    int a = 0;
    while (a < 16) {
        int b = 0;
        while (b < 16) {
            uint32_t key = mask[a + (b << 4)];
            if (key != 0) {
                int width_b = 1;
                int width_a = 1;
                int grow = 1;
                uint32_t kind;
                uint32_t rest;
                uint32_t layer;
                uint32_t sky;
                uint32_t block;
                int translucent;
                while (b + width_b < 16 &&
                       mask[a + ((b + width_b) << 4)] == key) {
                    width_b += 1;
                }
                while (a + width_a < 16 && grow) {
                    int i;
                    for (i = 0; i < width_b; i++) {
                        if (mask[(a + width_a) + ((b + i) << 4)] != key) {
                            grow = 0;
                            break;
                        }
                    }
                    if (grow) width_a += 1;
                }
                kind = key / VT_KIND_SCALE;
                rest = key % VT_KIND_SCALE;
                layer = rest / 256u - 1u;
                sky = (rest % 256u) / 16u;
                block = rest % 16u;
                translucent = kind == 1u;
                vt_emit_rect(out, translucent, dir, slice, base_x, base_y,
                             base_z, a, b, width_a, width_b, layer, sky,
                             block);
                {
                    int ai;
                    for (ai = 0; ai < width_a; ai++) {
                        int bi;
                        for (bi = 0; bi < width_b; bi++) {
                            mask[(a + ai) + ((b + bi) << 4)] = 0;
                        }
                    }
                }
                b += width_b;
            } else {
                b += 1;
            }
        }
        a += 1;
    }
}

/* ---- one section --------------------------------------------------------- */

static void vt_mesh_one(VTSnap* snap, VTJob* job, VTOut* out) {
    static const int dx[6] = { 1, -1, 0, 0, 0, 0 };
    static const int dy[6] = { 0, 0, 1, -1, 0, 0 };
    static const int dz[6] = { 0, 0, 0, 0, 1, -1 };
    uint32_t mask[VT_PLANE_CELLS];
    int dir;
    int i;
    out->sections = 0;
    out->quads[0] = 0;
    out->quads[1] = 0;
    if (job->center == 0) return;
    vt_snapshot(snap, job);
    out->sections = 1;

    for (dir = 0; dir < 6; dir++) {
        int slice;
        int outside = dir == 0 || dir == 2 || dir == 4;
        for (slice = 0; slice < 16; slice++) {
            int boundary = outside ? slice == 15 : slice == 0;
            int a;
            for (a = 0; a < 16; a++) {
                int b;
                for (b = 0; b < 16; b++) {
                    int x, y, z;
                    uint32_t state;
                    uint32_t render;
                    uint32_t nx, ny, nz;
                    uint32_t far_state, far_render;
                    uint32_t light;
                    if (dir == 0) { x = slice; y = b; z = a; }
                    else if (dir == 1) { x = slice; y = b; z = a; }
                    else if (dir == 2) { x = a; y = slice; z = b; }
                    else if (dir == 3) { x = a; y = slice; z = b; }
                    else if (dir == 4) { x = a; y = b; z = slice; }
                    else { x = a; y = b; z = slice; }
                    state = snap->states[vt_cell_index(x, y, z)];
                    render = snap->render[vt_cell_index(x, y, z)];
                    if (state == 0 || (render & VT_CUBE) == 0) {
                        mask[a + (b << 4)] = 0;
                        continue;
                    }
                    nx = (uint32_t)(x + dx[dir]);
                    ny = (uint32_t)(y + dy[dir]);
                    nz = (uint32_t)(z + dz[dir]);
                    if (boundary) {
                        int p = vt_plane_index(dir, a, b);
                        far_state = snap->plane_state[dir][p];
                        far_render = snap->plane_render[dir][p];
                        light = snap->plane_light[dir][p];
                    } else {
                        far_state = snap->states[vt_cell_index((int)nx, (int)ny, (int)nz)];
                        far_render = snap->render[vt_cell_index((int)nx, (int)ny, (int)nz)];
                        light = snap->light[vt_cell_index((int)nx, (int)ny, (int)nz)];
                    }
                    (void)far_state;
                    if (vt_face_hides(render, far_render)) {
                        mask[a + (b << 4)] = 0;
                    } else {
                        mask[a + (b << 4)] = vt_face_key(state, render, light);
                    }
                }
            }
            vt_greedy(out, mask, dir, slice, job->base_x, job->base_y,
                      job->base_z);
        }
    }

    /* Cross-shaped plants, visible from either side. */
    for (i = 0; i < VT_SECTION_CELLS; i++) {
        uint32_t state = snap->states[i];
        uint32_t render;
        uint32_t flags;
        uint32_t layer;
        uint32_t light;
        int x, y, z;
        int x0, y0, z0;
        if (state == 0) continue;
        render = snap->render[i];
        flags = render & 0xFFu;
        if ((flags & VT_CROSS) == 0) continue;
        layer = render >> 8;
        if (layer == 0) layer = VT_UNKNOWN_LAYER + 1u;
        layer = layer - 1u;
        light = snap->light[i];
        x = i & 15;
        z = (i >> 4) & 15;
        y = (i >> 8) & 15;
        x0 = job->base_x + x;
        y0 = job->base_y + y;
        z0 = job->base_z + z;
        vt_emit_quad(out, 0,
                     x0, y0, z0, x0 + 1, y0, z0 + 1,
                     x0 + 1, y0 + 1, z0 + 1, x0, y0 + 1, z0,
                     1, 1, layer, light / 16u, light % 16u, 6);
        vt_emit_quad(out, 0,
                     x0, y0 + 1, z0, x0 + 1, y0 + 1, z0 + 1,
                     x0 + 1, y0, z0 + 1, x0, y0, z0,
                     1, 1, layer, light / 16u, light % 16u, 6);
        vt_emit_quad(out, 0,
                     x0 + 1, y0, z0, x0, y0, z0 + 1,
                     x0, y0 + 1, z0 + 1, x0 + 1, y0 + 1, z0,
                     1, 1, layer, light / 16u, light % 16u, 6);
        vt_emit_quad(out, 0,
                     x0 + 1, y0 + 1, z0, x0, y0 + 1, z0 + 1,
                     x0, y0, z0 + 1, x0 + 1, y0, z0,
                     1, 1, layer, light / 16u, light % 16u, 6);
    }
}

/* ---- thread pool --------------------------------------------------------- */

#ifdef _WIN32

typedef CRITICAL_SECTION vt_mutex;
typedef CONDITION_VARIABLE vt_cond;
typedef HANDLE vt_thread;
typedef DWORD(WINAPI* vt_thread_fn)(LPVOID);

static void vt_mutex_init(vt_mutex* m) { InitializeCriticalSection(m); }
static void vt_mutex_destroy(vt_mutex* m) { DeleteCriticalSection(m); }
static void vt_mutex_lock(vt_mutex* m) { EnterCriticalSection(m); }
static void vt_mutex_unlock(vt_mutex* m) { LeaveCriticalSection(m); }
static void vt_cond_init(vt_cond* c) { InitializeConditionVariable(c); }
static void vt_cond_destroy(vt_cond* c) { (void)c; }
static void vt_cond_wait(vt_cond* c, vt_mutex* m) {
    SleepConditionVariableCS(c, m, INFINITE);
}
static void vt_cond_signal(vt_cond* c) { WakeConditionVariable(c); }
static void vt_cond_broadcast(vt_cond* c) { WakeAllConditionVariable(c); }
static int vt_thread_start(vt_thread* t, vt_thread_fn fn, void* arg) {
    *t = CreateThread(0, 0, fn, arg, 0, 0);
    return *t != 0 ? 1 : 0;
}
static void vt_thread_join(vt_thread t) {
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);
}

#else

typedef pthread_mutex_t vt_mutex;
typedef pthread_cond_t vt_cond;
typedef pthread_t vt_thread;
typedef void* (*vt_thread_fn)(void*);

static void vt_mutex_init(vt_mutex* m) { pthread_mutex_init(m, 0); }
static void vt_mutex_destroy(vt_mutex* m) { pthread_mutex_destroy(m); }
static void vt_mutex_lock(vt_mutex* m) { pthread_mutex_lock(m); }
static void vt_mutex_unlock(vt_mutex* m) { pthread_mutex_unlock(m); }
static void vt_cond_init(vt_cond* c) { pthread_cond_init(c, 0); }
static void vt_cond_destroy(vt_cond* c) { pthread_cond_destroy(c); }
static void vt_cond_wait(vt_cond* c, vt_mutex* m) {
    pthread_cond_wait(c, m);
}
static void vt_cond_signal(vt_cond* c) { pthread_cond_signal(c); }
static void vt_cond_broadcast(vt_cond* c) { pthread_cond_broadcast(c); }
static int vt_thread_start(vt_thread* t, vt_thread_fn fn, void* arg) {
    return pthread_create(t, 0, fn, arg) == 0 ? 1 : 0;
}
static void vt_thread_join(vt_thread t) { pthread_join(t, 0); }

#endif

typedef struct {
    vt_mutex lock;
    vt_cond work;
    vt_cond done;
    vt_thread* threads;
    int thread_count;
    VTJob* jobs;
    VTOut* outs;
    int job_count;
    int next_job;
    int pending;
    unsigned generation;
    int shutdown;
    int started;
} VTPool;

static VTPool vt_pool;
static int vt_pool_ready = 0;

static int vt_core_count(void) {
#ifdef _WIN32
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwNumberOfProcessors > 0 ? (int)info.dwNumberOfProcessors : 1;
#else
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 1;
#endif
}

#ifdef _WIN32
static DWORD WINAPI vt_worker_entry(LPVOID arg) {
#else
static void* vt_worker_entry(void* arg) {
#endif
    VTPool* pool = (VTPool*)arg;
    VTSnap* snap = vt_snap_new();
    unsigned seen = 0;
    if (snap == 0) {
#ifdef _WIN32
        return 1;
#else
        return 0;
#endif
    }
    vt_mutex_lock(&pool->lock);
    for (;;) {
        while (pool->generation == seen && !pool->shutdown) {
            vt_cond_wait(&pool->work, &pool->lock);
        }
        if (pool->shutdown) break;
        seen = pool->generation;
        for (;;) {
            int index;
            if (pool->next_job >= pool->job_count) break;
            index = pool->next_job++;
            vt_mutex_unlock(&pool->lock);
            vt_mesh_one(snap, &pool->jobs[index], &pool->outs[index]);
            vt_mutex_lock(&pool->lock);
        }
        pool->pending -= 1;
        if (pool->pending == 0) vt_cond_signal(&pool->done);
    }
    vt_mutex_unlock(&pool->lock);
    vt_snap_free(snap);
#ifdef _WIN32
    return 0;
#else
    return 0;
#endif
}

static void vt_pool_init(void) {
    int cores;
    int i;
    if (vt_pool_ready) return;
    vt_pool_ready = 1;
    memset(&vt_pool, 0, sizeof(vt_pool));
    cores = vt_core_count();
    if (cores < 1) cores = 1;
    if (cores > 32) cores = 32;
    vt_mutex_init(&vt_pool.lock);
    vt_cond_init(&vt_pool.work);
    vt_cond_init(&vt_pool.done);
    vt_pool.threads = (vt_thread*)calloc((size_t)cores, sizeof(vt_thread));
    if (vt_pool.threads == 0) {
        vt_pool.thread_count = 0;
        return;
    }
    for (i = 0; i < cores; i++) {
        if (!vt_thread_start(&vt_pool.threads[i], vt_worker_entry, &vt_pool)) {
            break;
        }
        vt_pool.thread_count += 1;
    }
    vt_pool.started = 1;
}

static void vt_pool_run(VTJob* jobs, VTOut* outs, int count) {
    int i;
    if (count <= 0) return;
    vt_pool_init();
    if (vt_pool.thread_count <= 0) {
        VTSnap* snap = vt_snap_new();
        if (snap != 0) {
            for (i = 0; i < count; i++) {
                vt_mesh_one(snap, &jobs[i], &outs[i]);
            }
            vt_snap_free(snap);
        }
        return;
    }
    vt_mutex_lock(&vt_pool.lock);
    vt_pool.jobs = jobs;
    vt_pool.outs = outs;
    vt_pool.job_count = count;
    vt_pool.next_job = 0;
    vt_pool.pending = vt_pool.thread_count;
    vt_pool.generation += 1;
    vt_cond_broadcast(&vt_pool.work);
    while (vt_pool.pending > 0) {
        vt_cond_wait(&vt_pool.done, &vt_pool.lock);
    }
    vt_pool.jobs = 0;
    vt_pool.outs = 0;
    vt_pool.job_count = 0;
    vt_mutex_unlock(&vt_pool.lock);
}

int vt_mesh_thread_count(void) {
    vt_pool_init();
    return vt_pool.thread_count;
}

/* ---- batches ------------------------------------------------------------- */

typedef struct {
    VTJob* jobs;
    int job_count;
    int job_cap;
    VTOut* outs;
    int ran;
    int world_set;
} VTBatch;

char* vt_mesh_batch_new(void) {
    VTBatch* batch = (VTBatch*)calloc(1, sizeof(VTBatch));
    return (char*)batch;
}

void vt_mesh_batch_free(char* handle) {
    VTBatch* batch = (VTBatch*)handle;
    int i;
    if (batch == 0) return;
    for (i = 0; i < batch->job_count; i++) {
        vt_out_free(&batch->outs[i]);
    }
    free(batch->outs);
    free(batch->jobs);
    free(batch);
}

static int vt_job_matches(VTJob* job, int cx, int cy, int cz) {
    return job->chunk_x == cx && job->chunk_y == cy && job->chunk_z == cz;
}

static VTJob* vt_batch_push(VTBatch* batch, int cx, int cy, int cz) {
    VTJob* job;
    int i;
    for (i = 0; i < batch->job_count; i++) {
        if (vt_job_matches(&batch->jobs[i], cx, cy, cz)) return 0;
    }
    if (batch->job_count >= batch->job_cap) {
        int cap = batch->job_cap > 0 ? batch->job_cap * 2 : 64;
        VTJob* jobs = (VTJob*)realloc(batch->jobs, (size_t)cap * sizeof(VTJob));
        VTOut* outs;
        if (jobs == 0) return 0;
        batch->jobs = jobs;
        outs = (VTOut*)realloc(batch->outs, (size_t)cap * sizeof(VTOut));
        if (outs == 0) return 0;
        batch->outs = outs;
        memset(batch->outs + batch->job_cap, 0,
               (size_t)(cap - batch->job_cap) * sizeof(VTOut));
        batch->job_cap = cap;
    }
    job = &batch->jobs[batch->job_count];
    memset(job, 0, sizeof(*job));
    job->chunk_x = cx;
    job->chunk_y = cy;
    job->chunk_z = cz;
    batch->job_count += 1;
    return job;
}

static void vt_job_link(VTBatch* batch, VTJob* job, void* world,
                        int cx, int sy, int cz) {
    static const int dx[6] = { 1, -1, 0, 0, 0, 0 };
    static const int dy[6] = { 0, 0, 1, -1, 0, 0 };
    static const int dz[6] = { 0, 0, 0, 0, 1, -1 };
    int i;
    job->center = vworld_section(world, cx, cz, sy);
    job->base_x = cx * 16;
    job->base_y = sy * 16;
    job->base_z = cz * 16;
    for (i = 0; i < 6; i++) {
        job->neighbors[i] = vworld_section(world, cx + dx[i], cz + dz[i],
                                           sy + dy[i]);
    }
    batch->world_set = 1;
}

void vt_mesh_batch_add_chunk(char* handle, char* world, int chunk_x,
                             int chunk_z, int min_section,
                             int section_count) {
    VTBatch* batch = (VTBatch*)handle;
    int i;
    if (batch == 0 || world == 0 || section_count < 1) return;
    for (i = 0; i < section_count; i++) {
        int sy = min_section + i;
        VTJob* job = vt_batch_push(batch, chunk_x, sy, chunk_z);
        if (job == 0) continue;
        vt_job_link(batch, job, world, chunk_x, sy, chunk_z);
    }
}

void vt_mesh_batch_add_section(char* handle, char* world, int chunk_x,
                               int section_y, int chunk_z) {
    VTBatch* batch = (VTBatch*)handle;
    VTJob* job;
    if (batch == 0 || world == 0) return;
    job = vt_batch_push(batch, chunk_x, section_y, chunk_z);
    if (job == 0) return;
    vt_job_link(batch, job, world, chunk_x, section_y, chunk_z);
}

void vt_mesh_batch_add_neighborhood(char* handle, char* world, int chunk_x,
                                    int section_y, int chunk_z) {
    static const int dx[6] = { 1, -1, 0, 0, 0, 0 };
    static const int dy[6] = { 0, 0, 1, -1, 0, 0 };
    static const int dz[6] = { 0, 0, 0, 0, 1, -1 };
    int i;
    vt_mesh_batch_add_section(handle, world, chunk_x, section_y, chunk_z);
    for (i = 0; i < 6; i++) {
        vt_mesh_batch_add_section(handle, world, chunk_x + dx[i],
                                  section_y + dy[i], chunk_z + dz[i]);
    }
}

int vt_mesh_batch_run(char* handle) {
    VTBatch* batch = (VTBatch*)handle;
    int i;
    if (batch == 0) return 1;
    if (batch->ran) return 0;
    for (i = 0; i < batch->job_count; i++) {
        vt_out_free(&batch->outs[i]);
    }
    vt_pool_run(batch->jobs, batch->outs, batch->job_count);
    for (i = 0; i < batch->job_count; i++) {
        if (batch->outs[i].failed) return 1;
    }
    batch->ran = 1;
    return 0;
}

int vt_mesh_batch_sections(char* handle) {
    VTBatch* batch = (VTBatch*)handle;
    return batch != 0 ? batch->job_count : 0;
}

int vt_mesh_batch_quad_count(char* handle) {
    VTBatch* batch = (VTBatch*)handle;
    int total = 0;
    int i;
    if (batch == 0) return 0;
    for (i = 0; i < batch->job_count; i++) {
        total += batch->outs[i].quads[0] + batch->outs[i].quads[1];
    }
    return total;
}

int vt_mesh_batch_vertex_count(char* handle, int slot, int translucent) {
    VTBatch* batch = (VTBatch*)handle;
    if (batch == 0 || slot < 0 || slot >= batch->job_count) return 0;
    if (translucent < 0 || translucent > 1) return 0;
    return (int)(batch->outs[slot].verts[translucent].len / VT_STRIDE);
}

int vt_mesh_batch_index_count(char* handle, int slot, int translucent) {
    VTBatch* batch = (VTBatch*)handle;
    if (batch == 0 || slot < 0 || slot >= batch->job_count) return 0;
    if (translucent < 0 || translucent > 1) return 0;
    return (int)batch->outs[slot].indices[translucent].len;
}

int64_t vt_mesh_batch_vertex_component(char* handle, int slot,
                                       int translucent, int vertex,
                                       int component) {
    VTBatch* batch = (VTBatch*)handle;
    size_t at;
    if (batch == 0 || slot < 0 || slot >= batch->job_count) return 0;
    if (translucent < 0 || translucent > 1) return 0;
    if (vertex < 0 || component < 0 || component >= VT_STRIDE) return 0;
    at = (size_t)vertex * VT_STRIDE + (size_t)component;
    if (at >= batch->outs[slot].verts[translucent].len) return 0;
    return batch->outs[slot].verts[translucent].data[at];
}

int64_t vt_mesh_batch_index_at(char* handle, int slot, int translucent,
                               int index) {
    VTBatch* batch = (VTBatch*)handle;
    if (batch == 0 || slot < 0 || slot >= batch->job_count) return 0;
    if (translucent < 0 || translucent > 1) return 0;
    if (index < 0 || (size_t)index >= batch->outs[slot].indices[translucent].len)
        return 0;
    return batch->outs[slot].indices[translucent].data[index];
}

static uint64_t vt_hash_values(const int64_t* data, size_t len) {
    uint64_t h = 1469598103934665603ULL;
    size_t i;
    for (i = 0; i < len; i++) {
        h ^= (uint64_t)data[i];
        h *= 1099511628211ULL;
    }
    return h;
}

int64_t vt_mesh_batch_checksum(char* handle, int slot, int translucent) {
    VTBatch* batch = (VTBatch*)handle;
    uint64_t h;
    if (batch == 0 || slot < 0 || slot >= batch->job_count) return 0;
    if (translucent < 0 || translucent > 1) return 0;
    h = vt_hash_values(batch->outs[slot].verts[translucent].data,
                       batch->outs[slot].verts[translucent].len);
    h ^= vt_hash_values(batch->outs[slot].indices[translucent].data,
                        batch->outs[slot].indices[translucent].len);
    return (int64_t)h;
}
