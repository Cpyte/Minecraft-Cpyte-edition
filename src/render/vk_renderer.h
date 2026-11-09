#ifndef VK_RENDERER_H
#define VK_RENDERER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    VK_STATE_DIALOG = 0,
    VK_STATE_WORLD = 1
} VkRendererState;

/* Initializes the window, Vulkan instance, device, swapchain, pipelines and atlas */
int vk_renderer_init(int width, int height, const char* title);

/* Shuts down Vulkan and destroys window */
void vk_renderer_shutdown(void);

/* Polls input events (returns 0 if user requested window close, 1 to continue) */
int vk_renderer_poll_events(void);

/* Updates state, camera, and animations */
void vk_renderer_update(float delta_time);

/* Renders one frame (dialogue GUI or 3D world depending on state) */
int vk_renderer_render_frame(void);

/* Uploads a chunk section mesh to the GPU.
 * Verts is an array of int64_t with stride 16 (matching VT_STRIDE in mesher.c).
 * Indices is an array of int64_t.
 * translucent: 0 for opaque/cutout pass, 1 for translucent pass. */
int vk_renderer_upload_chunk_mesh(int chunk_x, int chunk_z, int section_y,
                                  int translucent,
                                  const int64_t* verts, int vertex_count,
                                  const int64_t* indices, int index_count);

/* Uploads all sections from a mesher native batch to the GPU */
void vk_renderer_upload_batch(char* batch_handle);

/* Clears all loaded GPU chunk meshes */
void vk_renderer_clear_world_meshes(void);

/* Generates and uploads a default Minecraft-like landscape into the renderer */
void vk_renderer_generate_demo_world(void);

/* Generates the demo landscape and shows it, the action a menu screen asks
 * for without a server. */
void vk_renderer_start_demo(void);

/* The menu screens' output, collected one action at a time by the loop that
 * runs the client. `vk_renderer_menus_open` is 1 while a screen owns the
 * pointer. */
int64_t vk_renderer_menu_action(void);
char* vk_renderer_action_text(void);
char* vk_renderer_action_text2(void);
char* vk_renderer_menu_option(const char* key);
void vk_renderer_reload_atlas(void);
int64_t vk_renderer_action_long(void);
int64_t vk_renderer_action_index(void);
int64_t vk_renderer_menus_open(void);
void vk_renderer_set_menu_status(const char* text);
void vk_renderer_set_menu_subtitle(const char* text);
void vk_renderer_set_menu_hardcore(int hardcore);
void vk_renderer_set_menu_death_message(const char* text);

/* State accessors */
int vk_renderer_get_state(void);
void vk_renderer_set_state(int state);

/* Camera accessors */
void vk_renderer_set_camera(float x, float y, float z, float yaw, float pitch);
void vk_renderer_get_camera(float* out_x, float* out_y, float* out_z,
                            float* out_yaw, float* out_pitch);

#ifdef __cplusplus
}
#endif

#endif
