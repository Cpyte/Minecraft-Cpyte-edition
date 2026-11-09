/* Vortex engine - parallel per-face voxel mesher.
 *
 * The Cpyte mesher in world/mesher.cpy is the readable greedy reference and the
 * small-world API. This file is the production path: sections are meshed by a
 * persistent worker pool, per-section snapshots remove the paletted-container
 * and light decoding from the inner loop, and each worker writes into its own
 * growable vertex/index buffers so no locks are taken while meshing.
 *
 * Workers never allocate through the Cpyte GC. They only read decoded section
 * data through the accessor functions below and write malloc'd buffers; the
 * caller copies or uploads the result on the main thread. That keeps a
 * collection on the main thread from mistaking a worker's stack for a root
 * set, and keeps the GC out of the mesh critical path.
 *
 * Ambient occlusion and smooth light need the cells around each face corner,
 * so a job snapshots an 18^3 halo: the centre section plus a one-cell border
 * on every side, backed by the 3x3x3 grid of face-, edge- and corner-adjacent
 * sections. The halo is decoded once per job instead of a world lookup per
 * face. Each face is emitted as its own quad with a normal, per-corner AO,
 * averaged light, a biome tint and directional shading, matching the
 * behaviour of a modern client mesher; sub-block shapes (slabs, stairs,
 * fences, panes, fluids) use the state-aware geometry codes from blockdb.c.
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

/* ---- Cpyte-side accessors (compiled in their own module) ------------------
 *
 * sec_block_at_index, sec_light_packed_index, sec_biome_at_index and
 * vworld_section are Cpyte public defs.
 * Their extern declarations are block-scope (in vt_snapshot / vt_job_link) on
 * purpose: importing this file registers every file-scope declaration, and the
 * importer is emitted before any Cpyte body, so a file-scope extern here would
 * override the real VSection and VWorld pointer signatures with void pointer
 * ones. Block-scope externs are invisible to that top-level scan yet still link
 * against the Cpyte symbols. vt_blockdb_render is genuine C (blockdb.c), so it
 * stays file-scope. */

extern uint32_t vt_blockdb_render(int state);
extern uint32_t vt_blockdb_shape_tint(int state);
extern uint32_t vt_biome_color(int biome, int tint_kind);

/* ---- block flags, matching tools/gen_blockdb.py --------------------------- */

#define VT_AIR        1
#define VT_FLUID      2
#define VT_CUBE       4
#define VT_OPAQUE     8
#define VT_TRANSLUCENT 16
#define VT_LEAVES     32
#define VT_CROSS      64

/* Vertex layout (VT_STRIDE int64 components). Positions and normals are fixed
 * point x256 so sub-block shapes (slabs, carpets, fence posts) keep exact
 * fractions without floats in the worker. UVs are tile-local x256 (256 = one
 * tile), so the renderer maps them into an atlas page with `layer`. Light is
 * the smooth four-corner average x16 (0..240). `tint` is a packed 0xRRGGBB
 * biome colour, `shade` the directional face brightness x256, `ao` the corner
 * occlusion 0..3, and `flip` the triangulation diagonal chosen to keep AO
 * symmetric. This is the Horizon-style per-face vertex; the greedy Cpyte
 * reference mesher in world/mesher.cpy keeps its own simpler nine-component
 * format. */
#define VT_STRIDE 16
#define VT_POS_SCALE 256
#define VT_UNKNOWN_LAYER 65535u
#define VT_FULL_SKY (15 * 16)

#define VT_HALO 18
#define VT_HALO_CELLS (VT_HALO * VT_HALO * VT_HALO)
#define VT_SECTION_CELLS 4096

/* Geometry codes, matching engine/blockdb.c. */
#define VT_SHAPE_CUBE 0
#define VT_SHAPE_SLAB_LOW 2
#define VT_SHAPE_SLAB_HIGH 3
#define VT_SHAPE_SLAB_DOUBLE 4
#define VT_SHAPE_STAIRS 5
#define VT_SHAPE_FENCE 6
#define VT_SHAPE_WALL 7
#define VT_SHAPE_PANE 8
#define VT_SHAPE_CARPET 9
#define VT_SHAPE_DOOR 10
#define VT_SHAPE_TRAPDOOR 11
#define VT_SHAPE_FLUID 12
#define VT_SHAPE_PLATE 13
#define VT_SHAPE_BUTTON 14
#define VT_SHAPE_SKIP 255

#define VT_FACE_CROSS 6

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
    void* grid[27];
    int base_x;
    int base_y;
    int base_z;
    int chunk_x;
    int chunk_y;
    int chunk_z;
} VTJob;

/* Index into the 3x3x3 section grid: offsets in {-1,0,1} per axis. */
static int vt_grid_index(int ox, int oy, int oz) {
    return (ox + 1) + (oz + 1) * 3 + (oy + 1) * 9;
}

/* Halo cell index, local coordinate in 0..17: x + z*18 + y*324. The halo is the
 * centre section plus a one-cell border on every side, so per-face ambient
 * occlusion and smooth light can sample the eight cells around a face corner
 * without a world lookup. */
static int vt_halo_index(int hx, int hy, int hz) {
    return hx + hz * VT_HALO + hy * VT_HALO * VT_HALO;
}

typedef struct {
    uint32_t state[VT_HALO_CELLS];
    uint32_t render[VT_HALO_CELLS];
    uint8_t light[VT_HALO_CELLS];
    uint8_t shape[VT_SECTION_CELLS];
    uint8_t tint[VT_SECTION_CELLS];
    uint32_t biome[VT_SECTION_CELLS];
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

static void vt_snapshot(VTSnap* snap, VTJob* job) {
    extern int sec_block_at_index(void* section, int index);
    extern int sec_light_packed_index(void* section, int index);
    extern int sec_biome_at_index(void* section, int index);
    int hx, hy, hz;
    int i;
    if (job->center == 0) return;
    for (hy = 0; hy < VT_HALO; hy++) {
        int sy = hy - 1;
        int oy = sy < 0 ? -1 : (sy > 15 ? 1 : 0);
        int ly = sy < 0 ? 15 : (sy > 15 ? 0 : sy);
        for (hz = 0; hz < VT_HALO; hz++) {
            int sz = hz - 1;
            int oz = sz < 0 ? -1 : (sz > 15 ? 1 : 0);
            int lz = sz < 0 ? 15 : (sz > 15 ? 0 : sz);
            for (hx = 0; hx < VT_HALO; hx++) {
                int sx = hx - 1;
                int ox = sx < 0 ? -1 : (sx > 15 ? 1 : 0);
                int lx = sx < 0 ? 15 : (sx > 15 ? 0 : sx);
                int hi = vt_halo_index(hx, hy, hz);
                void* section = job->grid[vt_grid_index(ox, oy, oz)];
                uint32_t state = 0;
                int light = VT_FULL_SKY;
                if (section != 0) {
                    int ci = lx + (lz << 4) + (ly << 8);
                    state = (uint32_t)sec_block_at_index(section, ci);
                    light = sec_light_packed_index(section, ci);
                }
                snap->state[hi] = state;
                snap->render[hi] = vt_blockdb_render((int)state);
                snap->light[hi] = (uint8_t)light;
            }
        }
    }
    for (i = 0; i < VT_SECTION_CELLS; i++) {
        int x = i & 15;
        int z = (i >> 4) & 15;
        int y = (i >> 8) & 15;
        int hi = vt_halo_index(x + 1, y + 1, z + 1);
        uint32_t st = vt_blockdb_shape_tint((int)snap->state[hi]);
        int bi = (x >> 2) + ((z >> 2) << 2) + ((y >> 2) << 4);
        snap->shape[i] = (uint8_t)(st & 0xFFu);
        snap->tint[i] = (uint8_t)((st >> 8) & 0xFFu);
        snap->biome[i] = (uint32_t)sec_biome_at_index(job->center, bi);
    }
}

/* ---- geometry tables and helpers ----------------------------------------- */

static const int VT_NX[6] = { 1, -1, 0, 0, 0, 0 };
static const int VT_NY[6] = { 0, 0, 1, -1, 0, 0 };
static const int VT_NZ[6] = { 0, 0, 0, 0, 1, -1 };
/* Directional brightness x256: +/-X 0.6, +Y 1.0, -Y 0.5, +/-Z 0.8. */
static const int VT_SHADE[6] = { 153, 153, 256, 128, 204, 204 };
/* The two tangent axes of each face, used for ambient-occlusion sampling. */
static const int VT_T1[6] = { 1, 1, 0, 0, 0, 0 };
static const int VT_T2[6] = { 2, 2, 2, 2, 1, 1 };

/* Only opaque full cubes cast ambient occlusion onto their neighbours. */
static int vt_occludes(uint32_t render) {
    return (render & VT_OPAQUE) != 0 ? 1 : 0;
}

/* Axis-aligned edge length between two fixed-point corners. */
static int64_t vt_edge_len(const int64_t* a, const int64_t* b) {
    int64_t d0 = a[0] - b[0];
    int64_t d1 = a[1] - b[1];
    int64_t d2 = a[2] - b[2];
    if (d0 < 0) d0 = -d0;
    if (d1 < 0) d1 = -d1;
    if (d2 < 0) d2 = -d2;
    return d0 + d1 + d2;
}

/* A solid cube neighbour that a fence, wall or pane connects toward. */
static int vt_solid_neighbor(VTSnap* snap, int hx, int hy, int hz) {
    uint32_t r = snap->render[vt_halo_index(hx, hy, hz)];
    return ((r & VT_CUBE) != 0 && (r & VT_AIR) == 0) ? 1 : 0;
}

/* ---- per-face emission with ambient occlusion and smooth light ------------
 *
 * Each face corner is sampled against the air cell plus its two edge
 * neighbours and the corner between them. ao is 3 when nothing occludes and
 * falls to 0 in a fully enclosed concave corner; smooth light averages the
 * packed sky and block levels of those same four cells, stored x16 (0..240).
 * The triangulation diagonal is picked so the shared edge runs between the two
 * higher-occlusion corners, removing the usual AO anisotropy seam. */
static void vt_emit_face(VTOut* out, VTSnap* snap, int translucent, int dir,
                         int bx, int by, int bz, VTJob* job,
                         const int64_t* c, uint32_t layer, uint32_t tintcolor,
                         uint32_t face) {
    VTBuf* verts = &out->verts[translucent];
    VTBuf* indices = &out->indices[translucent];
    int64_t* v;
    int64_t* ix;
    int64_t base;
    int ax = bx + VT_NX[dir];
    int ay = by + VT_NY[dir];
    int az = bz + VT_NZ[dir];
    int basev[3];
    int airv[3];
    int ha[3];
    int t1 = VT_T1[dir];
    int t2 = VT_T2[dir];
    int64_t low1;
    int64_t low2;
    int64_t uw;
    int64_t vh;
    int ao[4];
    uint32_t sky[4];
    uint32_t blk[4];
    int k;
    int flip;
    if (out->failed) return;
    if (!vtbuf_reserve(verts, VT_STRIDE * 4) || !vtbuf_reserve(indices, 6)) {
        out->failed = 1;
        return;
    }
    basev[0] = job->base_x; basev[1] = job->base_y; basev[2] = job->base_z;
    airv[0] = ax; airv[1] = ay; airv[2] = az;
    ha[0] = ax + 1; ha[1] = ay + 1; ha[2] = az + 1;
    low1 = (int64_t)(basev[t1] + airv[t1]) * VT_POS_SCALE;
    low2 = (int64_t)(basev[t2] + airv[t2]) * VT_POS_SCALE;
    uw = vt_edge_len(c, c + 3);
    vh = vt_edge_len(c + 3, c + 6);
    for (k = 0; k < 4; k++) {
        int o1 = c[k * 3 + t1] <= low1 ? -1 : 1;
        int o2 = c[k * 3 + t2] <= low2 ? -1 : 1;
        int s1[3];
        int s2[3];
        int cc[3];
        int hiA, hi1, hi2, hiC;
        int side1, side2, corner;
        uint32_t la, l1, l2, lc;
        s1[0] = ha[0]; s1[1] = ha[1]; s1[2] = ha[2];
        s2[0] = ha[0]; s2[1] = ha[1]; s2[2] = ha[2];
        cc[0] = ha[0]; cc[1] = ha[1]; cc[2] = ha[2];
        s1[t1] += o1;
        s2[t2] += o2;
        cc[t1] += o1;
        cc[t2] += o2;
        hiA = vt_halo_index(ha[0], ha[1], ha[2]);
        hi1 = vt_halo_index(s1[0], s1[1], s1[2]);
        hi2 = vt_halo_index(s2[0], s2[1], s2[2]);
        hiC = vt_halo_index(cc[0], cc[1], cc[2]);
        side1 = vt_occludes(snap->render[hi1]);
        side2 = vt_occludes(snap->render[hi2]);
        corner = vt_occludes(snap->render[hiC]);
        ao[k] = (side1 && side2) ? 0 : 3 - (side1 + side2 + corner);
        la = snap->light[hiA];
        l1 = snap->light[hi1];
        l2 = snap->light[hi2];
        lc = snap->light[hiC];
        sky[k] = ((la >> 4) + (l1 >> 4) + (l2 >> 4) + (lc >> 4)) * 4u;
        blk[k] = ((la & 15u) + (l1 & 15u) + (l2 & 15u) + (lc & 15u)) * 4u;
    }
    flip = (ao[0] + ao[2] > ao[1] + ao[3]) ? 1 : 0;
    base = (int64_t)(verts->len / VT_STRIDE);
    v = verts->data + verts->len;
    for (k = 0; k < 4; k++) {
        int64_t* p = v + k * VT_STRIDE;
        int64_t u = (k == 1 || k == 2) ? uw : 0;
        int64_t vv = (k == 2 || k == 3) ? vh : 0;
        p[0] = c[k * 3 + 0]; p[1] = c[k * 3 + 1]; p[2] = c[k * 3 + 2];
        p[3] = u; p[4] = vv; p[5] = (int64_t)layer;
        p[6] = (int64_t)VT_NX[dir] * VT_POS_SCALE;
        p[7] = (int64_t)VT_NY[dir] * VT_POS_SCALE;
        p[8] = (int64_t)VT_NZ[dir] * VT_POS_SCALE;
        p[9] = (int64_t)ao[k];
        p[10] = (int64_t)sky[k];
        p[11] = (int64_t)blk[k];
        p[12] = (int64_t)tintcolor;
        p[13] = (int64_t)VT_SHADE[dir];
        p[14] = (int64_t)face;
        p[15] = (int64_t)flip;
    }
    verts->len += VT_STRIDE * 4;
    ix = indices->data + indices->len;
    if (flip) {
        ix[0] = base + 1; ix[1] = base + 2; ix[2] = base + 3;
        ix[3] = base + 1; ix[4] = base + 3; ix[5] = base;
    } else {
        ix[0] = base; ix[1] = base + 1; ix[2] = base + 2;
        ix[3] = base; ix[4] = base + 2; ix[5] = base + 3;
    }
    indices->len += 6;
    out->quads[translucent] += 1;
}

/* Emit the six faces of a sub-block box (offsets in tile units, 0..256) with
 * neighbour culling. skip_top_cull keeps a fluid surface exposed under the
 * lowered top. */
static void vt_emit_box(VTOut* out, VTSnap* snap, int translucent,
                        int bx, int by, int bz,
                        int ox0, int oy0, int oz0,
                        int ox1, int oy1, int oz1,
                        VTJob* job, uint32_t layer, uint32_t tintcolor,
                        uint32_t near_render, int skip_top_cull) {
    int64_t X0 = (int64_t)(job->base_x + bx) * VT_POS_SCALE + ox0;
    int64_t X1 = (int64_t)(job->base_x + bx) * VT_POS_SCALE + ox1;
    int64_t Y0 = (int64_t)(job->base_y + by) * VT_POS_SCALE + oy0;
    int64_t Y1 = (int64_t)(job->base_y + by) * VT_POS_SCALE + oy1;
    int64_t Z0 = (int64_t)(job->base_z + bz) * VT_POS_SCALE + oz0;
    int64_t Z1 = (int64_t)(job->base_z + bz) * VT_POS_SCALE + oz1;
    int64_t c[12];
    int dir;
    for (dir = 0; dir < 6; dir++) {
        int ax = bx + VT_NX[dir];
        int ay = by + VT_NY[dir];
        int az = bz + VT_NZ[dir];
        uint32_t far = snap->render[vt_halo_index(ax + 1, ay + 1, az + 1)];
        if (!(skip_top_cull && dir == 2) && vt_face_hides(near_render, far)) {
            continue;
        }
        switch (dir) {
        case 0:
            c[0] = X1; c[1] = Y0; c[2] = Z0;  c[3] = X1; c[4] = Y1; c[5] = Z0;
            c[6] = X1; c[7] = Y1; c[8] = Z1;  c[9] = X1; c[10] = Y0; c[11] = Z1;
            break;
        case 1:
            c[0] = X0; c[1] = Y0; c[2] = Z1;  c[3] = X0; c[4] = Y1; c[5] = Z1;
            c[6] = X0; c[7] = Y1; c[8] = Z0;  c[9] = X0; c[10] = Y0; c[11] = Z0;
            break;
        case 2:
            c[0] = X0; c[1] = Y1; c[2] = Z0;  c[3] = X0; c[4] = Y1; c[5] = Z1;
            c[6] = X1; c[7] = Y1; c[8] = Z1;  c[9] = X1; c[10] = Y1; c[11] = Z0;
            break;
        case 3:
            c[0] = X0; c[1] = Y0; c[2] = Z0;  c[3] = X1; c[4] = Y0; c[5] = Z0;
            c[6] = X1; c[7] = Y0; c[8] = Z1;  c[9] = X0; c[10] = Y0; c[11] = Z1;
            break;
        case 4:
            c[0] = X0; c[1] = Y0; c[2] = Z1;  c[3] = X1; c[4] = Y0; c[5] = Z1;
            c[6] = X1; c[7] = Y1; c[8] = Z1;  c[9] = X0; c[10] = Y1; c[11] = Z1;
            break;
        default:
            c[0] = X1; c[1] = Y0; c[2] = Z0;  c[3] = X0; c[4] = Y0; c[5] = Z0;
            c[6] = X0; c[7] = Y1; c[8] = Z0;  c[9] = X1; c[10] = Y1; c[11] = Z0;
            break;
        }
        vt_emit_face(out, snap, translucent, dir, bx, by, bz, job, c, layer,
                     tintcolor, (uint32_t)dir);
    }
}

/* A plant quad: up-facing normal, no occlusion, full-tile UV, face tag 6. */
static void vt_emit_plant(VTOut* out, const int64_t* c, uint32_t layer,
                          uint32_t sky, uint32_t block, uint32_t tintcolor) {
    VTBuf* verts = &out->verts[0];
    VTBuf* indices = &out->indices[0];
    int64_t* v;
    int64_t* ix;
    int64_t base;
    int k;
    if (out->failed) return;
    if (!vtbuf_reserve(verts, VT_STRIDE * 4) || !vtbuf_reserve(indices, 6)) {
        out->failed = 1;
        return;
    }
    base = (int64_t)(verts->len / VT_STRIDE);
    v = verts->data + verts->len;
    for (k = 0; k < 4; k++) {
        int64_t* p = v + k * VT_STRIDE;
        p[0] = c[k * 3 + 0]; p[1] = c[k * 3 + 1]; p[2] = c[k * 3 + 2];
        p[3] = (k == 1 || k == 2) ? VT_POS_SCALE : 0;
        p[4] = (k == 2 || k == 3) ? VT_POS_SCALE : 0;
        p[5] = (int64_t)layer;
        p[6] = 0; p[7] = VT_POS_SCALE; p[8] = 0;
        p[9] = 3;
        p[10] = (int64_t)sky;
        p[11] = (int64_t)block;
        p[12] = (int64_t)tintcolor;
        p[13] = VT_POS_SCALE;
        p[14] = VT_FACE_CROSS;
        p[15] = 0;
    }
    verts->len += VT_STRIDE * 4;
    ix = indices->data + indices->len;
    ix[0] = base; ix[1] = base + 1; ix[2] = base + 2;
    ix[3] = base; ix[4] = base + 2; ix[5] = base + 3;
    indices->len += 6;
    out->quads[0] += 1;
}

/* Cross geometry: two diagonal planes, each emitted twice so the plant reads
 * from every direction. Light is the cell's own level, unsmoothed. */
static void vt_emit_cross(VTSnap* snap, int bx, int by, int bz, VTJob* job,
                          uint32_t layer, uint32_t tintcolor, VTOut* out) {
    int64_t x0 = (int64_t)(job->base_x + bx) * VT_POS_SCALE;
    int64_t y0 = (int64_t)(job->base_y + by) * VT_POS_SCALE;
    int64_t z0 = (int64_t)(job->base_z + bz) * VT_POS_SCALE;
    int64_t x1 = x0 + VT_POS_SCALE;
    int64_t y1 = y0 + VT_POS_SCALE;
    int64_t z1 = z0 + VT_POS_SCALE;
    uint32_t light = snap->light[vt_halo_index(bx + 1, by + 1, bz + 1)];
    uint32_t sky = (light >> 4) * 16u;
    uint32_t block = (light & 15u) * 16u;
    int64_t c[12];
    c[0] = x0; c[1] = y0; c[2] = z0; c[3] = x1; c[4] = y0; c[5] = z1;
    c[6] = x1; c[7] = y1; c[8] = z1; c[9] = x0; c[10] = y1; c[11] = z0;
    vt_emit_plant(out, c, layer, sky, block, tintcolor);
    c[0] = x0; c[1] = y1; c[2] = z0; c[3] = x1; c[4] = y1; c[5] = z1;
    c[6] = x1; c[7] = y0; c[8] = z1; c[9] = x0; c[10] = y0; c[11] = z0;
    vt_emit_plant(out, c, layer, sky, block, tintcolor);
    c[0] = x1; c[1] = y0; c[2] = z0; c[3] = x0; c[4] = y0; c[5] = z1;
    c[6] = x0; c[7] = y1; c[8] = z1; c[9] = x1; c[10] = y1; c[11] = z0;
    vt_emit_plant(out, c, layer, sky, block, tintcolor);
    c[0] = x1; c[1] = y1; c[2] = z0; c[3] = x0; c[4] = y1; c[5] = z1;
    c[6] = x0; c[7] = y0; c[8] = z1; c[9] = x1; c[10] = y0; c[11] = z0;
    vt_emit_plant(out, c, layer, sky, block, tintcolor);
}

/* Post plus connecting arms toward solid neighbours (fence, wall, pane). */
static void vt_emit_connector(VTSnap* snap, int translucent,
                              int bx, int by, int bz, VTJob* job,
                              uint32_t layer, uint32_t tintcolor,
                              uint32_t near_render, int post0, int post1,
                              int arm_lo, int arm_hi, int arm_t0, int arm_t1,
                              VTOut* out) {
    int hx = bx + 1;
    int hy = by + 1;
    int hz = bz + 1;
    vt_emit_box(out, snap, translucent, bx, by, bz, post0, 0, post0,
                post1, 256, post1, job, layer, tintcolor, near_render, 0);
    if (vt_solid_neighbor(snap, hx + 1, hy, hz))
        vt_emit_box(out, snap, translucent, bx, by, bz, post1, arm_lo, arm_t0,
                    256, arm_hi, arm_t1, job, layer, tintcolor, near_render, 0);
    if (vt_solid_neighbor(snap, hx - 1, hy, hz))
        vt_emit_box(out, snap, translucent, bx, by, bz, 0, arm_lo, arm_t0,
                    post0, arm_hi, arm_t1, job, layer, tintcolor, near_render, 0);
    if (vt_solid_neighbor(snap, hx, hy, hz + 1))
        vt_emit_box(out, snap, translucent, bx, by, bz, arm_t0, arm_lo, post1,
                    arm_t1, arm_hi, 256, job, layer, tintcolor, near_render, 0);
    if (vt_solid_neighbor(snap, hx, hy, hz - 1))
        vt_emit_box(out, snap, translucent, bx, by, bz, arm_t0, arm_lo, 0,
                    arm_t1, arm_hi, post0, job, layer, tintcolor, near_render, 0);
}

/* ---- one section --------------------------------------------------------- */

static void vt_mesh_one(VTSnap* snap, VTJob* job, VTOut* out) {
    int i;
    out->sections = 0;
    out->quads[0] = 0;
    out->quads[1] = 0;
    if (job->center == 0) return;
    vt_snapshot(snap, job);
    out->sections = 1;

    for (i = 0; i < VT_SECTION_CELLS; i++) {
        int x = i & 15;
        int z = (i >> 4) & 15;
        int y = (i >> 8) & 15;
        int hi = vt_halo_index(x + 1, y + 1, z + 1);
        uint32_t state = snap->state[hi];
        uint32_t render = snap->render[hi];
        uint32_t flags = render & 0xFFu;
        uint32_t layer_code = render >> 8;
        uint32_t layer;
        uint32_t tintcolor;
        int translucent;
        int shape;
        if (state == 0 || (flags & VT_AIR) != 0) continue;
        layer = layer_code == 0 ? VT_UNKNOWN_LAYER : layer_code - 1u;
        translucent = (flags & VT_TRANSLUCENT) != 0 ? 1 : 0;
        tintcolor = snap->tint[i] != 0
            ? vt_biome_color((int)snap->biome[i], (int)snap->tint[i])
            : 0xFFFFFFu;
        shape = snap->shape[i];
        if ((flags & VT_CROSS) != 0) {
            vt_emit_cross(snap, x, y, z, job, layer, tintcolor, out);
            continue;
        }
        switch (shape) {
        case VT_SHAPE_CUBE:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 256, 256, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_FLUID:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 224, 256, job, layer, tintcolor, render, 1);
            break;
        case VT_SHAPE_SLAB_LOW:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 128, 256, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_SLAB_HIGH:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 128, 0,
                        256, 256, 256, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_SLAB_DOUBLE:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 256, 256, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_CARPET:
        case VT_SHAPE_PLATE:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 16, 256, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_STAIRS:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 128, 256, job, layer, tintcolor, render, 0);
            vt_emit_box(out, snap, translucent, x, y, z, 0, 128, 128,
                        256, 256, 256, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_FENCE:
            vt_emit_connector(snap, translucent, x, y, z, job, layer, tintcolor,
                              render, 96, 160, 64, 192, 112, 144, out);
            break;
        case VT_SHAPE_WALL:
            vt_emit_connector(snap, translucent, x, y, z, job, layer, tintcolor,
                              render, 96, 160, 0, 224, 112, 144, out);
            break;
        case VT_SHAPE_PANE:
            vt_emit_connector(snap, translucent, x, y, z, job, layer, tintcolor,
                              render, 112, 144, 0, 256, 120, 136, out);
            break;
        case VT_SHAPE_DOOR:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 256, 48, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_TRAPDOOR:
            vt_emit_box(out, snap, translucent, x, y, z, 0, 0, 0,
                        256, 48, 256, job, layer, tintcolor, render, 0);
            break;
        case VT_SHAPE_BUTTON:
            vt_emit_box(out, snap, translucent, x, y, z, 96, 0, 96,
                        160, 32, 160, job, layer, tintcolor, render, 0);
            break;
        default:
            break;
        }
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

int vt_mesh_vertex_stride(void) {
    return VT_STRIDE;
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
    extern void* vworld_section(void* world, int chunk_x, int chunk_z, int section_y);
    int ox, oy, oz;
    for (oy = -1; oy <= 1; oy++) {
        for (oz = -1; oz <= 1; oz++) {
            for (ox = -1; ox <= 1; ox++) {
                job->grid[vt_grid_index(ox, oy, oz)] = vworld_section(
                    world, cx + ox, cz + oz, sy + oy);
            }
        }
    }
    job->center = job->grid[13];
    job->base_x = cx * 16;
    job->base_y = sy * 16;
    job->base_z = cz * 16;
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

/* ---- renderer handoff ---------------------------------------------------- */

/* A finished batch is published here instead of being pushed straight into the
 * renderer, so the engine and the protocol layer never have to link against it.
 * The renderer drains the ring; a headless run has no drainer, so a full ring
 * recycles its oldest batch rather than growing without bound. */
#define VT_MESH_HANDOFF_SLOTS 8

static char* vt_mesh_handoff[VT_MESH_HANDOFF_SLOTS];
static int vt_mesh_handoff_head = 0;
static int vt_mesh_handoff_count = 0;

void vt_mesh_batch_publish(char* handle) {
    int tail;
    if (handle == 0) return;
    if (vt_mesh_handoff_count == VT_MESH_HANDOFF_SLOTS) {
        vt_mesh_batch_free(vt_mesh_handoff[vt_mesh_handoff_head]);
        vt_mesh_handoff[vt_mesh_handoff_head] = 0;
        vt_mesh_handoff_head = (vt_mesh_handoff_head + 1) % VT_MESH_HANDOFF_SLOTS;
        vt_mesh_handoff_count--;
    }
    tail = (vt_mesh_handoff_head + vt_mesh_handoff_count) % VT_MESH_HANDOFF_SLOTS;
    vt_mesh_handoff[tail] = handle;
    vt_mesh_handoff_count++;
}

char* vt_mesh_batch_take(void) {
    char* handle;
    if (vt_mesh_handoff_count == 0) return 0;
    handle = vt_mesh_handoff[vt_mesh_handoff_head];
    vt_mesh_handoff[vt_mesh_handoff_head] = 0;
    vt_mesh_handoff_head = (vt_mesh_handoff_head + 1) % VT_MESH_HANDOFF_SLOTS;
    vt_mesh_handoff_count--;
    return handle;
}

int vt_mesh_batch_pending(void) {
    return vt_mesh_handoff_count;
}
