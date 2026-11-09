# Vortex engine - Vulkan renderer bindings and game loop.
#
# Fully based on Horizon's chunk meshing and rendering architecture:
# - Horizon 16-stride vertex format (fixed point pos, normal, ao, sky/block light, tint, shade)
# - Dual-pass rendering: opaque/cutout terrain and translucent water/fluids
# - Minecraft-like lighting with ambient occlusion, directional shading, and biome tinting
# - Vulkan 1.2+ backend with MoltenVK portability on Apple Silicon / macOS
# - Startup dialogue GUI with local account management and vanilla resource pack asset verification

import "accounts.c"
import "resource_pack.c"
import "gui.c"
import "menus.c"
import "menudata.c"
import "vk_renderer.c"


public def mc_renderer_init(width: int, height: int, title: str) -> int:
    return vk_renderer_init(width, height, title)


public def mc_renderer_shutdown() -> void:
    vk_renderer_shutdown()


public def mc_renderer_poll() -> int:
    return vk_renderer_poll_events()


public def mc_renderer_update(dt: float) -> void:
    vk_renderer_update(dt)


# The engine publishes finished mesh batches into the mesher's handoff ring
# rather than calling here, so the renderer owns a batch once it takes it and
# frees it after the upload.
public def mc_renderer_drain_batches() -> int:
    int uploaded = 0
    char* batch = vmesh_take()
    while batch != null:
        vk_renderer_upload_batch(batch)
        vmesh_native_batch_free(batch)
        uploaded = uploaded + 1
        batch = vmesh_take()
    return uploaded


# A Play session installs the view pump: from then on every view the protocol
# publishes is one frame - window events polled, finished meshes drained, image
# presented - and closing the window is what ends the session. Headless runs
# never call this, so nothing here links into them.
public def mc_renderer_attach_view_pump() -> void:
    vk_renderer_attach_view_pump()


public def mc_renderer_detach_view_pump() -> void:
    vk_renderer_detach_view_pump()


public def mc_renderer_frame() -> int:
    mc_renderer_drain_batches()
    return vk_renderer_render_frame()


public def mc_renderer_upload_batch(batch: char*) -> void:
    vk_renderer_upload_batch(batch)


public def mc_renderer_generate_demo_world() -> void:
    vk_renderer_generate_demo_world()


public def mc_renderer_start_loop() -> int:
    print("Launching Minecraft Horizon Vulkan Renderer...")
    int res = vk_renderer_init(1152, 720, "Minecraft (Horizon Cpyte Vulkan Edition)")
    if res == 0:
        print("Failed to initialize Vulkan renderer")
        return 1
    print("Renderer running. Opening startup dialogue...")
    while vk_renderer_poll_events() != 0:
        vk_renderer_update(0.016)
        mc_renderer_frame()
    vk_renderer_shutdown()
    print("Renderer terminated cleanly")
    return 0


# ---- the menu screens, as the client loop sees them ----------------------
#
# src/render/menus.c draws the screens, src/render/menudata.c owns the files
# behind them, and the window turns a click into one action per frame. The
# caller's job is only to act on it: the screens never open a socket or start a
# server themselves, which is what keeps the same widgets usable headless.

public def mc_menu_open(username: str) -> int:
    return (int)vt_menudata_open(username)


public def mc_menu_dir() -> str:
    return vt_menudata_dir()


public def mc_menu_store() -> int:
    return (int)vt_menudata_store()


public def mc_menu_scan_worlds() -> int:
    return vt_menudata_scan_worlds(mc_menu_dir())


public def mc_menu_scan_servers() -> int:
    return vt_menudata_load_servers(mc_menu_dir())


public def mc_menu_delete_world(folder: str) -> int:
    return (int)vt_menudata_delete_world(folder)


public def mc_menu_apply_pack(path: str) -> int:
    return (int)vt_menudata_apply_pack(path)


public def mc_menu_action() -> int:
    return (int)vk_renderer_menu_action()


public def mc_menu_action_text() -> str:
    return vk_renderer_action_text()


public def mc_menu_action_text2() -> str:
    return vk_renderer_action_text2()


public def mc_menu_action_long() -> int64:
    return vk_renderer_action_long()


public def mc_menu_option(key: str) -> str:
    return vk_renderer_menu_option(key)


public def mc_menu_set_status(text: str) -> void:
    vk_renderer_set_menu_status(text)


public def mc_menu_set_death(text: str) -> void:
    vk_renderer_set_menu_death_message(text)


# After a session ends the window goes back to the title screen; the world's
# meshes are dropped so the next one starts from an empty scene.
public def mc_menu_back_to_title() -> void:
    vk_renderer_clear_world_meshes()
    vk_renderer_set_state(0)


public def mc_renderer_reload_atlas() -> void:
    vk_renderer_reload_atlas()
