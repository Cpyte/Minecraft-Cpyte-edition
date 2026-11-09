#define SDL_MAIN_HANDLED
#include "vk_renderer.h"
#include "accounts.h"
#include "resource_pack.h"
#include "shaders_spv.h"
#include "gui.h"
#include "menus.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <SDL2/SDL.h>
#include <SDL2/SDL_vulkan.h>
#include <vulkan/vulkan.h>

/* Two pieces of the engine, implemented in src/engine/native.c and
 * src/engine/mesher.c. The renderer reaches for them directly so that a Play
 * session can drive a frame without the protocol bundle ever linking Vulkan:
 * the loop publishes its view and publishes finished meshes, the pump below
 * reads both. */
extern void vt_set_view_pump(long long handle);
extern double vt_view_double(int index);
extern void vt_close_view(void);
extern char* vt_mesh_batch_take(void);
extern void vt_mesh_batch_free(char* handle);
extern int vt_chat_slot_count(void);
extern const char* vt_chat_line_at(int row);
extern long long vt_chat_line_serial(int row);
extern int64_t mc_stdin_inject_line(const char *text);

#define MAX_FRAMES_IN_FLIGHT 2
/* One entry per chunk section and pass. A live server replaces the same
 * section over and over, so the store is keyed instead of append-only and the
 * budget below is what a real view distance actually needs. */
#define MAX_SECTIONS 4096
/* Sky quads, the HUD and the chat lines all share the GUI pipeline, so the
 * budget has to hold a frame of 8x8-font text rather than just a crosshair. */
#define MAX_GUI_VERTS 65536
#define MAX_WORLD_VERTS 900000
#define MAX_WORLD_INDICES 1400000

/* ---- Math Helpers -------------------------------------------------------- */

#define PI 3.14159265358979323846f
#define DEG2RAD(d) ((d) * (PI / 180.0f))

static void mat4_identity(float* m) {
    memset(m, 0, 16 * sizeof(float));
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

static void mat4_multiply(const float* a, const float* b, float* out) {
    float res[16];
    for (int i = 0; i < 4; i++) {
        for (int j = 0; j < 4; j++) {
            res[i * 4 + j] = a[i * 4 + 0] * b[0 * 4 + j] +
                             a[i * 4 + 1] * b[1 * 4 + j] +
                             a[i * 4 + 2] * b[2 * 4 + j] +
                             a[i * 4 + 3] * b[3 * 4 + j];
        }
    }
    memcpy(out, res, 16 * sizeof(float));
}

static void mat4_perspective(float fovy_rad, float aspect, float znear, float zfar, float* out) {
    memset(out, 0, 16 * sizeof(float));
    float tanHalfFov = tanf(fovy_rad / 2.0f);
    out[0] = 1.0f / (aspect * tanHalfFov);
    out[5] = -1.0f / tanHalfFov; // Vulkan Y-flip
    out[10] = zfar / (znear - zfar);
    out[11] = -1.0f;
    out[14] = -(zfar * znear) / (zfar - znear);
}

static void mat4_lookat(float eyex, float eyey, float eyez,
                        float atx, float aty, float atz,
                        float upx, float upy, float upz, float* out) {
    float fx = atx - eyex;
    float fy = aty - eyey;
    float fz = atz - eyez;
    float flen = sqrtf(fx*fx + fy*fy + fz*fz);
    if (flen > 0.00001f) { fx /= flen; fy /= flen; fz /= flen; }

    float rx = fy * upz - fz * upy;
    float ry = fz * upx - fx * upz;
    float rz = fx * upy - fy * upx;
    float rlen = sqrtf(rx*rx + ry*ry + rz*rz);
    if (rlen > 0.00001f) { rx /= rlen; ry /= rlen; rz /= rlen; }

    float ux = ry * fz - rz * fy;
    float uy = rz * fx - rx * fz;
    float uz = rx * fy - ry * fx;

    memset(out, 0, 16 * sizeof(float));
    out[0] = rx;  out[1] = ux;  out[2] = -fx;  out[3] = 0.0f;
    out[4] = ry;  out[5] = uy;  out[6] = -fy;  out[7] = 0.0f;
    out[8] = rz;  out[9] = uz;  out[10] = -fz; out[11] = 0.0f;
    out[12] = -(rx * eyex + ry * eyey + rz * eyez);
    out[13] = -(ux * eyex + uy * eyey + uz * eyez);
    out[14] = -(-fx * eyex + -fy * eyey + -fz * eyez);
    out[15] = 1.0f;
}

/* ---- Frustum ------------------------------------------------------------
 *
 * The six planes of view * proj, in the column-major layout mat4_multiply
 * produces. Horizon culls every chunk section against its bounds before
 * recording a draw; the same test here keeps a large store cheap. */
static float s_frustum[6][4];

static void frustum_from_matrix(const float* m) {
    /* Row vectors of a column-major matrix: element (r, c) is m[c * 4 + r]. */
    float rows[4][4];
    int r, c, i;
    for (r = 0; r < 4; r++)
        for (c = 0; c < 4; c++)
            rows[r][c] = m[c * 4 + r];
    for (r = 0; r < 4; r++) {
        for (c = 0; c < 4; c++) {
            s_frustum[r * 2 + 0][c] = rows[3][c] + rows[r][c];
            s_frustum[r * 2 + 1][c] = rows[3][c] - rows[r][c];
        }
    }
    for (i = 0; i < 6; i++) {
        float len = sqrtf(s_frustum[i][0] * s_frustum[i][0] +
                          s_frustum[i][1] * s_frustum[i][1] +
                          s_frustum[i][2] * s_frustum[i][2]);
        if (len > 0.00001f) {
            s_frustum[i][0] /= len;
            s_frustum[i][1] /= len;
            s_frustum[i][2] /= len;
            s_frustum[i][3] /= len;
        }
    }
}

/* The corner of the box nearest the plane's positive side, the usual "p-vertex"
 * test: if that corner is behind the plane, the whole box is. */
static int frustum_sees_box(const float* bmin, const float* bmax) {
    int i;
    for (i = 0; i < 6; i++) {
        float px = s_frustum[i][0] > 0.0f ? bmax[0] : bmin[0];
        float py = s_frustum[i][1] > 0.0f ? bmax[1] : bmin[1];
        float pz = s_frustum[i][2] > 0.0f ? bmax[2] : bmin[2];
        if (s_frustum[i][0] * px + s_frustum[i][1] * py +
            s_frustum[i][2] * pz + s_frustum[i][3] < 0.0f)
            return 0;
    }
    return 1;
}

/* ---- GPU Vertex Formats -------------------------------------------------- */

typedef struct {
    float pos[3];
    float uv[2];
    uint32_t layer;
    float normal[3];
    float ao;
    float light[2];
    float tint[3];
    float shade;
    uint32_t face;
} GpuTerrainVertex;

typedef struct {
    float pos[2];
    float uv[2];
    float color[4];
} GpuGuiVertex;

typedef struct {
    float model[16];
    float view[16];
    float proj[16];
    float cameraPos[4];
    float skyColor[4];
    float fogColor[4];
    float skyBrightness;
    float time;
    float fogStart;
    float fogEnd;
    int32_t tileMap[768];
} TerrainUbo;

/* ---- Chunk Section Mesh -------------------------------------------------- */

typedef struct {
    int active;
    int chunk_x;
    int chunk_z;
    int section_y;
    int translucent;
    int vertex_offset;
    int vertex_count;
    int index_offset;
    int index_count;
    /* World-space bounds, so a section can be culled against the frustum and
     * measured against the render distance without touching its vertices. */
    float bmin[3];
    float bmax[3];
    int visible;
} ChunkSectionMesh;

/* ---- Renderer Global State ----------------------------------------------- */

static SDL_Window* s_window = NULL;
static int s_width = 1152;
static int s_height = 720;
static VkRendererState s_state = VK_STATE_DIALOG;
/* The action the client loop has not collected yet, and the flag that
 * keeps the overlay pass from drawing the same screen twice in one frame. */
static int s_menu_action;

static VkInstance s_instance = VK_NULL_HANDLE;
static VkSurfaceKHR s_surface = VK_NULL_HANDLE;
static VkPhysicalDevice s_phys_dev = VK_NULL_HANDLE;
static VkDevice s_device = VK_NULL_HANDLE;
static uint32_t s_graphics_queue_idx = 0;
static VkQueue s_graphics_queue = VK_NULL_HANDLE;

static VkSwapchainKHR s_swapchain = VK_NULL_HANDLE;
static VkFormat s_swapchain_format = VK_FORMAT_B8G8R8A8_UNORM;
static VkExtent2D s_swapchain_extent = {0, 0};
static uint32_t s_swapchain_image_count = 0;
static VkImage* s_swapchain_images = NULL;
static VkImageView* s_swapchain_image_views = NULL;

static VkImage s_depth_image = VK_NULL_HANDLE;
static VkDeviceMemory s_depth_memory = VK_NULL_HANDLE;
static VkImageView s_depth_view = VK_NULL_HANDLE;

static VkRenderPass s_render_pass = VK_NULL_HANDLE;
static VkFramebuffer* s_framebuffers = NULL;

static VkCommandPool s_command_pool = VK_NULL_HANDLE;
static VkCommandBuffer s_command_buffers[MAX_FRAMES_IN_FLIGHT];
static VkSemaphore s_image_avail_sem[MAX_FRAMES_IN_FLIGHT];
static VkSemaphore s_render_done_sem[MAX_FRAMES_IN_FLIGHT];
static VkFence s_in_flight_fences[MAX_FRAMES_IN_FLIGHT];
static uint32_t s_current_frame = 0;

static VkDescriptorSetLayout s_terrain_ds_layout = VK_NULL_HANDLE;
static VkDescriptorSetLayout s_gui_ds_layout = VK_NULL_HANDLE;
static VkPipelineLayout s_terrain_pipe_layout = VK_NULL_HANDLE;
static VkPipelineLayout s_gui_pipe_layout = VK_NULL_HANDLE;

static VkPipeline s_terrain_opaque_pipe = VK_NULL_HANDLE;
static VkPipeline s_terrain_translucent_pipe = VK_NULL_HANDLE;
static VkPipeline s_gui_pipe = VK_NULL_HANDLE;

static VkDescriptorPool s_descriptor_pool = VK_NULL_HANDLE;
static VkDescriptorSet s_terrain_descriptor_set = VK_NULL_HANDLE;
static VkDescriptorSet s_gui_descriptor_set = VK_NULL_HANDLE;

static VkImage s_atlas_image = VK_NULL_HANDLE;
static VkDeviceMemory s_atlas_memory = VK_NULL_HANDLE;
static VkImageView s_atlas_view = VK_NULL_HANDLE;
static VkSampler s_atlas_sampler = VK_NULL_HANDLE;

static VkBuffer s_terrain_ubo_buf = VK_NULL_HANDLE;
static VkDeviceMemory s_terrain_ubo_mem = VK_NULL_HANDLE;

static VkBuffer s_world_vbo = VK_NULL_HANDLE;
static VkDeviceMemory s_world_vbo_mem = VK_NULL_HANDLE;
static VkBuffer s_world_ibo = VK_NULL_HANDLE;
static VkDeviceMemory s_world_ibo_mem = VK_NULL_HANDLE;

static GpuTerrainVertex* s_world_vert_cache = NULL;
static uint32_t* s_world_idx_cache = NULL;
static int s_total_verts = 0;
static int s_total_indices = 0;
static int s_world_vbo_dirty = 0;

static ChunkSectionMesh s_chunk_meshes[MAX_SECTIONS];
/* Slots handed out, sections alive, and vertex records left behind by
 * replaced or evicted sections. */
static int s_section_slots = 0;
static int s_section_live = 0;
static int s_verts_dead = 0;
/* Sections the frustum accepted in the frame just recorded. */
static int s_sections_visible = 0;

static VkBuffer s_gui_vbo = VK_NULL_HANDLE;
static VkDeviceMemory s_gui_vbo_mem = VK_NULL_HANDLE;
static GpuGuiVertex* s_gui_verts = NULL;
static int s_gui_vert_count = 0;

/* Camera & Control */
static float s_cam_x = 8.5f;
static float s_cam_y = 66.5f;
static float s_cam_z = 8.5f;
static float s_cam_yaw = -45.0f;
static float s_cam_pitch = -20.0f;
static float s_world_time = 0.0f;
static int s_key_w = 0, s_key_s = 0, s_key_a = 0, s_key_d = 0;
static int s_key_space = 0, s_key_shift = 0;
static int s_mouse_grabbed = 0;

/* The matrix the frame just recorded. The sky bodies live in the GUI pipeline,
 * which has no 3D transform, so it projects a world-space direction through
 * the terrain's own view/projection to find their screen pixels. */
static float s_viewproj[16];
static int s_viewproj_valid = 0;
/* GUI vertices holding the sky bodies, drawn before the terrain pass; the HUD
 * pass starts at this firstVertex offset. */
static int s_gui_sky_count = 0;

/* ---- Client state from a Play session -----------------------------------
 *
 * Zero until a session publishes a view. While it is set the renderer is a
 * viewer for a world the protocol loaded: the camera follows the player the
 * server moves, the sky runs on the world's day time, the fog stops where the
 * server's view distance stops, and the HUD reports the real health, hunger,
 * experience and held slot. */
static int s_view_live = 0;
static double s_srv_x = 0.0, s_srv_y = 0.0, s_srv_z = 0.0;
static int s_look_taken = 0;
static float s_day_time = 6000.0f;
static float s_health = 20.0f;
static float s_food = 20.0f;
static float s_saturation = 5.0f;
static float s_xp_progress = 0.0f;
static float s_xp_level = 0.0f;
static int s_held_slot = 0;
static int s_game_mode = 0;
static int s_view_distance = 8;

/* Sky, fog and haze for the frame being prepared. */
static float s_sky_rgb[3] = {0.47f, 0.65f, 1.0f};
static float s_fog_rgb[3] = {0.75f, 0.85f, 1.0f};
static float s_sky_brightness = 1.0f;
static float s_fog_start = 45.0f;
static float s_fog_end = 96.0f;
/* Unit vector toward the sun, and the daylight the sky is running on. The sky
 * bodies are drawn from these; the star sphere turns with the same angle. */
static float s_sun_dir[3] = {1.0f, 0.0f, 0.0f};
static float s_star_angle = 0.0f;
static float s_daylight = 1.0f;

/* Minecraft's day runs 0..24000 ticks with sunrise at 0, noon at 6000, sunset
 * at 12000 and midnight at 18000, so the sun's height above the horizon is a
 * sine of that angle. Everything else follows from it: how bright the sky
 * light is, which way the horizon tints, and how far the haze reaches. */
static void vk_sky_model(float day_time, int view_distance) {
    float cycle = day_time - 24000.0f * floorf(day_time / 24000.0f);
    float elevation = sinf(cycle / 24000.0f * 2.0f * PI);
    /* Full daylight above +0.15, full night below -0.15, a ramp between. */
    float daylight = (elevation + 0.15f) / 0.3f;
    if (daylight < 0.0f) daylight = 0.0f;
    if (daylight > 1.0f) daylight = 1.0f;
    /* Strongest exactly at the horizon, gone once the sun has cleared it. */
    float dusk = 1.0f - (elevation < 0.0f ? -elevation : elevation) / 0.15f;
    if (dusk < 0.0f) dusk = 0.0f;
    if (dusk > 1.0f) dusk = 1.0f;

    /* Night keeps a floor: skylit stone is dim, never black, the way the
     * vanilla lightmap leaves it. */
    s_sky_brightness = 0.12f + 0.88f * daylight;

    s_sky_rgb[0] = 0.03f + (0.47f - 0.03f) * daylight;
    s_sky_rgb[1] = 0.04f + (0.65f - 0.04f) * daylight;
    s_sky_rgb[2] = 0.09f + (1.00f - 0.09f) * daylight;
    s_sky_rgb[0] += (0.95f - s_sky_rgb[0]) * dusk * 0.5f;
    s_sky_rgb[1] += (0.52f - s_sky_rgb[1]) * dusk * 0.35f;

    s_fog_rgb[0] = 0.04f + (0.75f - 0.04f) * daylight;
    s_fog_rgb[1] = 0.05f + (0.85f - 0.05f) * daylight;
    s_fog_rgb[2] = 0.10f + (1.00f - 0.10f) * daylight;
    s_fog_rgb[0] += (0.98f - s_fog_rgb[0]) * dusk * 0.5f;
    s_fog_rgb[1] += (0.60f - s_fog_rgb[1]) * dusk * 0.35f;
    s_fog_rgb[2] += (0.40f - s_fog_rgb[2]) * dusk * 0.25f;

    s_daylight = daylight;
    /* The sun's path lies in the east/up plane, so its direction is the angle
     * the sky model already uses; the star sphere rotates by the same amount
     * about the north axis and the moon takes the opposite point. */
    s_star_angle = cycle / 24000.0f * 2.0f * PI;
    s_sun_dir[0] = cosf(s_star_angle);
    s_sun_dir[1] = sinf(s_star_angle);
    s_sun_dir[2] = 0.0f;

    if (!s_view_live)
        return;
    /* Vanilla ends the haze at the server's view distance, and starts it far
     * enough in that the chunks nearest the player stay crisp. */
    int distance = view_distance > 0 ? view_distance : 8;
    s_fog_end = (float)(distance * 16 - 8);
    s_fog_start = s_fog_end * 0.62f;
}

/* Dialogue GUI state */
static char s_verify_status[256] = "Checking resource pack...";
static int s_pack_is_valid = 0;

/* ---- Vulkan Memory & Buffer Utilities ------------------------------------ */

static uint32_t find_memory_type(uint32_t type_filter, VkMemoryPropertyFlags props) {
    VkPhysicalDeviceMemoryProperties mem_props;
    vkGetPhysicalDeviceMemoryProperties(s_phys_dev, &mem_props);
    for (uint32_t i = 0; i < mem_props.memoryTypeCount; i++) {
        if ((type_filter & (1 << i)) &&
            (mem_props.memoryTypes[i].propertyFlags & props) == props) {
            return i;
        }
    }
    return 0;
}

static int create_buffer(VkDeviceSize size, VkBufferUsageFlags usage,
                         VkMemoryPropertyFlags props,
                         VkBuffer* out_buf, VkDeviceMemory* out_mem) {
    VkBufferCreateInfo bi = {
        .sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE
    };
    if (vkCreateBuffer(s_device, &bi, NULL, out_buf) != VK_SUCCESS) return 0;

    VkMemoryRequirements req;
    vkGetBufferMemoryRequirements(s_device, *out_buf, &req);

    VkMemoryAllocateInfo ai = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = req.size,
        .memoryTypeIndex = find_memory_type(req.memoryTypeBits, props)
    };
    if (vkAllocateMemory(s_device, &ai, NULL, out_mem) != VK_SUCCESS) return 0;
    vkBindBufferMemory(s_device, *out_buf, *out_mem, 0);
    return 1;
}

static VkShaderModule create_shader_module(const unsigned char* code, size_t size) {
    VkShaderModuleCreateInfo ci = {
        .sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = size,
        .pCode = (const uint32_t*)code
    };
    VkShaderModule mod = VK_NULL_HANDLE;
    vkCreateShaderModule(s_device, &ci, NULL, &mod);
    return mod;
}

/* ---- 8x8 Pixel Font for UI ------------------------------------------------ */

static const uint8_t FONT_8X8[128][8] = {
    [' '] = {0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00},
    ['!'] = {0x18,0x18,0x18,0x18,0x00,0x00,0x18,0x00},
    ['"'] = {0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00},
    ['#'] = {0x6c,0x6c,0xfe,0x6c,0xfe,0x6c,0x6c,0x00},
    ['$'] = {0x18,0x7e,0xc0,0x7c,0x06,0x7e,0x18,0x00},
    ['%'] = {0x00,0xc6,0xcc,0x18,0x30,0x66,0xc6,0x00},
    ['&'] = {0x38,0x6c,0x38,0x76,0xdc,0xcc,0x76,0x00},
    ['\'']= {0x30,0x30,0x10,0x00,0x00,0x00,0x00,0x00},
    ['('] = {0x0c,0x18,0x30,0x30,0x30,0x18,0x0c,0x00},
    [')'] = {0x30,0x18,0x0c,0x0c,0x0c,0x18,0x30,0x00},
    ['*'] = {0x00,0x66,0x3c,0xff,0x3c,0x66,0x00,0x00},
    ['+'] = {0x00,0x18,0x18,0x7e,0x18,0x18,0x00,0x00},
    [','] = {0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30},
    ['-'] = {0x00,0x00,0x00,0x7e,0x00,0x00,0x00,0x00},
    ['.'] = {0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00},
    ['/'] = {0x06,0x0c,0x18,0x30,0x60,0xc0,0x80,0x00},
    ['0'] = {0x7c,0xc6,0xce,0xd6,0xe6,0xc6,0x7c,0x00},
    ['1'] = {0x18,0x38,0x18,0x18,0x18,0x18,0x7e,0x00},
    ['2'] = {0x7c,0xc6,0x06,0x1c,0x30,0x60,0xfe,0x00},
    ['3'] = {0x7c,0xc6,0x06,0x3c,0x06,0xc6,0x7c,0x00},
    ['4'] = {0x1c,0x3c,0x6c,0xcc,0xfe,0x0c,0x0c,0x00},
    ['5'] = {0xfe,0xc0,0xfc,0x06,0x06,0xc6,0x7c,0x00},
    ['6'] = {0x78,0xc0,0xfc,0xc6,0xc6,0xc6,0x7c,0x00},
    ['7'] = {0xfe,0x06,0x0c,0x18,0x30,0x30,0x30,0x00},
    ['8'] = {0x7c,0xc6,0xc6,0x7c,0xc6,0xc6,0x7c,0x00},
    ['9'] = {0x7c,0xc6,0xc6,0x7e,0x06,0x0c,0x78,0x00},
    [':'] = {0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00},
    [';'] = {0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x30},
    ['<'] = {0x0c,0x18,0x30,0x60,0x30,0x18,0x0c,0x00},
    ['='] = {0x00,0x7e,0x00,0x7e,0x00,0x00,0x00,0x00},
    ['>'] = {0x30,0x18,0x0c,0x06,0x0c,0x18,0x30,0x00},
    ['?'] = {0x7c,0xc6,0x0c,0x18,0x18,0x00,0x18,0x00},
    ['@'] = {0x7c,0xc6,0xde,0xde,0xdc,0xc0,0x7c,0x00},
    ['A'] = {0x38,0x6c,0xc6,0xc6,0xfe,0xc6,0xc6,0x00},
    ['B'] = {0xfc,0x66,0x66,0x7c,0x66,0x66,0xfc,0x00},
    ['C'] = {0x3c,0x66,0xc0,0xc0,0xc0,0x66,0x3c,0x00},
    ['D'] = {0xf8,0x6c,0x66,0x66,0x66,0x6c,0xf8,0x00},
    ['E'] = {0xfe,0x62,0x68,0x78,0x68,0x62,0xfe,0x00},
    ['F'] = {0xfe,0x62,0x68,0x78,0x68,0x60,0xf0,0x00},
    ['G'] = {0x3c,0x66,0xc0,0xc0,0xce,0x66,0x3e,0x00},
    ['H'] = {0xc6,0xc6,0xc6,0xfe,0xc6,0xc6,0xc6,0x00},
    ['I'] = {0x7e,0x18,0x18,0x18,0x18,0x18,0x7e,0x00},
    ['J'] = {0x1e,0x0c,0x0c,0x0c,0xcc,0xcc,0x78,0x00},
    ['K'] = {0xe6,0x66,0x6c,0x78,0x6c,0x66,0xe6,0x00},
    ['L'] = {0xf0,0x60,0x60,0x60,0x62,0x66,0xfe,0x00},
    ['M'] = {0xc6,0xee,0xfe,0xd6,0xc6,0xc6,0xc6,0x00},
    ['N'] = {0xc6,0xe6,0xf6,0xde,0xce,0xc6,0xc6,0x00},
    ['O'] = {0x7c,0xc6,0xc6,0xc6,0xc6,0xc6,0x7c,0x00},
    ['P'] = {0xfc,0x66,0x66,0x7c,0x60,0x60,0xf0,0x00},
    ['Q'] = {0x7c,0xc6,0xc6,0xc6,0xd6,0xde,0x7c,0x0e},
    ['R'] = {0xfc,0x66,0x66,0x7c,0x6c,0x66,0xe6,0x00},
    ['S'] = {0x7c,0xc6,0x60,0x38,0x0c,0xc6,0x7c,0x00},
    ['T'] = {0x7e,0x18,0x18,0x18,0x18,0x18,0x18,0x00},
    ['U'] = {0xc6,0xc6,0xc6,0xc6,0xc6,0xc6,0x7c,0x00},
    ['V'] = {0xc6,0xc6,0xc6,0xc6,0x6c,0x38,0x10,0x00},
    ['W'] = {0xc6,0xc6,0xc6,0xd6,0xfe,0xee,0xc6,0x00},
    ['X'] = {0xc6,0xc6,0x6c,0x38,0x6c,0xc6,0xc6,0x00},
    ['Y'] = {0xc6,0xc6,0x6c,0x38,0x18,0x18,0x3c,0x00},
    ['Z'] = {0xfe,0xc6,0x0c,0x18,0x30,0x62,0xfe,0x00},
    ['['] = {0x3c,0x30,0x30,0x30,0x30,0x30,0x3c,0x00},
    ['\\']= {0xc0,0x60,0x30,0x18,0x0c,0x06,0x02,0x00},
    [']'] = {0x3c,0x0c,0x0c,0x0c,0x0c,0x0c,0x3c,0x00},
    ['^'] = {0x18,0x3c,0x66,0x00,0x00,0x00,0x00,0x00},
    ['_'] = {0x00,0x00,0x00,0x00,0x00,0x00,0xff,0x00},
    ['a'] = {0x00,0x00,0x78,0x0c,0x7c,0xcc,0x76,0x00},
    ['b'] = {0xe0,0x60,0x7c,0x66,0x66,0x66,0xdc,0x00},
    ['c'] = {0x00,0x00,0x78,0xcc,0xc0,0xcc,0x78,0x00},
    ['d'] = {0x1c,0x0c,0x7c,0xcc,0xcc,0xcc,0x76,0x00},
    ['e'] = {0x00,0x00,0x78,0xcc,0xfc,0xc0,0x78,0x00},
    ['f'] = {0x38,0x6c,0x60,0xf0,0x60,0x60,0xf0,0x00},
    ['g'] = {0x00,0x00,0x76,0xcc,0xcc,0x7c,0x0c,0xf8},
    ['h'] = {0xe0,0x60,0x6c,0x76,0x66,0x66,0xe6,0x00},
    ['i'] = {0x18,0x00,0x38,0x18,0x18,0x18,0x3c,0x00},
    ['j'] = {0x06,0x00,0x0e,0x06,0x06,0x66,0x66,0x3c},
    ['k'] = {0xe0,0x60,0x66,0x6c,0x78,0x6c,0xe6,0x00},
    ['l'] = {0x38,0x18,0x18,0x18,0x18,0x18,0x3c,0x00},
    ['m'] = {0x00,0x00,0xec,0xfe,0xd6,0xc6,0xc6,0x00},
    ['n'] = {0x00,0x00,0xdc,0x66,0x66,0x66,0x66,0x00},
    ['o'] = {0x00,0x00,0x78,0xcc,0xcc,0xcc,0x78,0x00},
    ['p'] = {0x00,0x00,0xdc,0x66,0x66,0x7c,0x60,0xf0},
    ['q'] = {0x00,0x00,0x76,0xcc,0xcc,0x7c,0x0c,0x1e},
    ['r'] = {0x00,0x00,0xdc,0x76,0x60,0x60,0xf0,0x00},
    ['s'] = {0x00,0x00,0x7c,0xc0,0x78,0x0c,0xf8,0x00},
    ['t'] = {0x10,0x30,0x7c,0x30,0x30,0x34,0x18,0x00},
    ['u'] = {0x00,0x00,0xcc,0xcc,0xcc,0xcc,0x76,0x00},
    ['v'] = {0x00,0x00,0xc6,0xc6,0x6c,0x38,0x10,0x00},
    ['w'] = {0x00,0x00,0xc6,0xd6,0xfe,0xfe,0x6c,0x00},
    ['x'] = {0x00,0x00,0xc6,0x6c,0x38,0x6c,0xc6,0x00},
    ['y'] = {0x00,0x00,0xc6,0xc6,0xcc,0x78,0x0c,0xf8},
    ['z'] = {0x00,0x00,0xfc,0x98,0x30,0x64,0xfc,0x00},
    ['{'] = {0x0e,0x18,0x18,0x70,0x18,0x18,0x0e,0x00},
    ['|'] = {0x18,0x18,0x18,0x00,0x18,0x18,0x18,0x00},
    ['}'] = {0x70,0x18,0x18,0x0e,0x18,0x18,0x70,0x00},
    ['~'] = {0x76,0xdc,0x00,0x00,0x00,0x00,0x00,0x00}
};

/* ---- 2D GUI Drawing Primitives ------------------------------------------- */

static void gui_push_quad(float x, float y, float w, float h,
                          float r, float g, float b, float a) {
    if (s_gui_vert_count + 6 > MAX_GUI_VERTS) return;
    GpuGuiVertex v0 = {{x, y}, {-1.0f, -1.0f}, {r, g, b, a}};
    GpuGuiVertex v1 = {{x + w, y}, {-1.0f, -1.0f}, {r, g, b, a}};
    GpuGuiVertex v2 = {{x + w, y + h}, {-1.0f, -1.0f}, {r, g, b, a}};
    GpuGuiVertex v3 = {{x, y + h}, {-1.0f, -1.0f}, {r, g, b, a}};

    s_gui_verts[s_gui_vert_count++] = v0;
    s_gui_verts[s_gui_vert_count++] = v1;
    s_gui_verts[s_gui_vert_count++] = v2;
    s_gui_verts[s_gui_vert_count++] = v0;
    s_gui_verts[s_gui_vert_count++] = v2;
    s_gui_verts[s_gui_vert_count++] = v3;
}

/* One quad per horizontal run of lit pixels rather than one per pixel: the HUD
 * and chat lines are rebuilt every frame, so glyph text is the vertex budget. */
static void gui_draw_text(float x, float y, float scale, const char* text,
                          float r, float g, float b, float a) {
    if (!text) return;
    float cx = x;
    size_t len = strlen(text);
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)text[i];
        if (c >= 128) c = '?';
        for (int py = 0; py < 8; py++) {
            uint8_t row = FONT_8X8[c][py];
            int px = 0;
            while (px < 8) {
                if (!(row & (0x80 >> px))) { px++; continue; }
                int run = 1;
                while (px + run < 8 && (row & (0x80 >> (px + run)))) run++;
                gui_push_quad(cx + px * scale, y + py * scale,
                              run * scale, scale, r, g, b, a);
                px += run;
            }
        }
        cx += 8.0f * scale;
    }
}

/* Draws a classic beveled Minecraft stone button */
static void gui_draw_button(float x, float y, float w, float h, const char* label,
                            int hovered, int active) {
    float bg_r = active ? 0.35f : (hovered ? 0.45f : 0.30f);
    float bg_g = active ? 0.55f : (hovered ? 0.45f : 0.30f);
    float bg_b = active ? 0.35f : (hovered ? 0.45f : 0.30f);

    // Dark outline
    gui_push_quad(x, y, w, h, 0.08f, 0.08f, 0.08f, 1.0f);
    // Button body
    gui_push_quad(x + 2, y + 2, w - 4, h - 4, bg_r, bg_g, bg_b, 1.0f);
    // Top & left light bevel
    gui_push_quad(x + 2, y + 2, w - 4, 2, 0.7f, 0.7f, 0.7f, 0.8f);
    gui_push_quad(x + 2, y + 2, 2, h - 4, 0.7f, 0.7f, 0.7f, 0.8f);
    // Bottom & right dark shadow bevel
    gui_push_quad(x + 2, y + h - 4, w - 4, 2, 0.12f, 0.12f, 0.12f, 0.8f);
    gui_push_quad(x + w - 4, y + 2, 2, h - 4, 0.12f, 0.12f, 0.12f, 0.8f);

    // Text centered
    int text_len = (int)strlen(label);
    float text_w = text_len * 8.0f * 2.0f;
    float text_x = x + (w - text_w) / 2.0f;
    float text_y = y + (h - 16.0f) / 2.0f;

    // Drop shadow
    gui_draw_text(text_x + 2, text_y + 2, 2.0f, label, 0.15f, 0.15f, 0.15f, 1.0f);
    // Main text
    if (hovered) {
        gui_draw_text(text_x, text_y, 2.0f, label, 1.0f, 1.0f, 0.6f, 1.0f);
    } else {
        gui_draw_text(text_x, text_y, 2.0f, label, 0.95f, 0.95f, 0.95f, 1.0f);
    }
}

/* Draws a panel card / box */
static void gui_draw_panel(float x, float y, float w, float h, const char* title) {
    // Backdrop
    gui_push_quad(x, y, w, h, 0.12f, 0.12f, 0.14f, 0.92f);
    // Border
    gui_push_quad(x, y, w, 2, 0.4f, 0.4f, 0.45f, 1.0f);
    gui_push_quad(x, y + h - 2, w, 2, 0.2f, 0.2f, 0.25f, 1.0f);
    gui_push_quad(x, y, 2, h, 0.4f, 0.4f, 0.45f, 1.0f);
    gui_push_quad(x + w - 2, y, 2, h, 0.2f, 0.2f, 0.25f, 1.0f);

    if (title && strlen(title) > 0) {
        gui_push_quad(x + 10, y + 8, w - 20, 24, 0.20f, 0.20f, 0.24f, 1.0f);
        gui_draw_text(x + 16, y + 12, 2.0f, title, 1.0f, 0.85f, 0.3f, 1.0f);
    }
}

/* ---- Menu GUI backend ---------------------------------------------------- *
 *
 * src/render/gui.c holds the widgets and knows nothing about Vulkan, SDL or
 * the GUI vertex buffer, so it draws through these two entry points. The text
 * one takes its own device-pixel scale because a widget's logical coordinates
 * have already been multiplied by the GUI scale there. */

void vt_gui_backend_rect(float x, float y, float w, float h,
                         float r, float g, float b, float a) {
    gui_push_quad(x, y, w, h, r, g, b, a);
}

void vt_gui_backend_text(float x, float y, float scale, const char *text,
                         float r, float g, float b, float a) {
    gui_draw_text(x, y, scale, text, r, g, b, a);
}

/* ---- Dialogue GUI Rendering & Interaction -------------------------------- */

/* The dirt tiles stand in for the panorama a pack would supply: this
 * repository carries no Mojang-derived asset, and the wallpaper is the one
 * thing a menu screen draws before any widget exists. */
static void menu_backdrop(void) {
    int x, y;
    for (y = 0; y < s_height; y += 32) {
        for (x = 0; x < s_width; x += 32) {
            float n = (float)(((x * 11 + y * 17) % 19) / 200.0);
            gui_push_quad((float)x, (float)y, 32.0f, 32.0f,
                          0.14f + n, 0.10f + n * 0.7f, 0.08f + n * 0.5f, 1.0f);
        }
    }
    gui_push_quad(0.0f, 0.0f, (float)s_width, (float)s_height, 0.0f, 0.0f, 0.0f, 0.45f);
}

/* The pointer is in the menus' hands whenever a screen or an overlay is up. */
static void menu_pointer(void) {
    int mx = 0, my = 0;
    Uint32 buttons = SDL_GetMouseState(&mx, &my);
    vt_menus_set_mouse(mx, my, (buttons & SDL_BUTTON_LMASK) != 0);
}

static void menu_draw(void) {
    int scale_choice = atoi(vt_menus_get_option("guiScale", "0"));
    s_gui_vert_count = 0;
    s_gui_sky_count = 0;
    if (scale_choice >= 1 && scale_choice <= 4) vt_gui_set_scale(scale_choice, s_width, s_height);
    else vt_gui_layout(s_width, s_height);
    menu_backdrop();
    menu_pointer();
    s_menu_action = vt_menus_draw();
    if (s_menu_action == VT_MENU_ACTION_DEMO) vk_renderer_start_demo();
}

/* While a session is running the protocol loop owns the socket, so the only
 * way a menu choice reaches it is the input queue that loop already reads.
 * Chat, disconnect and return to title all travel that way; a queued line
 * goes out on the loop's next poll, which is also why a full queue is retried
 * on a later frame instead of being dropped. */
static const char *s_menu_retry;

static void menu_inject(const char *text) {
    if (mc_stdin_inject_line(text) == -2) {
        static char retry[256];
        snprintf(retry, sizeof retry, "%s", text);
        s_menu_retry = retry;
    }
}

static void menu_retry_line(void) {
    if (s_menu_retry == NULL) return;
    if (mc_stdin_inject_line(s_menu_retry) != -2) s_menu_retry = NULL;
}

static void menu_session_action(void) {
    switch (s_menu_action) {
        case VT_MENU_ACTION_SEND_CHAT:
            menu_inject(vt_menus_action_text());
            break;
        case VT_MENU_ACTION_DISCONNECT:
        case VT_MENU_ACTION_RETURN_TO_MENU:
            /* /quit is the session's own exit: it leaves the Play loop, which
             * returns to the menu loop that opened it. */
            menu_inject("/quit");
            s_menu_action = 0;
            break;
        default:
            break;
    }
}

/* The pause or death screen sits on top of the world the HUD just drew, so it
 * shares that pass's vertex buffer rather than resetting it. */
static void menu_overlay(void) {
    int scale_choice;
    if (!vt_menus_overlay_kind()) return;
    scale_choice = atoi(vt_menus_get_option("guiScale", "0"));
    if (scale_choice >= 1 && scale_choice <= 4) vt_gui_set_scale(scale_choice, s_width, s_height);
    else vt_gui_layout(s_width, s_height);
    menu_pointer();
    s_menu_action = vt_menus_draw();
    menu_session_action();
}

/* The block atlas is the pack's, so choosing a pack means uploading another
 * texture before the next world frame. */
void vk_renderer_reload_atlas(void) {
    int atlas_w = 0, atlas_h = 0;
    const unsigned char* pixels;
    VkDeviceSize image_size;
    VkBuffer staging_buf;
    VkDeviceMemory staging_mem;
    VkCommandBufferBeginInfo bi = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
    };
    VkBufferImageCopy region = {
        .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
        .imageExtent = {1, 1, 1}
    };

    if (s_atlas_image == VK_NULL_HANDLE) return;
    pixels = resource_pack_build_atlas(&atlas_w, &atlas_h);
    if (pixels == NULL || atlas_w <= 0 || atlas_h <= 0) return;
    image_size = (VkDeviceSize)(atlas_w * atlas_h * 4);
    if (create_buffer(image_size, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                      &staging_buf, &staging_mem)) {
        void* data;
        vkMapMemory(s_device, staging_mem, 0, image_size, 0, &data);
        memcpy(data, pixels, (size_t)image_size);
        vkUnmapMemory(s_device, staging_mem);

        vkBeginCommandBuffer(s_command_buffers[0], &bi);
        region.imageExtent.width = (uint32_t)atlas_w;
        region.imageExtent.height = (uint32_t)atlas_h;
        vkCmdCopyBufferToImage(s_command_buffers[0], staging_buf, s_atlas_image,
                               VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, 1, &region);
        vkEndCommandBuffer(s_command_buffers[0]);
        {
            VkSubmitInfo si = {
                .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .commandBufferCount = 1,
                .pCommandBuffers = &s_command_buffers[0]
            };
            vkQueueSubmit(s_graphics_queue, 1, &si, VK_NULL_HANDLE);
            vkQueueWaitIdle(s_graphics_queue);
        }
        vkDestroyBuffer(s_device, staging_buf, NULL);
        vkFreeMemory(s_device, staging_mem, NULL);
    }
    s_world_vbo_dirty = 1; /* the atlas index in the mesh changed meaning */
}

void vk_renderer_start_demo(void) {
    vk_renderer_reload_atlas();
    vk_renderer_generate_demo_world();
    s_state = VK_STATE_WORLD;
    s_mouse_grabbed = 1;
    vt_menus_set_ingame(1, 0);
    SDL_SetRelativeMouseMode(SDL_TRUE);
}

/* ---- In-Game HUD Rendering -----------------------------------------------
 *
 * Vanilla's status bar is pixel art drawn from the game's own textures. This
 * repository carries no Mojang-derived asset, so the same widgets are built
 * from quads here: the heart and hunger rows in the positions and at the pitch
 * vanilla uses, the experience bar and level above the hotbar, and a nine slot
 * hotbar whose selection follows the server's held slot. */

/* One 9x9 icon at (x, y), lit in (r, g, b) across the fraction `fill` of its
 * width, the rest of it left as a dark socket. */
/* ---- Sky Bodies ----------------------------------------------------------
 *
 * Vanilla paints the sun, moon and stars on a celestial sphere that turns once
 * per world day about the north axis, the moon at the point exactly opposite
 * the sun. The GUI pipeline has no 3D transform, so each direction is projected
 * with the terrain camera's own matrix and this pass runs before the terrain
 * draw, which then covers anything below the horizon. */
#define STAR_COUNT 128

static int sky_project(const float* dir, float* out_x, float* out_y) {
    if (!s_viewproj_valid) return 0;
    const float* m = s_viewproj;
    double wx = (double)s_cam_x + dir[0];
    double wy = (double)s_cam_y + dir[1];
    double wz = (double)s_cam_z + dir[2];
    /* Any point along the ray from the eye projects to the same place, so the
     * direction itself is enough; w is its signed distance in front. */
    double w = m[3] * wx + m[7] * wy + m[11] * wz + m[15];
    if (w <= 0.0001) return 0;
    double x = (m[0] * wx + m[4] * wy + m[8] * wz + m[12]) / w;
    double y = (m[1] * wx + m[5] * wy + m[9] * wz + m[13]) / w;
    *out_x = (float)(x * 0.5 + 0.5) * (float)s_width;
    *out_y = (float)(y * 0.5 + 0.5) * (float)s_height;
    return 1;
}

static void sky_draw_body(const float* dir, float size_px,
                          float r, float g, float b, float a) {
    float px = 0.0f, py = 0.0f;
    if (!sky_project(dir, &px, &py)) return;
    if (px < -size_px || px > (float)s_width + size_px) return;
    if (py < -size_px || py > (float)s_height + size_px) return;
    gui_push_quad(px - size_px * 0.5f, py - size_px * 0.5f,
                  size_px, size_px, r, g, b, a);
}

/* Pixels covered by an angle, from the vertical field of view the terrain
 * projection was built with. */
static float sky_pixels_per_radian(void) {
    return (float)s_height / (2.0f * tanf(DEG2RAD(70.0f) * 0.5f));
}

/* The golden-angle spiral gives an even spread over the sphere without a table
 * of directions, and it is the same field every night. */
static void sky_star_direction(int index, float* out) {
    float z = ((float)index + 0.5f) / (float)STAR_COUNT * 2.0f - 1.0f;
    float radius = sqrtf(1.0f - z * z);
    float phi = (float)index * 2.39996323f;
    out[0] = radius * cosf(phi);
    out[1] = radius * sinf(phi);
    out[2] = z;
}

static void render_sky_gui(void) {
    float ca = cosf(s_star_angle);
    float sa = sinf(s_star_angle);
    float night = 1.0f - s_daylight;

    if (night > 0.02f) {
        float star_size = 3.0f;
        int i;
        for (i = 0; i < STAR_COUNT; i++) {
            float base[3];
            float dir[3];
            sky_star_direction(i, base);
            dir[0] = base[0] * ca - base[1] * sa;
            dir[1] = base[0] * sa + base[1] * ca;
            dir[2] = base[2];
            /* How far the star is from the sun, in the sun's own plane. A star
             * fades out as the sun rises behind it rather than popping. */
            float away = -(dir[0] * s_sun_dir[0] + dir[1] * s_sun_dir[1]);
            if (away < 0.15f) continue;
            float edge = (away - 0.15f) / 0.35f;
            if (edge > 1.0f) edge = 1.0f;
            float magnitude = (float)((i * 37) % 100) / 100.0f;
            float size = star_size * (0.5f + magnitude * 0.7f);
            float a = night * edge * (0.3f + 0.7f * magnitude);
            sky_draw_body(dir, size, 1.0f, 1.0f, 0.92f, a);
        }
    }

    float disc = 0.055f * sky_pixels_per_radian();
    float moon_dir[3] = { -s_sun_dir[0], -s_sun_dir[1], -s_sun_dir[2] };
    sky_draw_body(moon_dir, disc, 0.92f, 0.94f, 1.0f, 1.0f);

    /* The sun washes out toward the horizon the way the sky does, so it does
     * not read as a white square against a dusk sky. */
    float dusk_warm = 1.0f - night;
    sky_draw_body(s_sun_dir, disc, 1.0f, 0.92f - 0.25f * dusk_warm,
                  0.62f - 0.3f * dusk_warm, 1.0f);
}

/* ---- Chat ----------------------------------------------------------------
 *
 * The Play session tees every line it prints into the engine's message ring,
 * so the window shows what the terminal shows. Vanilla holds a line for ten
 * seconds and fades it over three after that; the newest rests just above the
 * status bars and the older ones stack upward. */
#define CHAT_MAX_LINES 6
#define CHAT_MAX_CHARS 80
#define CHAT_HOLD_MS 10000u
#define CHAT_FADE_MS 3000u
#define CHAT_MEMORY 32

static long long s_chat_seen_serial[CHAT_MEMORY];
static Uint32 s_chat_seen_tick[CHAT_MEMORY];
static int s_chat_seen_count = 0;

static Uint32 chat_first_seen(long long serial, Uint32 now) {
    int i;
    for (i = 0; i < s_chat_seen_count; i++)
        if (s_chat_seen_serial[i] == serial) return s_chat_seen_tick[i];
    if (s_chat_seen_count == CHAT_MEMORY) {
        for (i = 1; i < CHAT_MEMORY; i++) {
            s_chat_seen_serial[i - 1] = s_chat_seen_serial[i];
            s_chat_seen_tick[i - 1] = s_chat_seen_tick[i];
        }
        s_chat_seen_count = CHAT_MEMORY - 1;
    }
    s_chat_seen_serial[s_chat_seen_count] = serial;
    s_chat_seen_tick[s_chat_seen_count] = now;
    s_chat_seen_count++;
    return now;
}

static void render_chat_hud(float bottom) {
    int rows = vt_chat_slot_count();
    int picked[CHAT_MAX_LINES];
    float fade[CHAT_MAX_LINES];
    int count = 0;
    int row;
    Uint32 now = SDL_GetTicks();

    /* Walk newest to oldest, keeping the lines that are still on screen. */
    for (row = rows - 1; row >= 0 && count < CHAT_MAX_LINES; row--) {
        long long serial = vt_chat_line_serial(row);
        const char* line;
        Uint32 age;
        if (serial == 0) continue;
        line = vt_chat_line_at(row);
        if (line[0] == 0) continue;
        age = now - chat_first_seen(serial, now);
        if (age < CHAT_HOLD_MS) {
            fade[count] = 1.0f;
        } else if (age < CHAT_HOLD_MS + CHAT_FADE_MS) {
            fade[count] = 1.0f - (float)(age - CHAT_HOLD_MS) / (float)CHAT_FADE_MS;
        } else {
            continue;
        }
        picked[count] = row;
        count++;
    }

    float scale = 1.5f;
    float line_h = 8.0f * scale + 6.0f;
    int slot;
    for (slot = 0; slot < count; slot++) {
        int index = picked[count - 1 - slot];
        float a = fade[count - 1 - slot];
        const char* text = vt_chat_line_at(index);
        char visible[CHAT_MAX_CHARS + 1];
        int chars = 0;
        float y = bottom - 118.0f - (float)slot * line_h;
        float width;
        while (chars < CHAT_MAX_CHARS && text[chars] != 0) {
            visible[chars] = text[chars];
            chars++;
        }
        visible[chars] = 0;
        width = (float)chars * 8.0f * scale;
        gui_push_quad(9.0f, y - 2.0f, width + 6.0f, 8.0f * scale + 5.0f,
                      0.0f, 0.0f, 0.0f, 0.42f * a);
        gui_draw_text(12.0f, y, scale, visible, 1.0f, 1.0f, 1.0f, a);
    }
}

static void hud_icon(float x, float y, float fill, const float* shape,
                     int cells, float r, float g, float b) {
    int i;
    for (i = 0; i < cells; i++) {
        /* shape is x, y, w, h in icon pixels */
        float sx = x + shape[i * 4 + 0];
        float sy = y + shape[i * 4 + 1];
        float sw = shape[i * 4 + 2];
        float sh = shape[i * 4 + 3];
        float edge = x + fill * 9.0f;
        float lit = sx + sw <= edge ? 1.0f : (sx < edge ? (edge - sx) / sw : 0.0f);
        if (lit < 1.0f)
            gui_push_quad(sx, sy, sw, sh, 0.12f, 0.12f, 0.14f, 0.75f);
        if (lit > 0.0f)
            gui_push_quad(sx, sy, sw * lit, sh, r, g, b, 1.0f);
    }
}

static void render_status_hud(float center_x, float bottom) {
    static const float heart[4 * 4] = {
        1.0f, 1.0f, 3.0f, 2.0f,
        5.0f, 1.0f, 3.0f, 2.0f,
        0.0f, 3.0f, 9.0f, 3.0f,
        2.0f, 6.0f, 5.0f, 2.0f,
    };
    static const float drumstick[4 * 4] = {
        4.0f, 0.0f, 4.0f, 3.0f,
        2.0f, 2.0f, 5.0f, 3.0f,
        1.0f, 5.0f, 4.0f, 2.0f,
        0.0f, 7.0f, 3.0f, 2.0f,
    };
    int i;
    float row_y = bottom - 60.0f;
    float left = center_x - 91.0f;
    float right = center_x + 91.0f - 80.0f;

    /* Hearts: two health to an icon, the last able to sit half full. */
    float hearts = s_health / 2.0f;
    for (i = 0; i < 10; i++) {
        float fill = hearts - (float)i;
        if (fill < 0.0f) fill = 0.0f;
        if (fill > 1.0f) fill = 1.0f;
        hud_icon(left + (float)i * 8.0f, row_y, fill, heart, 4, 0.85f, 0.16f, 0.2f);
    }

    /* Hunger, drained from the right the way vanilla stacks it. */
    float drumsticks = s_food / 2.0f;
    for (i = 0; i < 10; i++) {
        float fill = drumsticks - (float)(9 - i);
        if (fill < 0.0f) fill = 0.0f;
        if (fill > 1.0f) fill = 1.0f;
        hud_icon(right + (float)i * 8.0f, row_y, fill, drumstick, 4, 0.78f, 0.55f, 0.25f);
    }

    /* Experience: the progress the server reported over a dark trough, with
     * the level centred above it. */
    float bar_w = 182.0f;
    float bar_y = bottom - 44.0f;
    gui_push_quad(center_x - bar_w / 2.0f, bar_y, bar_w, 6.0f, 0.0f, 0.0f, 0.0f, 0.85f);
    if (s_xp_progress > 0.0f) {
        float progress = s_xp_progress > 1.0f ? 1.0f : s_xp_progress;
        gui_push_quad(center_x - bar_w / 2.0f + 1.0f, bar_y + 1.0f,
                      (bar_w - 2.0f) * progress, 4.0f, 0.45f, 0.9f, 0.15f, 1.0f);
    }
    if (s_xp_level > 0.0f) {
        char level[16];
        snprintf(level, sizeof(level), "%d", (int)s_xp_level);
        gui_draw_text(center_x - (float)strlen(level) * 6.0f, bar_y - 13.0f, 2.0f,
                      level, 0.45f, 0.9f, 0.15f, 1.0f);
    }

    /* Hotbar: window 0 of the protocol inventory is 46 slots, 0..8 of which
     * are these, indexed by the held slot packet. The frame is the server's. */
    float slot = 22.0f;
    float hotbar_x = center_x - slot * 4.5f;
    float hotbar_y = bottom - 30.0f;
    gui_push_quad(hotbar_x - 3.0f, hotbar_y - 3.0f, slot * 9.0f + 6.0f, slot + 6.0f,
                  0.0f, 0.0f, 0.0f, 0.65f);
    for (i = 0; i < 9; i++) {
        float sx = hotbar_x + (float)i * slot;
        gui_push_quad(sx, hotbar_y, slot - 2.0f, slot - 2.0f, 0.15f, 0.15f, 0.18f, 0.9f);
    }
    if (s_held_slot >= 0 && s_held_slot < 9) {
        float sx = hotbar_x + (float)s_held_slot * slot;
        gui_push_quad(sx - 2.0f, hotbar_y - 2.0f, slot - 6.0f, 2.0f, 1.0f, 1.0f, 1.0f, 0.9f);
        gui_push_quad(sx - 2.0f, hotbar_y + slot - 6.0f, slot - 6.0f, 2.0f, 1.0f, 1.0f, 1.0f, 0.9f);
        gui_push_quad(sx - 2.0f, hotbar_y - 2.0f, 2.0f, slot - 6.0f, 1.0f, 1.0f, 1.0f, 0.9f);
        gui_push_quad(sx + slot - 6.0f, hotbar_y - 2.0f, 2.0f, slot - 6.0f, 1.0f, 1.0f, 1.0f, 0.9f);
    }

    static const char* modes[4] = {"Survival", "Creative", "Adventure", "Spectator"};
    const char* mode = s_game_mode >= 0 && s_game_mode < 4 ? modes[s_game_mode] : "Unknown";
    gui_draw_text(left, row_y - 20.0f, 1.5f, mode, 0.8f, 0.8f, 0.8f, 0.9f);
    gui_push_quad(left, row_y - 9.0f, 80.0f, 4.0f, 0.0f, 0.0f, 0.0f, 0.7f);
    if (s_saturation > 0.0f) {
        float saturate = s_saturation / 20.0f;
        if (saturate > 1.0f) saturate = 1.0f;
        gui_push_quad(left + 1.0f, row_y - 8.0f, 78.0f * saturate, 2.0f,
                      0.95f, 0.8f, 0.2f, 1.0f);
    }
}

static void render_world_hud(void) {
    s_gui_vert_count = 0;
    render_sky_gui();
    s_gui_sky_count = s_gui_vert_count;

    // Minecraft Crosshair (+)
    float cx = s_width / 2.0f;
    float cy = s_height / 2.0f;
    float c_size = 9.0f;
    float c_thick = 2.0f;
    gui_push_quad(cx - c_size, cy - c_thick / 2.0f, c_size * 2.0f, c_thick, 1.0f, 1.0f, 1.0f, 0.85f);
    gui_push_quad(cx - c_thick / 2.0f, cy - c_size, c_thick, c_size * 2.0f, 1.0f, 1.0f, 1.0f, 0.85f);

    // Top-left Debug Info HUD (F3 style)
    char buf[128];
    const char* user = accounts_get_name(accounts_get_selected());
    snprintf(buf, sizeof(buf), "Minecraft Horizon Edition (Cpyte + Vulkan 1.4)");
    gui_draw_text(12, 12, 1.5f, buf, 1.0f, 1.0f, 1.0f, 1.0f);

    snprintf(buf, sizeof(buf), "Player: %s (UUID: %.8s...)", user, accounts_get_uuid(accounts_get_selected()));
    gui_draw_text(12, 30, 1.5f, buf, 0.9f, 0.9f, 0.5f, 1.0f);

    snprintf(buf, sizeof(buf), "XYZ: %.1f / %.1f / %.1f  (Yaw: %.1f, Pitch: %.1f)",
             s_cam_x, s_cam_y, s_cam_z, s_cam_yaw, s_cam_pitch);
    gui_draw_text(12, 48, 1.5f, buf, 0.9f, 0.9f, 0.9f, 1.0f);

    snprintf(buf, sizeof(buf), "Sections: %d live, %d in frustum | Verts: %d",
             s_section_live, s_sections_visible, s_total_verts);
    gui_draw_text(12, 66, 1.5f, buf, 0.4f, 1.0f, 0.5f, 1.0f);

    if (s_view_live) {
        snprintf(buf, sizeof(buf), "Day time %d | View distance %d | Held slot %d",
                 (int)s_day_time, s_view_distance, s_held_slot);
        gui_draw_text(12, 84, 1.5f, buf, 0.9f, 0.9f, 0.6f, 1.0f);
    }

    if (s_view_live) {
        render_status_hud(s_width / 2.0f, (float)s_height);
        render_chat_hud((float)s_height);
    }

    // Controls hint bottom-left
    if (s_view_live)
        gui_draw_text(12, s_height - 24, 1.5f,
                      "Camera follows the server | ESC: Unlock cursor | Terminal: commands and /quit",
                      0.75f, 0.85f, 1.0f, 0.9f);
    else
        gui_draw_text(12, s_height - 24, 1.5f,
                      "WASD: Move | Mouse: Look | Space/Shift: Fly | ESC: Menu / Unlock Cursor",
                      0.75f, 0.85f, 1.0f, 0.9f);

    // If mouse released (ESC pressed)
    if (!s_mouse_grabbed) {
        gui_push_quad(0, 0, s_width, s_height, 0.0f, 0.0f, 0.0f, 0.5f);
        gui_draw_panel((s_width - 320) / 2.0f, (s_height - 180) / 2.0f, 320, 180, "GAME PAUSED");
        gui_draw_button((s_width - 260) / 2.0f, (s_height - 180) / 2.0f + 50, 260, 40, "Back to Game", 1, 0);
        gui_draw_button((s_width - 260) / 2.0f, (s_height - 180) / 2.0f + 104, 260, 40, "Return to Launcher", 0, 0);
    }
}

/* ---- Landscape Generator & Meshing --------------------------------------- */

void vk_renderer_generate_demo_world(void) {
    vk_renderer_clear_world_meshes();

    // Generate a picturesque 3x3 chunk area (48x48 blocks) with rolling hills,
    // trees, sand beaches, flowers, and water
    int chunk_radius = 2; // -1 to 1 (3x3 chunks)

    for (int cx = -chunk_radius; cx <= chunk_radius; cx++) {
        for (int cz = -chunk_radius; cz <= chunk_radius; cz++) {
            // Allocate arrays for a chunk column
            int max_quads = 2048;
            int64_t* opaque_verts = (int64_t*)malloc(max_quads * 4 * 16 * sizeof(int64_t));
            int64_t* opaque_indices = (int64_t*)malloc(max_quads * 6 * sizeof(int64_t));
            int op_vert_count = 0;
            int op_idx_count = 0;

            int64_t* trans_verts = (int64_t*)malloc(512 * 4 * 16 * sizeof(int64_t));
            int64_t* trans_indices = (int64_t*)malloc(512 * 6 * sizeof(int64_t));
            int tr_vert_count = 0;
            int tr_idx_count = 0;

            // Simple height generation per column
            for (int bx = 0; bx < 16; bx++) {
                for (int bz = 0; bz < 16; bz++) {
                    int wx = cx * 16 + bx;
                    int wz = cz * 16 + bz;

                    // Smooth rolling hills
                    float h_val = 62.0f + 4.5f * sinf(wx * 0.12f) * cosf(wz * 0.12f) +
                                  2.5f * sinf(wx * 0.25f + wz * 0.18f);
                    int surface_y = (int)h_val;
                    int water_level = 62;

                    // Emit surface block (grass if >= 62, sand if 60..61, stone below)
                    int block_proto = (surface_y >= water_level) ? 2 : 12; // 2=grass, 12=sand

                    // Emit top face
                    if (op_vert_count + 4 <= max_quads * 4) {
                        int64_t* v = &opaque_verts[op_vert_count * 16];
                        int base_idx = op_vert_count;

                        int64_t x0 = (int64_t)wx * 256;
                        int64_t x1 = x0 + 256;
                        int64_t y1 = (int64_t)surface_y * 256 + 256;
                        int64_t z0 = (int64_t)wz * 256;
                        int64_t z1 = z0 + 256;

                        // 4 vertices of top quad (+Y face, face=2)
                        // v0: x0, y1, z0
                        v[0] = x0; v[1] = y1; v[2] = z0; v[3] = 0; v[4] = 0;
                        v[5] = block_proto; v[6] = 0; v[7] = 256; v[8] = 0;
                        v[9] = 3; v[10] = 240; v[11] = 0;
                        v[12] = (block_proto == 2) ? 0x79C05A : 0xFFFFFF; // grass green tint
                        v[13] = 256; v[14] = 2; v[15] = 0;

                        // v1: x1, y1, z0
                        v += 16;
                        v[0] = x1; v[1] = y1; v[2] = z0; v[3] = 256; v[4] = 0;
                        v[5] = block_proto; v[6] = 0; v[7] = 256; v[8] = 0;
                        v[9] = 3; v[10] = 240; v[11] = 0;
                        v[12] = (block_proto == 2) ? 0x79C05A : 0xFFFFFF;
                        v[13] = 256; v[14] = 2; v[15] = 0;

                        // v2: x1, y1, z1
                        v += 16;
                        v[0] = x1; v[1] = y1; v[2] = z1; v[3] = 256; v[4] = 256;
                        v[5] = block_proto; v[6] = 0; v[7] = 256; v[8] = 0;
                        v[9] = 3; v[10] = 240; v[11] = 0;
                        v[12] = (block_proto == 2) ? 0x79C05A : 0xFFFFFF;
                        v[13] = 256; v[14] = 2; v[15] = 0;

                        // v3: x0, y1, z1
                        v += 16;
                        v[0] = x0; v[1] = y1; v[2] = z1; v[3] = 0; v[4] = 256;
                        v[5] = block_proto; v[6] = 0; v[7] = 256; v[8] = 0;
                        v[9] = 3; v[10] = 240; v[11] = 0;
                        v[12] = (block_proto == 2) ? 0x79C05A : 0xFFFFFF;
                        v[13] = 256; v[14] = 2; v[15] = 0;

                        op_vert_count += 4;

                        opaque_indices[op_idx_count++] = base_idx;
                        opaque_indices[op_idx_count++] = base_idx + 1;
                        opaque_indices[op_idx_count++] = base_idx + 2;
                        opaque_indices[op_idx_count++] = base_idx;
                        opaque_indices[op_idx_count++] = base_idx + 2;
                        opaque_indices[op_idx_count++] = base_idx + 3;
                    }

                    // Water surface if surface_y < water_level
                    if (surface_y < water_level && tr_vert_count + 4 <= 512 * 4) {
                        int64_t* tv = &trans_verts[tr_vert_count * 16];
                        int t_base = tr_vert_count;

                        int64_t x0 = (int64_t)wx * 256;
                        int64_t x1 = x0 + 256;
                        int64_t wy1 = (int64_t)water_level * 256 + 220; // water height
                        int64_t z0 = (int64_t)wz * 256;
                        int64_t z1 = z0 + 256;

                        for (int k = 0; k < 4; k++) {
                            int64_t* p = tv + k * 16;
                            p[0] = (k == 1 || k == 2) ? x1 : x0;
                            p[1] = wy1;
                            p[2] = (k == 2 || k == 3) ? z1 : z0;
                            p[3] = (k == 1 || k == 2) ? 256 : 0;
                            p[4] = (k == 2 || k == 3) ? 256 : 0;
                            p[5] = 8; // water
                            p[6] = 0; p[7] = 256; p[8] = 0;
                            p[9] = 3; p[10] = 240; p[11] = 0;
                            p[12] = 0x3F76E4; // water blue tint
                            p[13] = 256; p[14] = 2; p[15] = 0;
                        }
                        tr_vert_count += 4;
                        trans_indices[tr_idx_count++] = t_base;
                        trans_indices[tr_idx_count++] = t_base + 1;
                        trans_indices[tr_idx_count++] = t_base + 2;
                        trans_indices[tr_idx_count++] = t_base;
                        trans_indices[tr_idx_count++] = t_base + 2;
                        trans_indices[tr_idx_count++] = t_base + 3;
                    }

                    // Wildflowers on grass
                    if (block_proto == 2 && ((wx * 13 + wz * 7) % 17 == 0) && op_vert_count + 8 <= max_quads * 4) {
                        int flower_proto = ((wx + wz) % 2 == 0) ? 37 : 38; // dandelion or poppy
                        int64_t x0 = (int64_t)wx * 256;
                        int64_t x1 = x0 + 256;
                        int64_t y0 = (int64_t)surface_y * 256 + 256;
                        int64_t y1 = y0 + 256;
                        int64_t z0 = (int64_t)wz * 256;
                        int64_t z1 = z0 + 256;

                        // Diagonal 1
                        int f_base = op_vert_count;
                        int64_t* fv = &opaque_verts[op_vert_count * 16];
                        fv[0]=x0; fv[1]=y0; fv[2]=z0; fv[3]=0; fv[4]=256; fv[5]=flower_proto; fv[9]=3; fv[10]=240; fv[13]=256; fv[14]=6;
                        fv+=16;
                        fv[0]=x1; fv[1]=y0; fv[2]=z1; fv[3]=256; fv[4]=256; fv[5]=flower_proto; fv[9]=3; fv[10]=240; fv[13]=256; fv[14]=6;
                        fv+=16;
                        fv[0]=x1; fv[1]=y1; fv[2]=z1; fv[3]=256; fv[4]=0; fv[5]=flower_proto; fv[9]=3; fv[10]=240; fv[13]=256; fv[14]=6;
                        fv+=16;
                        fv[0]=x0; fv[1]=y1; fv[2]=z0; fv[3]=0; fv[4]=0; fv[5]=flower_proto; fv[9]=3; fv[10]=240; fv[13]=256; fv[14]=6;

                        op_vert_count += 4;
                        opaque_indices[op_idx_count++] = f_base;
                        opaque_indices[op_idx_count++] = f_base + 1;
                        opaque_indices[op_idx_count++] = f_base + 2;
                        opaque_indices[op_idx_count++] = f_base;
                        opaque_indices[op_idx_count++] = f_base + 2;
                        opaque_indices[op_idx_count++] = f_base + 3;
                    }
                }
            }

            // Upload chunk meshes
            if (op_vert_count > 0) {
                vk_renderer_upload_chunk_mesh(cx, cz, 4, 0,
                                              opaque_verts, op_vert_count,
                                              opaque_indices, op_idx_count);
            }
            if (tr_vert_count > 0) {
                vk_renderer_upload_chunk_mesh(cx, cz, 4, 1,
                                              trans_verts, tr_vert_count,
                                              trans_indices, tr_idx_count);
            }

            free(opaque_verts);
            free(opaque_indices);
            free(trans_verts);
            free(trans_indices);
        }
    }

    printf("[Renderer] Demo world loaded: %d chunk sections meshed on GPU.\n", s_section_live);
}

/* ---- Mesh Store ----------------------------------------------------------
 *
 * A real server sends the same section again and again: chunk data, a light
 * update, then a block change. Appending each of those would bury the player
 * under stale geometry, so the store is keyed by (column, section, pass) and
 * replaces in place. Freed vertices are tallied, and once enough of the cache
 * is stale it is compacted; when the cache itself is full the sections
 * furthest from the camera are dropped first, which is the render-distance
 * walk Horizon applies from the other side. */

static ChunkSectionMesh* vk_section_find(int chunk_x, int chunk_z, int section_y,
                                         int translucent) {
    int i;
    for (i = 0; i < s_section_slots; i++) {
        ChunkSectionMesh* m = &s_chunk_meshes[i];
        if (m->active && m->chunk_x == chunk_x && m->chunk_z == chunk_z &&
            m->section_y == section_y && m->translucent == translucent)
            return m;
    }
    return NULL;
}

/* Distance from the camera to a section's centre, squared, in blocks. */
static float vk_section_distance2(const ChunkSectionMesh* m) {
    float cx = (m->bmin[0] + m->bmax[0]) * 0.5f - s_cam_x;
    float cy = (m->bmin[1] + m->bmax[1]) * 0.5f - s_cam_y;
    float cz = (m->bmin[2] + m->bmax[2]) * 0.5f - s_cam_z;
    return cx * cx + cy * cy + cz * cz;
}

static void vk_section_retire(ChunkSectionMesh* m) {
    if (!m->active) return;
    s_verts_dead += m->vertex_count;
    m->active = 0;
    m->visible = 0;
    s_section_live--;
}

/* The farthest live section, the one to drop before the nearest. */
static ChunkSectionMesh* vk_section_farthest(void) {
    ChunkSectionMesh* worst = NULL;
    float worst_distance = -1.0f;
    int i;
    for (i = 0; i < s_section_slots; i++) {
        ChunkSectionMesh* m = &s_chunk_meshes[i];
        if (!m->active) continue;
        float distance = vk_section_distance2(m);
        if (worst == NULL || distance > worst_distance) {
            worst = m;
            worst_distance = distance;
        }
    }
    return worst;
}

static void vk_mesh_compact(void) {
    if (s_total_verts <= 0) {
        int i;
        for (i = 0; i < s_section_slots; i++)
            s_chunk_meshes[i].active = 0;
        s_section_slots = 0;
        s_section_live = 0;
        s_verts_dead = 0;
        s_world_vbo_dirty = 1;
        return;
    }
    GpuTerrainVertex* vtmp =
        (GpuTerrainVertex*)malloc((size_t)s_total_verts * sizeof(GpuTerrainVertex));
    uint32_t* itmp = (uint32_t*)malloc((size_t)s_total_indices * sizeof(uint32_t));
    if (vtmp == NULL || itmp == NULL) {
        free(vtmp);
        free(itmp);
        return;
    }
    int vertices = 0;
    int indices = 0;
    int i;
    for (i = 0; i < s_section_slots; i++) {
        ChunkSectionMesh* m = &s_chunk_meshes[i];
        if (!m->active) continue;
        memcpy(vtmp + vertices, s_world_vert_cache + m->vertex_offset,
               (size_t)m->vertex_count * sizeof(GpuTerrainVertex));
        int k;
        for (k = 0; k < m->index_count; k++)
            itmp[indices + k] =
                s_world_idx_cache[m->index_offset + k] - m->vertex_offset + vertices;
        m->vertex_offset = vertices;
        m->index_offset = indices;
        vertices += m->vertex_count;
        indices += m->index_count;
    }
    memcpy(s_world_vert_cache, vtmp, (size_t)vertices * sizeof(GpuTerrainVertex));
    memcpy(s_world_idx_cache, itmp, (size_t)indices * sizeof(uint32_t));
    free(vtmp);
    free(itmp);
    s_total_verts = vertices;
    s_total_indices = indices;
    s_verts_dead = 0;
    s_world_vbo_dirty = 1;
}

/* Room for one more section, compacting and evicting if it takes that. */
static int vk_mesh_room_for(int vertex_count, int index_count) {
    if (s_verts_dead > s_total_verts / 3 && s_verts_dead > 4096)
        vk_mesh_compact();
    while (s_total_verts + vertex_count > MAX_WORLD_VERTS ||
           s_total_indices + index_count > MAX_WORLD_INDICES) {
        ChunkSectionMesh* far = vk_section_farthest();
        if (far == NULL)
            return 0;
        vk_section_retire(far);
        vk_mesh_compact();
        if (s_section_live == 0 && s_total_verts >= vertex_count)
            return 0;
    }
    return 1;
}

static ChunkSectionMesh* vk_section_slot(void) {
    int i;
    for (i = 0; i < s_section_slots; i++) {
        if (!s_chunk_meshes[i].active)
            return &s_chunk_meshes[i];
    }
    if (s_section_slots < MAX_SECTIONS)
        return &s_chunk_meshes[s_section_slots++];
    /* Every slot is live: reuse the farthest, which is exactly the section a
     * render-distance walk would have refused to keep. */
    ChunkSectionMesh* far = vk_section_farthest();
    if (far == NULL)
        return NULL;
    vk_section_retire(far);
    return far;
}

/* ---- Mesh Upload Implementation ------------------------------------------ */

int vk_renderer_upload_chunk_mesh(int chunk_x, int chunk_z, int section_y,
                                  int translucent,
                                  const int64_t* verts, int vertex_count,
                                  const int64_t* indices, int index_count) {
    if (vertex_count <= 0 || index_count <= 0) return 0;
    ChunkSectionMesh* old = vk_section_find(chunk_x, chunk_z, section_y, translucent);
    if (old != NULL)
        vk_section_retire(old);
    if (!vk_mesh_room_for(vertex_count, index_count)) return 0;

    int v_start = s_total_verts;
    int i_start = s_total_indices;

    float bmin[3] = {1e30f, 1e30f, 1e30f};
    float bmax[3] = {-1e30f, -1e30f, -1e30f};
    for (int i = 0; i < vertex_count; i++) {
        const int64_t* src = verts + i * 16;
        GpuTerrainVertex* dst = &s_world_vert_cache[v_start + i];
        dst->pos[0] = (float)src[0] / 256.0f;
        dst->pos[1] = (float)src[1] / 256.0f;
        dst->pos[2] = (float)src[2] / 256.0f;
        dst->uv[0]  = (float)src[3] / 256.0f;
        dst->uv[1]  = (float)src[4] / 256.0f;
        dst->layer  = (uint32_t)src[5];
        dst->normal[0] = (float)src[6] / 256.0f;
        dst->normal[1] = (float)src[7] / 256.0f;
        dst->normal[2] = (float)src[8] / 256.0f;
        dst->ao     = (float)src[9];
        dst->light[0] = (float)src[10];
        dst->light[1] = (float)src[11];
        uint32_t tint = (uint32_t)src[12];
        dst->tint[0] = ((tint >> 16) & 0xFF) / 255.0f;
        dst->tint[1] = ((tint >> 8) & 0xFF) / 255.0f;
        dst->tint[2] = (tint & 0xFF) / 255.0f;
        dst->shade  = (float)src[13] / 256.0f;
        dst->face   = (uint32_t)src[14];
        for (int a = 0; a < 3; a++) {
            float coordinate = (&dst->pos[0])[a];
            if (coordinate < bmin[a]) bmin[a] = coordinate;
            if (coordinate > bmax[a]) bmax[a] = coordinate;
        }
    }

    for (int i = 0; i < index_count; i++) {
        s_world_idx_cache[i_start + i] = (uint32_t)(indices[i] + v_start);
    }

    ChunkSectionMesh* m = vk_section_slot();
    if (m == NULL) return 0;
    m->active = 1;
    m->chunk_x = chunk_x;
    m->chunk_z = chunk_z;
    m->section_y = section_y;
    m->translucent = translucent;
    m->vertex_offset = v_start;
    m->vertex_count = vertex_count;
    m->index_offset = i_start;
    m->index_count = index_count;
    m->bmin[0] = bmin[0]; m->bmin[1] = bmin[1]; m->bmin[2] = bmin[2];
    m->bmax[0] = bmax[0]; m->bmax[1] = bmax[1]; m->bmax[2] = bmax[2];
    m->visible = 1;
    s_section_live++;

    s_total_verts += vertex_count;
    s_total_indices += index_count;
    s_world_vbo_dirty = 1;
    return 1;
}

typedef struct {
    int64_t* data;
    size_t len;
    size_t cap;
} VTBufInternal;

typedef struct {
    VTBufInternal verts[2];
    VTBufInternal indices[2];
    int quads[2];
    int sections;
    int failed;
} VTOutInternal;

typedef struct {
    void* center;
    void* grid[27];
    int base_x;
    int base_y;
    int base_z;
    int active;
} VTJobInternal;

typedef struct {
    VTJobInternal* jobs;
    VTOutInternal* outs;
    int job_count;
    int job_capacity;
    int world_set;
} VTBatchInternal;

void vk_renderer_upload_batch(char* handle) {
    VTBatchInternal* batch = (VTBatchInternal*)handle;
    if (!batch) return;
    for (int s = 0; s < batch->job_count; s++) {
        int cx = batch->jobs[s].base_x / 16;
        int sy = batch->jobs[s].base_y / 16;
        int cz = batch->jobs[s].base_z / 16;
        for (int t = 0; t < 2; t++) {
            VTBufInternal* vb = &batch->outs[s].verts[t];
            VTBufInternal* ib = &batch->outs[s].indices[t];
            if (vb->len > 0 && ib->len > 0) {
                int vcount = (int)(vb->len / 16);
                int icount = (int)ib->len;
                vk_renderer_upload_chunk_mesh(cx, cz, sy, t, vb->data, vcount, ib->data, icount);
            }
        }
    }
}

void vk_renderer_clear_world_meshes(void) {
    int i;
    for (i = 0; i < MAX_SECTIONS; i++) {
        s_chunk_meshes[i].active = 0;
        s_chunk_meshes[i].visible = 0;
    }
    s_section_slots = 0;
    s_section_live = 0;
    s_verts_dead = 0;
    s_total_verts = 0;
    s_total_indices = 0;
    s_world_vbo_dirty = 1;
}

/* ---- Core Vulkan Initialization & Setup ---------------------------------- */

int vk_renderer_init(int width, int height, const char* title) {
    s_width = width > 0 ? width : 1152;
    s_height = height > 0 ? height : 720;

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 0;
    }

    s_window = SDL_CreateWindow(
        title ? title : "Minecraft (Horizon Cpyte Vulkan Edition)",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        s_width, s_height,
        SDL_WINDOW_VULKAN | SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE
    );
    if (!s_window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        return 0;
    }

    // 1. Vulkan Instance
    VkApplicationInfo appInfo = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Minecraft Vortex",
        .applicationVersion = VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "Vortex-Horizon",
        .engineVersion = VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = VK_API_VERSION_1_2
    };

    const char* extNames[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        "VK_EXT_metal_surface",
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME
    };

    VkInstanceCreateInfo instInfo = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        .pApplicationInfo = &appInfo,
        .enabledExtensionCount = 3,
        .ppEnabledExtensionNames = extNames
    };

    if (vkCreateInstance(&instInfo, NULL, &s_instance) != VK_SUCCESS) {
        fprintf(stderr, "vkCreateInstance failed\n");
        return 0;
    }

    // 2. Surface
    if (!SDL_Vulkan_CreateSurface(s_window, s_instance, &s_surface)) {
        fprintf(stderr, "SDL_Vulkan_CreateSurface failed\n");
        return 0;
    }

    // 3. Physical Device
    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(s_instance, &deviceCount, NULL);
    if (deviceCount == 0) return 0;
    VkPhysicalDevice* devices = (VkPhysicalDevice*)malloc(deviceCount * sizeof(VkPhysicalDevice));
    vkEnumeratePhysicalDevices(s_instance, &deviceCount, devices);
    s_phys_dev = devices[0];
    free(devices);

    // Find queue family
    uint32_t qfCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(s_phys_dev, &qfCount, NULL);
    VkQueueFamilyProperties* qfProps = (VkQueueFamilyProperties*)malloc(qfCount * sizeof(VkQueueFamilyProperties));
    vkGetPhysicalDeviceQueueFamilyProperties(s_phys_dev, &qfCount, qfProps);
    for (uint32_t i = 0; i < qfCount; i++) {
        VkBool32 presentSupport = VK_FALSE;
        vkGetPhysicalDeviceSurfaceSupportKHR(s_phys_dev, i, s_surface, &presentSupport);
        if ((qfProps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && presentSupport) {
            s_graphics_queue_idx = i;
            break;
        }
    }
    free(qfProps);

    // 4. Logical Device
    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo qci = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = s_graphics_queue_idx,
        .queueCount = 1,
        .pQueuePriorities = &queuePriority
    };

    const char* devExts[] = {
        VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        "VK_KHR_portability_subset"
    };

    VkDeviceCreateInfo devInfo = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &qci,
        .enabledExtensionCount = 2,
        .ppEnabledExtensionNames = devExts
    };

    if (vkCreateDevice(s_phys_dev, &devInfo, NULL, &s_device) != VK_SUCCESS) {
        devInfo.enabledExtensionCount = 1; // Retry without portability_subset if unsupported
        if (vkCreateDevice(s_phys_dev, &devInfo, NULL, &s_device) != VK_SUCCESS) {
            fprintf(stderr, "vkCreateDevice failed\n");
            return 0;
        }
    }
    vkGetDeviceQueue(s_device, s_graphics_queue_idx, 0, &s_graphics_queue);

    // 5. Swapchain
    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(s_phys_dev, s_surface, &caps);
    s_swapchain_extent = caps.currentExtent;
    if (s_swapchain_extent.width == 0xFFFFFFFF) {
        s_swapchain_extent.width = (uint32_t)s_width;
        s_swapchain_extent.height = (uint32_t)s_height;
    }

    VkSwapchainCreateInfoKHR sci = {
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = s_surface,
        .minImageCount = caps.minImageCount + 1 > caps.maxImageCount && caps.maxImageCount > 0 ? caps.maxImageCount : caps.minImageCount + 1,
        .imageFormat = s_swapchain_format,
        .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        .imageExtent = s_swapchain_extent,
        .imageArrayLayers = 1,
        .imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = caps.currentTransform,
        .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = VK_PRESENT_MODE_FIFO_KHR, // V-Sync 60fps
        .clipped = VK_TRUE
    };

    if (vkCreateSwapchainKHR(s_device, &sci, NULL, &s_swapchain) != VK_SUCCESS) {
        fprintf(stderr, "vkCreateSwapchainKHR failed\n");
        return 0;
    }

    vkGetSwapchainImagesKHR(s_device, s_swapchain, &s_swapchain_image_count, NULL);
    s_swapchain_images = (VkImage*)malloc(s_swapchain_image_count * sizeof(VkImage));
    vkGetSwapchainImagesKHR(s_device, s_swapchain, &s_swapchain_image_count, s_swapchain_images);

    s_swapchain_image_views = (VkImageView*)malloc(s_swapchain_image_count * sizeof(VkImageView));
    for (uint32_t i = 0; i < s_swapchain_image_count; i++) {
        VkImageViewCreateInfo ivci = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = s_swapchain_images[i],
            .viewType = VK_IMAGE_VIEW_TYPE_2D,
            .format = s_swapchain_format,
            .subresourceRange = {
                .aspectMask = VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1
            }
        };
        vkCreateImageView(s_device, &ivci, NULL, &s_swapchain_image_views[i]);
    }

    // 6. Depth Image
    VkImageCreateInfo depthImgInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = VK_FORMAT_D32_SFLOAT,
        .extent = {s_swapchain_extent.width, s_swapchain_extent.height, 1},
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
    };
    vkCreateImage(s_device, &depthImgInfo, NULL, &s_depth_image);

    VkMemoryRequirements dReq;
    vkGetImageMemoryRequirements(s_device, s_depth_image, &dReq);
    VkMemoryAllocateInfo dAlloc = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = dReq.size,
        .memoryTypeIndex = find_memory_type(dReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    };
    vkAllocateMemory(s_device, &dAlloc, NULL, &s_depth_memory);
    vkBindImageMemory(s_device, s_depth_image, s_depth_memory, 0);

    VkImageViewCreateInfo depthViewInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = s_depth_image,
        .viewType = VK_IMAGE_VIEW_TYPE_2D,
        .format = VK_FORMAT_D32_SFLOAT,
        .subresourceRange = {
            .aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1
        }
    };
    vkCreateImageView(s_device, &depthViewInfo, NULL, &s_depth_view);

    // 7. Render Pass
    VkAttachmentDescription attachments[2] = {
        // Color
        {
            .format = s_swapchain_format,
            .samples = VK_SAMPLE_COUNT_1_BIT,
            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
        },
        // Depth
        {
            .format = VK_FORMAT_D32_SFLOAT,
            .samples = VK_SAMPLE_COUNT_1_BIT,
            .loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
        }
    };

    VkAttachmentReference colorRef = {0, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL};
    VkAttachmentReference depthRef = {1, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};

    VkSubpassDescription subpass = {
        .pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorRef,
        .pDepthStencilAttachment = &depthRef
    };

    VkSubpassDependency dependency = {
        .srcSubpass = VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .srcAccessMask = 0,
        .dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT | VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
    };

    VkRenderPassCreateInfo rpInfo = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 2,
        .pAttachments = attachments,
        .subpassCount = 1,
        .pSubpasses = &subpass,
        .dependencyCount = 1,
        .pDependencies = &dependency
    };
    vkCreateRenderPass(s_device, &rpInfo, NULL, &s_render_pass);

    // 8. Framebuffers
    s_framebuffers = (VkFramebuffer*)malloc(s_swapchain_image_count * sizeof(VkFramebuffer));
    for (uint32_t i = 0; i < s_swapchain_image_count; i++) {
        VkImageView fbAttachments[] = {s_swapchain_image_views[i], s_depth_view};
        VkFramebufferCreateInfo fbInfo = {
            .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = s_render_pass,
            .attachmentCount = 2,
            .pAttachments = fbAttachments,
            .width = s_swapchain_extent.width,
            .height = s_swapchain_extent.height,
            .layers = 1
        };
        vkCreateFramebuffer(s_device, &fbInfo, NULL, &s_framebuffers[i]);
    }

    // 9. Command Pool & Buffers
    VkCommandPoolCreateInfo cpInfo = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = s_graphics_queue_idx
    };
    vkCreateCommandPool(s_device, &cpInfo, NULL, &s_command_pool);

    VkCommandBufferAllocateInfo cbAlloc = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = s_command_pool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = MAX_FRAMES_IN_FLIGHT
    };
    vkAllocateCommandBuffers(s_device, &cbAlloc, s_command_buffers);

    // Sync objects
    VkSemaphoreCreateInfo semInfo = {.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    VkFenceCreateInfo fenceInfo = {
        .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = VK_FENCE_CREATE_SIGNALED_BIT
    };
    for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
        vkCreateSemaphore(s_device, &semInfo, NULL, &s_image_avail_sem[i]);
        vkCreateSemaphore(s_device, &semInfo, NULL, &s_render_done_sem[i]);
        vkCreateFence(s_device, &fenceInfo, NULL, &s_in_flight_fences[i]);
    }

    // 10. Texture Atlas Setup
    int atlas_w = 256, atlas_h = 256;
    const unsigned char* atlas_pixels = resource_pack_build_atlas(&atlas_w, &atlas_h);

    VkImageCreateInfo atlasImgInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .extent = {(uint32_t)atlas_w, (uint32_t)atlas_h, 1},
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL,
        .usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
    };
    vkCreateImage(s_device, &atlasImgInfo, NULL, &s_atlas_image);

    VkMemoryRequirements aReq;
    vkGetImageMemoryRequirements(s_device, s_atlas_image, &aReq);
    VkMemoryAllocateInfo aAlloc = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = aReq.size,
        .memoryTypeIndex = find_memory_type(aReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    };
    vkAllocateMemory(s_device, &aAlloc, NULL, &s_atlas_memory);
    vkBindImageMemory(s_device, s_atlas_image, s_atlas_memory, 0);

    // Upload initial atlas pixels
    VkDeviceSize imgSize = atlas_w * atlas_h * 4;
    VkBuffer stagingBuf;
    VkDeviceMemory stagingMem;
    if (create_buffer(imgSize, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                      VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                      &stagingBuf, &stagingMem)) {
        void* data;
        vkMapMemory(s_device, stagingMem, 0, imgSize, 0, &data);
        memcpy(data, atlas_pixels, imgSize);
        vkUnmapMemory(s_device, stagingMem);

        VkCommandBufferBeginInfo bi = {
            .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
        };
        vkBeginCommandBuffer(s_command_buffers[0], &bi);

        // Transition undefined -> dst optimal
        VkImageMemoryBarrier barrier1 = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = s_atlas_image,
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
            .srcAccessMask = 0,
            .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT
        };
        vkCmdPipelineBarrier(s_command_buffers[0],
            VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier1);

        VkBufferImageCopy region = {
            .bufferOffset = 0,
            .imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1},
            .imageExtent = {(uint32_t)atlas_w, (uint32_t)atlas_h, 1}
        };
        vkCmdCopyBufferToImage(s_command_buffers[0], stagingBuf, s_atlas_image,
                               VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

        // Transition dst optimal -> shader read
        VkImageMemoryBarrier barrier2 = {
            .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .image = s_atlas_image,
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
            .srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
            .dstAccessMask = VK_ACCESS_SHADER_READ_BIT
        };
        vkCmdPipelineBarrier(s_command_buffers[0],
            VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier2);

        vkEndCommandBuffer(s_command_buffers[0]);
        VkSubmitInfo si = {
            .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &s_command_buffers[0]
        };
        vkQueueSubmit(s_graphics_queue, 1, &si, VK_NULL_HANDLE);
        vkQueueWaitIdle(s_graphics_queue);

        vkDestroyBuffer(s_device, stagingBuf, NULL);
        vkFreeMemory(s_device, stagingMem, NULL);
    }

    VkImageViewCreateInfo aViewInfo = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = s_atlas_image,
        .viewType = VK_IMAGE_VIEW_TYPE_2D,
        .format = VK_FORMAT_R8G8B8A8_UNORM,
        .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}
    };
    vkCreateImageView(s_device, &aViewInfo, NULL, &s_atlas_view);

    // Pixel-art nearest neighbor sampler
    VkSamplerCreateInfo sampInfo = {
        .sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = VK_FILTER_NEAREST,
        .minFilter = VK_FILTER_NEAREST,
        .addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .anisotropyEnable = VK_FALSE,
        .maxAnisotropy = 1.0f,
        .borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = VK_FALSE,
        .compareEnable = VK_FALSE,
        .mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST
    };
    vkCreateSampler(s_device, &sampInfo, NULL, &s_atlas_sampler);

    // 11. Descriptor Set Layouts & Pools
    VkDescriptorSetLayoutBinding uboLayoutBinding = {
        .binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT
    };
    VkDescriptorSetLayoutBinding samplerLayoutBinding = {
        .binding = 1,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT
    };
    VkDescriptorSetLayoutBinding terrainBindings[] = {uboLayoutBinding, samplerLayoutBinding};
    VkDescriptorSetLayoutCreateInfo terrainDsInfo = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 2,
        .pBindings = terrainBindings
    };
    vkCreateDescriptorSetLayout(s_device, &terrainDsInfo, NULL, &s_terrain_ds_layout);

    VkDescriptorSetLayoutBinding guiBinding = {
        .binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT
    };
    VkDescriptorSetLayoutCreateInfo guiDsInfo = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &guiBinding
    };
    vkCreateDescriptorSetLayout(s_device, &guiDsInfo, NULL, &s_gui_ds_layout);

    VkDescriptorPoolSize poolSizes[] = {
        {VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 4},
        {VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 4}
    };
    VkDescriptorPoolCreateInfo poolInfo = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 8,
        .poolSizeCount = 2,
        .pPoolSizes = poolSizes
    };
    vkCreateDescriptorPool(s_device, &poolInfo, NULL, &s_descriptor_pool);

    VkDescriptorSetAllocateInfo dsAlloc1 = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = s_descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &s_terrain_ds_layout
    };
    vkAllocateDescriptorSets(s_device, &dsAlloc1, &s_terrain_descriptor_set);

    VkDescriptorSetAllocateInfo dsAlloc2 = {
        .sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = s_descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &s_gui_ds_layout
    };
    vkAllocateDescriptorSets(s_device, &dsAlloc2, &s_gui_descriptor_set);

    // Uniform buffer for terrain
    create_buffer(sizeof(TerrainUbo), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                  VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                  &s_terrain_ubo_buf, &s_terrain_ubo_mem);

    VkDescriptorBufferInfo dbi = {
        .buffer = s_terrain_ubo_buf,
        .offset = 0,
        .range = sizeof(TerrainUbo)
    };
    VkDescriptorImageInfo dii = {
        .sampler = s_atlas_sampler,
        .imageView = s_atlas_view,
        .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    };
    VkWriteDescriptorSet writes[3] = {
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = s_terrain_descriptor_set,
            .dstBinding = 0,
            .descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 1,
            .pBufferInfo = &dbi
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = s_terrain_descriptor_set,
            .dstBinding = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .pImageInfo = &dii
        },
        {
            .sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = s_gui_descriptor_set,
            .dstBinding = 0,
            .descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = 1,
            .pImageInfo = &dii
        }
    };
    vkUpdateDescriptorSets(s_device, 3, writes, 0, NULL);

    // 12. Graphics Pipelines
    VkPipelineLayoutCreateInfo tPipeLayoutInfo = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &s_terrain_ds_layout
    };
    vkCreatePipelineLayout(s_device, &tPipeLayoutInfo, NULL, &s_terrain_pipe_layout);

    VkPushConstantRange pcRange = {
        .stageFlags = VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = sizeof(float) * 2 // screenSize
    };
    VkPipelineLayoutCreateInfo gPipeLayoutInfo = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &s_gui_ds_layout,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &pcRange
    };
    vkCreatePipelineLayout(s_device, &gPipeLayoutInfo, NULL, &s_gui_pipe_layout);

    // Vertex bindings
    VkVertexInputBindingDescription tBinding = {
        .binding = 0,
        .stride = sizeof(GpuTerrainVertex),
        .inputRate = VK_VERTEX_INPUT_RATE_VERTEX
    };
    VkVertexInputAttributeDescription tAttrs[9] = {
        {0, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(GpuTerrainVertex, pos)},
        {1, 0, VK_FORMAT_R32G32_SFLOAT, offsetof(GpuTerrainVertex, uv)},
        {2, 0, VK_FORMAT_R32_UINT, offsetof(GpuTerrainVertex, layer)},
        {3, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(GpuTerrainVertex, normal)},
        {4, 0, VK_FORMAT_R32_SFLOAT, offsetof(GpuTerrainVertex, ao)},
        {5, 0, VK_FORMAT_R32G32_SFLOAT, offsetof(GpuTerrainVertex, light)},
        {6, 0, VK_FORMAT_R32G32B32_SFLOAT, offsetof(GpuTerrainVertex, tint)},
        {7, 0, VK_FORMAT_R32_SFLOAT, offsetof(GpuTerrainVertex, shade)},
        {8, 0, VK_FORMAT_R32_UINT, offsetof(GpuTerrainVertex, face)}
    };

    VkPipelineVertexInputStateCreateInfo tVertexInput = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &tBinding,
        .vertexAttributeDescriptionCount = 9,
        .pVertexAttributeDescriptions = tAttrs
    };

    VkPipelineInputAssemblyStateCreateInfo inputAssembly = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
    };

    VkViewport viewport = {0.0f, 0.0f, (float)s_swapchain_extent.width, (float)s_swapchain_extent.height, 0.0f, 1.0f};
    VkRect2D scissor = {{0, 0}, s_swapchain_extent};
    VkPipelineViewportStateCreateInfo viewportState = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor
    };

    VkPipelineRasterizationStateCreateInfo rasterizer = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = VK_POLYGON_MODE_FILL,
        .cullMode = VK_CULL_MODE_BACK_BIT,
        .frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1.0f
    };

    VkPipelineMultisampleStateCreateInfo multisampling = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = VK_SAMPLE_COUNT_1_BIT
    };

    VkPipelineDepthStencilStateCreateInfo depthStencilOpaque = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = VK_TRUE,
        .depthWriteEnable = VK_TRUE,
        .depthCompareOp = VK_COMPARE_OP_LESS_OR_EQUAL
    };

    VkPipelineColorBlendAttachmentState colorBlendAttachment = {
        .colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = VK_FALSE
    };
    VkPipelineColorBlendStateCreateInfo colorBlending = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment
    };

    VkShaderModule tVertMod = create_shader_module(g_spv_terrain_vert, g_spv_terrain_vert_len);
    VkShaderModule tFragMod = create_shader_module(g_spv_terrain_frag, g_spv_terrain_frag_len);
    VkPipelineShaderStageCreateInfo tStages[] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = tVertMod, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = tFragMod, .pName = "main"}
    };

    VkGraphicsPipelineCreateInfo pipelineInfo = {
        .sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = tStages,
        .pVertexInputState = &tVertexInput,
        .pInputAssemblyState = &inputAssembly,
        .pViewportState = &viewportState,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = &depthStencilOpaque,
        .pColorBlendState = &colorBlending,
        .layout = s_terrain_pipe_layout,
        .renderPass = s_render_pass,
        .subpass = 0
    };
    vkCreateGraphicsPipelines(s_device, VK_NULL_HANDLE, 1, &pipelineInfo, NULL, &s_terrain_opaque_pipe);

    // Translucent Pipeline
    rasterizer.cullMode = VK_CULL_MODE_NONE;
    depthStencilOpaque.depthWriteEnable = VK_FALSE;
    colorBlendAttachment.blendEnable = VK_TRUE;
    colorBlendAttachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
    colorBlendAttachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    colorBlendAttachment.colorBlendOp = VK_BLEND_OP_ADD;
    colorBlendAttachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
    colorBlendAttachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
    colorBlendAttachment.alphaBlendOp = VK_BLEND_OP_ADD;
    vkCreateGraphicsPipelines(s_device, VK_NULL_HANDLE, 1, &pipelineInfo, NULL, &s_terrain_translucent_pipe);

    // GUI Pipeline
    VkVertexInputBindingDescription gBinding = {
        .binding = 0,
        .stride = sizeof(GpuGuiVertex),
        .inputRate = VK_VERTEX_INPUT_RATE_VERTEX
    };
    VkVertexInputAttributeDescription gAttrs[3] = {
        {0, 0, VK_FORMAT_R32G32_SFLOAT, offsetof(GpuGuiVertex, pos)},
        {1, 0, VK_FORMAT_R32G32_SFLOAT, offsetof(GpuGuiVertex, uv)},
        {2, 0, VK_FORMAT_R32G32B32A32_SFLOAT, offsetof(GpuGuiVertex, color)}
    };
    VkPipelineVertexInputStateCreateInfo gVertexInput = {
        .sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &gBinding,
        .vertexAttributeDescriptionCount = 3,
        .pVertexAttributeDescriptions = gAttrs
    };

    VkShaderModule gVertMod = create_shader_module(g_spv_gui_vert, g_spv_gui_vert_len);
    VkShaderModule gFragMod = create_shader_module(g_spv_gui_frag, g_spv_gui_frag_len);
    VkPipelineShaderStageCreateInfo gStages[] = {
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_VERTEX_BIT, .module = gVertMod, .pName = "main"},
        {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_FRAGMENT_BIT, .module = gFragMod, .pName = "main"}
    };

    rasterizer.cullMode = VK_CULL_MODE_NONE;
    depthStencilOpaque.depthTestEnable = VK_FALSE;
    depthStencilOpaque.depthWriteEnable = VK_FALSE;

    pipelineInfo.pStages = gStages;
    pipelineInfo.pVertexInputState = &gVertexInput;
    pipelineInfo.layout = s_gui_pipe_layout;
    vkCreateGraphicsPipelines(s_device, VK_NULL_HANDLE, 1, &pipelineInfo, NULL, &s_gui_pipe);

    vkDestroyShaderModule(s_device, tVertMod, NULL);
    vkDestroyShaderModule(s_device, tFragMod, NULL);
    vkDestroyShaderModule(s_device, gVertMod, NULL);
    vkDestroyShaderModule(s_device, gFragMod, NULL);

    // 13. Vertex & Index Buffers
    s_world_vert_cache = (GpuTerrainVertex*)malloc(MAX_WORLD_VERTS * sizeof(GpuTerrainVertex));
    s_world_idx_cache = (uint32_t*)malloc(MAX_WORLD_INDICES * sizeof(uint32_t));
    s_gui_verts = (GpuGuiVertex*)malloc(MAX_GUI_VERTS * sizeof(GpuGuiVertex));

    create_buffer(MAX_WORLD_VERTS * sizeof(GpuTerrainVertex), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                  VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                  &s_world_vbo, &s_world_vbo_mem);

    create_buffer(MAX_WORLD_INDICES * sizeof(uint32_t), VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
                  VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                  &s_world_ibo, &s_world_ibo_mem);

    create_buffer(MAX_GUI_VERTS * sizeof(GpuGuiVertex), VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
                  VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                  &s_gui_vbo, &s_gui_vbo_mem);

    // 14. Initialize Accounts & Resource Pack
    accounts_init();
    resource_pack_discover();
    s_pack_is_valid = resource_pack_verify(resource_pack_get_current(),
                                          s_verify_status, sizeof(s_verify_status));

    printf("[Renderer] Vulkan initialized successfully on %ux%u surface.\n",
           s_swapchain_extent.width, s_swapchain_extent.height);
    return 1;
}

void vk_renderer_shutdown(void) {
    if (s_device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(s_device);

        free(s_world_vert_cache);
        free(s_world_idx_cache);
        free(s_gui_verts);

        vkDestroyBuffer(s_device, s_world_vbo, NULL);
        vkFreeMemory(s_device, s_world_vbo_mem, NULL);
        vkDestroyBuffer(s_device, s_world_ibo, NULL);
        vkFreeMemory(s_device, s_world_ibo_mem, NULL);
        vkDestroyBuffer(s_device, s_gui_vbo, NULL);
        vkFreeMemory(s_device, s_gui_vbo_mem, NULL);
        vkDestroyBuffer(s_device, s_terrain_ubo_buf, NULL);
        vkFreeMemory(s_device, s_terrain_ubo_mem, NULL);

        vkDestroySampler(s_device, s_atlas_sampler, NULL);
        vkDestroyImageView(s_device, s_atlas_view, NULL);
        vkDestroyImage(s_device, s_atlas_image, NULL);
        vkFreeMemory(s_device, s_atlas_memory, NULL);

        vkDestroyPipeline(s_device, s_terrain_opaque_pipe, NULL);
        vkDestroyPipeline(s_device, s_terrain_translucent_pipe, NULL);
        vkDestroyPipeline(s_device, s_gui_pipe, NULL);
        vkDestroyPipelineLayout(s_device, s_terrain_pipe_layout, NULL);
        vkDestroyPipelineLayout(s_device, s_gui_pipe_layout, NULL);
        vkDestroyDescriptorSetLayout(s_device, s_terrain_ds_layout, NULL);
        vkDestroyDescriptorSetLayout(s_device, s_gui_ds_layout, NULL);
        vkDestroyDescriptorPool(s_device, s_descriptor_pool, NULL);

        for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
            vkDestroySemaphore(s_device, s_image_avail_sem[i], NULL);
            vkDestroySemaphore(s_device, s_render_done_sem[i], NULL);
            vkDestroyFence(s_device, s_in_flight_fences[i], NULL);
        }

        vkDestroyCommandPool(s_device, s_command_pool, NULL);

        for (uint32_t i = 0; i < s_swapchain_image_count; i++) {
            vkDestroyFramebuffer(s_device, s_framebuffers[i], NULL);
            vkDestroyImageView(s_device, s_swapchain_image_views[i], NULL);
        }
        free(s_framebuffers);
        free(s_swapchain_image_views);
        free(s_swapchain_images);

        vkDestroyImageView(s_device, s_depth_view, NULL);
        vkDestroyImage(s_device, s_depth_image, NULL);
        vkFreeMemory(s_device, s_depth_memory, NULL);

        vkDestroyRenderPass(s_device, s_render_pass, NULL);
        vkDestroySwapchainKHR(s_device, s_swapchain, NULL);
        vkDestroyDevice(s_device, NULL);
    }

    if (s_surface != VK_NULL_HANDLE) vkDestroySurfaceKHR(s_instance, s_surface, NULL);
    if (s_instance != VK_NULL_HANDLE) vkDestroyInstance(s_instance, NULL);
    if (s_window) SDL_DestroyWindow(s_window);
    SDL_Quit();
}

int vk_renderer_poll_events(void) {
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        if (ev.type == SDL_QUIT) {
            return 0;
        } else if (ev.type == SDL_KEYDOWN) {
            if (vt_menus_overlay_kind() || s_state == VK_STATE_DIALOG) {
                /* Keys belong to the widgets until they are out of the way. */
                SDL_Keycode k = ev.key.keysym.sym;
                int code = VT_GUI_KEY_NONE;
                if (k == SDLK_BACKSPACE) code = VT_GUI_KEY_BACKSPACE;
                else if (k == SDLK_RETURN || k == SDLK_KP_ENTER) code = VT_GUI_KEY_ENTER;
                else if (k == SDLK_ESCAPE) code = VT_GUI_KEY_ESCAPE;
                else if (k == SDLK_TAB) code = VT_GUI_KEY_TAB;
                else if (k == SDLK_LEFT) code = VT_GUI_KEY_LEFT;
                else if (k == SDLK_RIGHT) code = VT_GUI_KEY_RIGHT;
                else if (k == SDLK_UP) code = VT_GUI_KEY_UP;
                else if (k == SDLK_DOWN) code = VT_GUI_KEY_DOWN;
                else if (k == SDLK_HOME) code = VT_GUI_KEY_HOME;
                else if (k == SDLK_END) code = VT_GUI_KEY_END;
                else if (k == SDLK_DELETE) code = VT_GUI_KEY_DELETE;
                vt_menus_add_key(code);
            } else if (s_state == VK_STATE_WORLD) {
                if (ev.key.keysym.sym == SDLK_ESCAPE) {
                    /* Escape opens the pause menu, which means the pointer
                     * belongs to the widgets again. */
                    vt_menus_set_overlay(s_view_live && s_health <= 0.0f ? 2 : 1);
                    s_mouse_grabbed = 0;
                    SDL_SetRelativeMouseMode(SDL_FALSE);
                } else if (ev.key.keysym.sym == SDLK_F5) {
                    /* Hand the heading back to the server. */
                    s_look_taken = 0;
                } else if (ev.key.keysym.sym == SDLK_t) {
                    vt_menus_open_chat();
                    s_mouse_grabbed = 0;
                    SDL_SetRelativeMouseMode(SDL_FALSE);
                    s_key_w = s_key_a = s_key_s = s_key_d = 0;
                } else if (ev.key.keysym.sym == SDLK_w) s_key_w = 1;
                else if (ev.key.keysym.sym == SDLK_s) s_key_s = 1;
                else if (ev.key.keysym.sym == SDLK_a) s_key_a = 1;
                else if (ev.key.keysym.sym == SDLK_d) s_key_d = 1;
                else if (ev.key.keysym.sym == SDLK_SPACE) s_key_space = 1;
                else if (ev.key.keysym.sym == SDLK_LSHIFT) s_key_shift = 1;
            }
        } else if (ev.type == SDL_KEYUP) {
            if (s_state == VK_STATE_WORLD) {
                if (ev.key.keysym.sym == SDLK_w) s_key_w = 0;
                else if (ev.key.keysym.sym == SDLK_s) s_key_s = 0;
                else if (ev.key.keysym.sym == SDLK_a) s_key_a = 0;
                else if (ev.key.keysym.sym == SDLK_d) s_key_d = 0;
                else if (ev.key.keysym.sym == SDLK_SPACE) s_key_space = 0;
                else if (ev.key.keysym.sym == SDLK_LSHIFT) s_key_shift = 0;
            }
        } else if (ev.type == SDL_TEXTINPUT) {
            if (vt_menus_overlay_kind() || s_state == VK_STATE_DIALOG)
                vt_menus_add_text(ev.text.text);
        } else if (ev.type == SDL_MOUSEBUTTONDOWN) {
            if (ev.button.button != SDL_BUTTON_LEFT) continue;
            if (s_state == VK_STATE_DIALOG || vt_menus_overlay_kind()) {
                vt_menus_add_click(ev.button.x, ev.button.y);
            } else if (s_state == VK_STATE_WORLD && !s_mouse_grabbed) {
                /* A click on the world, with no menu up, takes the pointer
                 * back for look. */
                s_mouse_grabbed = 1;
                SDL_SetRelativeMouseMode(SDL_TRUE);
            }
        } else if (ev.type == SDL_MOUSEWHEEL) {
            if (s_state == VK_STATE_DIALOG || vt_menus_overlay_kind())
                vt_menus_add_wheel(ev.wheel.y);
        } else if (ev.type == SDL_MOUSEMOTION) {
            if (s_state == VK_STATE_WORLD && s_mouse_grabbed) {
                /* Mouse look is the viewer's own. While a session is live it
                 * marks the heading as taken, so the server's rotation stops
                 * overriding it while the position keeps tracking. */
                float sens = 0.15f;
                if (s_view_live) s_look_taken = 1;
                s_cam_yaw += ev.motion.xrel * sens;
                s_cam_pitch -= ev.motion.yrel * sens;
                if (s_cam_pitch > 89.0f) s_cam_pitch = 89.0f;
                if (s_cam_pitch < -89.0f) s_cam_pitch = -89.0f;
            }
        } else if (ev.type == SDL_WINDOWEVENT) {
            if (ev.window.event == SDL_WINDOWEVENT_RESIZED) {
                s_width = ev.window.data1;
                s_height = ev.window.data2;
            }
        }
    }
    return 1;
}

void vk_renderer_update(float dt) {
    s_world_time += dt;
    menu_retry_line();

    if (s_state == VK_STATE_WORLD && s_view_live) {
        /* Health decides the death screen, not a click: the server knows the
         * player is gone before the player does. */
        if (s_health <= 0.0f && vt_menus_overlay_kind() == 0) {
            vt_menus_set_overlay(2);
            s_mouse_grabbed = 0;
            SDL_SetRelativeMouseMode(SDL_FALSE);
        } else if (s_health > 0.0f && vt_menus_overlay_kind() == 2) {
            vt_menus_set_overlay(0);
        }
    }

    if (s_state == VK_STATE_WORLD && s_mouse_grabbed) {
        /* Free-look movement. While a session is live this drifts the camera
         * away from the player it follows; the player's own motion still
         * shows, because each publish translates the camera by the same
         * delta, and F5 snaps the camera back onto the player. */
        float speed = 12.0f * dt;
        float rad = DEG2RAD(s_cam_yaw);
        float sin_y = sinf(rad);
        float cos_y = cosf(rad);

        if (s_key_w) {
            s_cam_x += cos_y * speed;
            s_cam_z += sin_y * speed;
        }
        if (s_key_s) {
            s_cam_x -= cos_y * speed;
            s_cam_z -= sin_y * speed;
        }
        if (s_key_a) {
            s_cam_x += sin_y * speed;
            s_cam_z -= cos_y * speed;
        }
        if (s_key_d) {
            s_cam_x -= sin_y * speed;
            s_cam_z += cos_y * speed;
        }
        if (s_key_space) {
            s_cam_y += speed;
        }
        if (s_key_shift) {
            s_cam_y -= speed;
        }
    }
}

/* One GUI-pipeline range of the shared vertex buffer. The sky bodies and the
 * HUD are the same vertex format but sit on opposite sides of the terrain
 * draw, so the pass is issued twice per frame with different offsets. */
static void gui_draw_range(VkCommandBuffer cb, uint32_t count, uint32_t first) {
    float screenSize[2] = {(float)s_swapchain_extent.width,
                           (float)s_swapchain_extent.height};
    VkDeviceSize offsets[] = {0};
    if (count == 0) return;
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, s_gui_pipe);
    vkCmdPushConstants(cb, s_gui_pipe_layout, VK_SHADER_STAGE_VERTEX_BIT,
                       0, sizeof(screenSize), screenSize);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, s_gui_pipe_layout,
                            0, 1, &s_gui_descriptor_set, 0, NULL);
    vkCmdBindVertexBuffers(cb, 0, 1, &s_gui_vbo, offsets);
    vkCmdDraw(cb, count, 1, first, 0);
}

int vk_renderer_render_frame(void) {
    vkWaitForFences(s_device, 1, &s_in_flight_fences[s_current_frame], VK_TRUE, UINT64_MAX);

    uint32_t imageIndex = 0;
    VkResult res = vkAcquireNextImageKHR(s_device, s_swapchain, UINT64_MAX,
                                        s_image_avail_sem[s_current_frame],
                                        VK_NULL_HANDLE, &imageIndex);
    if (res != VK_SUCCESS) return 0;

    vkResetFences(s_device, 1, &s_in_flight_fences[s_current_frame]);

    // Update UBO and VBOs if needed
    if (s_state == VK_STATE_WORLD) {
        TerrainUbo ubo;
        mat4_identity(ubo.model);

        float atX = s_cam_x + cosf(DEG2RAD(s_cam_yaw)) * cosf(DEG2RAD(s_cam_pitch));
        float atY = s_cam_y + sinf(DEG2RAD(s_cam_pitch));
        float atZ = s_cam_z + sinf(DEG2RAD(s_cam_yaw)) * cosf(DEG2RAD(s_cam_pitch));
        mat4_lookat(s_cam_x, s_cam_y, s_cam_z, atX, atY, atZ, 0.0f, 1.0f, 0.0f, ubo.view);

        float aspect = (float)s_swapchain_extent.width / (float)s_swapchain_extent.height;
        float view_far = s_view_live && s_view_distance > 0
                             ? (float)(s_view_distance * 16 + 32) : 250.0f;
        mat4_perspective(DEG2RAD(70.0f), aspect, 0.1f, view_far, ubo.proj);

        /* Horizon culls per chunk section before recording it, so the geometry
         * a player cannot see costs nothing but a plane test. */
        float viewproj[16];
        mat4_multiply(ubo.view, ubo.proj, viewproj);
        frustum_from_matrix(viewproj);
        memcpy(s_viewproj, viewproj, sizeof(s_viewproj));
        s_viewproj_valid = 1;

        ubo.cameraPos[0] = s_cam_x;
        ubo.cameraPos[1] = s_cam_y;
        ubo.cameraPos[2] = s_cam_z;
        ubo.cameraPos[3] = 1.0f;

        /* Sky, fog and the brightness the sky light is scaled by, from the
         * world's day time and the server's view distance. */
        vk_sky_model(s_day_time, s_view_distance);
        ubo.skyColor[0] = s_sky_rgb[0]; ubo.skyColor[1] = s_sky_rgb[1];
        ubo.skyColor[2] = s_sky_rgb[2]; ubo.skyColor[3] = 1.0f;
        ubo.fogColor[0] = s_fog_rgb[0]; ubo.fogColor[1] = s_fog_rgb[1];
        ubo.fogColor[2] = s_fog_rgb[2]; ubo.fogColor[3] = 1.0f;
        ubo.skyBrightness = s_sky_brightness;
        ubo.time = s_world_time;
        ubo.fogStart = s_fog_start;
        ubo.fogEnd = s_fog_end;
        s_sections_visible = 0;

        for (int i = 0; i < 128; i++) {
            for (int f = 0; f < 6; f++) {
                ubo.tileMap[i * 6 + f] = resource_pack_get_tile_for_block_face(i, f);
            }
        }

        void* ubo_data;
        vkMapMemory(s_device, s_terrain_ubo_mem, 0, sizeof(TerrainUbo), 0, &ubo_data);
        memcpy(ubo_data, &ubo, sizeof(TerrainUbo));
        vkUnmapMemory(s_device, s_terrain_ubo_mem);

        if (s_world_vbo_dirty && s_total_verts > 0) {
            void* vdata;
            vkMapMemory(s_device, s_world_vbo_mem, 0, s_total_verts * sizeof(GpuTerrainVertex), 0, &vdata);
            memcpy(vdata, s_world_vert_cache, s_total_verts * sizeof(GpuTerrainVertex));
            vkUnmapMemory(s_device, s_world_vbo_mem);

            void* idata;
            vkMapMemory(s_device, s_world_ibo_mem, 0, s_total_indices * sizeof(uint32_t), 0, &idata);
            memcpy(idata, s_world_idx_cache, s_total_indices * sizeof(uint32_t));
            vkUnmapMemory(s_device, s_world_ibo_mem);

            s_world_vbo_dirty = 0;
        }

        render_world_hud();
        menu_overlay();
    } else {
        menu_draw();
    }

    // Upload GUI VBO
    if (s_gui_vert_count > 0) {
        void* gdata;
        vkMapMemory(s_device, s_gui_vbo_mem, 0, s_gui_vert_count * sizeof(GpuGuiVertex), 0, &gdata);
        memcpy(gdata, s_gui_verts, s_gui_vert_count * sizeof(GpuGuiVertex));
        vkUnmapMemory(s_device, s_gui_vbo_mem);
    }

    // Record command buffer
    VkCommandBuffer cb = s_command_buffers[s_current_frame];
    vkResetCommandBuffer(cb, 0);

    VkCommandBufferBeginInfo cbbi = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
    };
    vkBeginCommandBuffer(cb, &cbbi);

    VkClearValue clearValues[2];
    if (s_state == VK_STATE_WORLD) {
        /* The clear colour is the sky the terrain fades into at max fog. */
        clearValues[0].color = (VkClearColorValue){{s_fog_rgb[0], s_fog_rgb[1], s_fog_rgb[2], 1.0f}};
    } else {
        clearValues[0].color = (VkClearColorValue){{0.08f, 0.08f, 0.09f, 1.0f}};
    }
    clearValues[1].depthStencil = (VkClearDepthStencilValue){1.0f, 0};

    VkRenderPassBeginInfo rpbi = {
        .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = s_render_pass,
        .framebuffer = s_framebuffers[imageIndex],
        .renderArea = {{0, 0}, s_swapchain_extent},
        .clearValueCount = 2,
        .pClearValues = clearValues
    };
    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);

    VkViewport vp = {0.0f, 0.0f, (float)s_swapchain_extent.width, (float)s_swapchain_extent.height, 0.0f, 1.0f};
    vkCmdSetViewport(cb, 0, 1, &vp);
    VkRect2D sc = {{0, 0}, s_swapchain_extent};
    vkCmdSetScissor(cb, 0, 1, &sc);

    /* 1. The sky bodies, ahead of the terrain so the ground hides whatever is
     * below the horizon. */
    if (s_state == VK_STATE_WORLD)
        gui_draw_range(cb, (uint32_t)s_gui_sky_count, 0);

    if (s_state == VK_STATE_WORLD && s_total_verts > 0) {
        VkDeviceSize offsets[] = {0};
        vkCmdBindVertexBuffers(cb, 0, 1, &s_world_vbo, offsets);
        vkCmdBindIndexBuffer(cb, s_world_ibo, 0, VK_INDEX_TYPE_UINT32);
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, s_terrain_pipe_layout,
                                0, 1, &s_terrain_descriptor_set, 0, NULL);

        // 1. Opaque Pass, including the cutout layer the way Horizon draws it
        vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, s_terrain_opaque_pipe);
        for (int i = 0; i < s_section_slots; i++) {
            ChunkSectionMesh* m = &s_chunk_meshes[i];
            if (!m->active || m->translucent) continue;
            m->visible = frustum_sees_box(m->bmin, m->bmax);
            if (m->visible) {
                s_sections_visible++;
                vkCmdDrawIndexed(cb, m->index_count, 1, m->index_offset, 0, 0);
            }
        }

        // 2. Translucent Pass
        vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, s_terrain_translucent_pipe);
        for (int i = 0; i < s_section_slots; i++) {
            ChunkSectionMesh* m = &s_chunk_meshes[i];
            if (!m->active || !m->translucent) continue;
            if (frustum_sees_box(m->bmin, m->bmax))
                vkCmdDrawIndexed(cb, m->index_count, 1, m->index_offset, 0, 0);
        }
    }

    /* 3. HUD and chat, over the terrain, starting past the sky vertices. */
    gui_draw_range(cb, (uint32_t)(s_gui_vert_count - s_gui_sky_count),
                   (uint32_t)s_gui_sky_count);

    vkCmdEndRenderPass(cb);
    vkEndCommandBuffer(cb);

    // Submit & Present
    VkPipelineStageFlags waitStages[] = {VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    VkSubmitInfo submitInfo = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &s_image_avail_sem[s_current_frame],
        .pWaitDstStageMask = waitStages,
        .commandBufferCount = 1,
        .pCommandBuffers = &cb,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &s_render_done_sem[s_current_frame]
    };
    vkQueueSubmit(s_graphics_queue, 1, &submitInfo, s_in_flight_fences[s_current_frame]);

    VkPresentInfoKHR presentInfo = {
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &s_render_done_sem[s_current_frame],
        .swapchainCount = 1,
        .pSwapchains = &s_swapchain,
        .pImageIndices = &imageIndex
    };
    vkQueuePresentKHR(s_graphics_queue, &presentInfo);

    s_current_frame = (s_current_frame + 1) % MAX_FRAMES_IN_FLIGHT;
    return 1;
}

int vk_renderer_get_state(void) {
    return (int)s_state;
}

void vk_renderer_set_state(int state) {
    s_state = (VkRendererState)state;
    if (s_state == VK_STATE_WORLD) {
        vt_menus_set_ingame(1, 0);
        s_mouse_grabbed = 1;
        SDL_SetRelativeMouseMode(SDL_TRUE);
    } else {
        vt_menus_set_ingame(0, 0);
        s_mouse_grabbed = 0;
        SDL_SetRelativeMouseMode(SDL_FALSE);
    }
}

/* ---- the menus' side of the client loop -------------------------------
 *
 * The screens never start a connection: one action at a time is left here for
 * whoever runs the loop, with the world folder, address or seed it names. */

int64_t vk_renderer_menu_action(void) {
    int64_t action = s_menu_action;
    s_menu_action = 0;
    return action;
}

/* The two strings come back as plain char*, which is what Cpyte maps to a str;
 * a const char* return is a different signature to that compiler. */
char* vk_renderer_action_text(void) { return (char*)vt_menus_action_text(); }
char* vk_renderer_action_text2(void) { return (char*)vt_menus_action_text2(); }
char* vk_renderer_menu_option(const char* key) { return (char*)vt_menus_get_option(key, ""); }
int64_t vk_renderer_action_long(void) { return vt_menus_action_long(); }
int64_t vk_renderer_action_index(void) { return (int64_t)vt_menus_action_index(); }

void vk_renderer_set_menu_status(const char* text) { vt_menus_set_status(text); }
void vk_renderer_set_menu_subtitle(const char* text) { vt_menus_set_subtitle(text); }
void vk_renderer_set_menu_hardcore(int hardcore) { vt_menus_set_hardcore(hardcore); }
void vk_renderer_set_menu_death_message(const char* text) { vt_menus_set_death_message(text); }

/* 1 while the menus own the pointer, which is how the client loop knows not
 * to send movement or the camera's own look. */
int64_t vk_renderer_menus_open(void) { return vt_menus_is_grabbing(); }

void vk_renderer_set_camera(float x, float y, float z, float yaw, float pitch) {
    s_cam_x = x;
    s_cam_y = y;
    s_cam_z = z;
    s_cam_yaw = yaw;
    s_cam_pitch = pitch;
}

/* ---- View Pump ------------------------------------------------------------
 *
 * The Play loop publishes the player's view once per packet it handles. When
 * a renderer is linked it installs the function below as the pump, so each
 * publish becomes one frame: poll the window, drain the mesh batches the
 * engine finished, present. Without a pump the publish is only a store, which
 * is what keeps every headless run and every test bundle buildable without
 * the GPU libraries.
 *
 * The slots read here are the ones written by vt_publish_view in
 * src/engine/native.c. */
static void vk_renderer_view_apply(void) {
    double x = vt_view_double(0);
    double y = vt_view_double(1);
    double z = vt_view_double(2);
    double yaw = vt_view_double(3);
    double pitch = vt_view_double(4);
    float eye = (float)(y + 1.62);

    if (!s_view_live) {
        /* First frame of a session: adopt the player outright. */
        s_cam_x = (float)x;
        s_cam_y = eye;
        s_cam_z = (float)z;
        /* Minecraft's yaw runs from south toward west and a positive pitch
         * looks down, while this camera looks along +x at zero yaw and up for
         * a positive pitch: hence the quarter turn and the flip. */
        s_cam_yaw = (float)(yaw + 90.0);
        s_cam_pitch = (float)(-pitch);
    } else {
        /* Follow the player by the distance the server moved them, so a camera
         * the viewer nudged keeps its offset rather than snapping back. */
        s_cam_x += (float)(x - s_srv_x);
        s_cam_y += (float)(eye - (s_srv_y + 1.62));
        s_cam_z += (float)(z - s_srv_z);
        if (!s_look_taken) {
            s_cam_yaw = (float)(yaw + 90.0);
            s_cam_pitch = (float)(-pitch);
        }
    }
    s_srv_x = x;
    s_srv_y = y;
    s_srv_z = z;

    s_day_time = (float)vt_view_double(5);
    s_health = (float)vt_view_double(6);
    s_food = (float)vt_view_double(7);
    s_saturation = (float)vt_view_double(8);
    s_xp_progress = (float)vt_view_double(9);
    s_xp_level = (float)vt_view_double(10);
    s_held_slot = (int)vt_view_double(11);
    s_game_mode = (int)vt_view_double(12);
    s_view_distance = (int)vt_view_double(13);
    s_view_live = 1;
}

void vk_renderer_on_view(void) {
    if (s_state == VK_STATE_DIALOG) {
        vt_menus_set_ingame(1, 0);
        /* A session is running, so show the world it loaded. The cursor is
         * left alone: the terminal still owns keyboard input, /quit included. */
        s_state = VK_STATE_WORLD;
    }
    vk_renderer_view_apply();

    if (vk_renderer_poll_events() == 0) {
        vt_close_view();
        return;
    }
    vk_renderer_update(0.016f);

    char* batch = vt_mesh_batch_take();
    while (batch != NULL) {
        vk_renderer_upload_batch(batch);
        vt_mesh_batch_free(batch);
        batch = vt_mesh_batch_take();
    }

    vk_renderer_render_frame();
}

/* Handed to vt_set_view_pump as an integer, because Cpyte cannot pass a
 * function pointer through a C parameter of its own. */
void vk_renderer_attach_view_pump(void) {
    vt_set_view_pump((long long)(intptr_t)vk_renderer_on_view);
}

/* Back to a demo tour: the launcher owns the camera again. */
void vk_renderer_detach_view_pump(void) {
    vt_set_view_pump(0);
    s_view_live = 0;
    s_look_taken = 0;
    s_day_time = 6000.0f;
    s_health = 20.0f;
    s_food = 20.0f;
    s_saturation = 5.0f;
    s_xp_progress = 0.0f;
    s_xp_level = 0.0f;
    s_held_slot = 0;
    s_game_mode = 0;
    s_view_distance = 8;
}

int vk_renderer_view_is_live(void) {
    return s_view_live;
}

void vk_renderer_get_camera(float* out_x, float* out_y, float* out_z,
                            float* out_yaw, float* out_pitch) {
    if (out_x) *out_x = s_cam_x;
    if (out_y) *out_y = s_cam_y;
    if (out_z) *out_z = s_cam_z;
    if (out_yaw) *out_yaw = s_cam_yaw;
    if (out_pitch) *out_pitch = s_cam_pitch;
}
