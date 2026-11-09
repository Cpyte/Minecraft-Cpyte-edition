import stdlib


# First launch: discover a local Minecraft installation and build the block
# database from its data generator. Normal launches only verify the existing
# file, so this costs nothing once generated/blockdb.bin exists.
def ensure_block_database() -> void:
    if blockdb_load_default() == 1:
        print(f"Block database: {blockdb_block_count()} blocks, {blockdb_state_count()} states")
        return
    print("Block database not found; scanning local Minecraft installations (first launch only) ...")
    if vt_run_blockdb_setup() == 0 and blockdb_load_default() == 1:
        print(f"Block database: {blockdb_block_count()} blocks, {blockdb_state_count()} states")
        return
    print("Block database unavailable; the mesher will treat every non-air block as an opaque cube.")
    print("Install Minecraft 26.3 (protocol 777) with its Java runtime, or point VORTEX_BLOCK_DB at a generated database.")


# Exercises the chat decoder without a server by framing a plain StringTag
# component (type 8, u16 length, bytes) the way System Chat arrives on the wire.
def self_test_chat() -> void:
    print("Chat subsystem:")
    str message = "Vortex local self-test: chat decode OK"
    int length = text_len(message)
    int64[] body = new int64[3 + length]
    body[0] = 8
    body[1] = 0
    body[2] = length
    int i = 0
    while i < length:
        body[3 + i] = code_at(message, i)
        i += 1
    if print_system_chat(body, 0) != 0:
        print("  chat self-test failed")


# Builds a small decoded chunk column, sets block and sky light, then runs the
# native parallel mesher over it: the same decode -> palette -> light -> mesh
# path the Play loop uses, driven locally so no server is required.
def self_test_voxel() -> void:
    ensure_block_database()
    print("Voxel engine + light subsystem:")
    VWorld* world = vworld_new(4, 0, 2, 16, 8)
    char* column = (char*)vt_calloc_ptrs(2)
    int sy = 0
    while sy < 2:
        VSection* section = sec_new(sy)
        int x = 0
        while x < 16:
            int z = 0
            while z < 16:
                sec_block_set(section, x, 0, z, 1)
                sec_sky_light_set(section, x, 1, z, 15)
                z += 1
            x += 1
        sec_block_set(section, 4, 1, 4, 1)
        sec_block_light_set(section, 4, 1, 4, 14)
        vt_ptr_set(column, sy, (void*)section)
        sy += 1
    if vworld_replace_sections(world, 0, 0, column) == 0:
        print("  could not store the self-test chunk column")
        vworld_free_column(column, 2)
        vworld_free(world)
        return
    print(f"  block at (4,1,4): {vworld_block_at(world, 4, 1, 4)}")
    print(f"  packed light at (4,1,4): {vworld_light_at(world, 4, 1, 4)}")
    mesh_chunk_native(world, 0, 0)
    vworld_free(world)


# The session's own window. Opening it before connecting means the first Play
# packet already has somewhere to put the world: each view the protocol
# publishes drives one frame, so no second loop competes with the socket. If
# the window cannot be made the session still runs, only without a picture.
def play_with_renderer(host: str, port: int64, username: str) -> int:
    print("Opening the render window (ESC unlocks the cursor, closing it ends the session):")
    if mc_renderer_init(1280, 720, "Minecraft (Horizon Cpyte Vulkan Edition)") == 0:
        print("Vulkan renderer unavailable; connecting headless")
        return offline_login(host, port, username, 0)
    mc_renderer_attach_view_pump()
    int result = offline_login(host, port, username, 0)
    mc_renderer_detach_view_pump()
    mc_renderer_shutdown()
    return result


def run_local_self_test() -> int:
    print("Running local self-test (no server connection)")
    self_test_chat()
    self_test_voxel()
    print("Local self-test complete")
    return 0


# A decimal seed written through out, or a random one when the line is empty.
# Minecraft's seeds are 64-bit and wrap, so the parse stays in int64. Returns 1
# when the text was usable.
def read_seed(line: str, out: int64*) -> int:
    int length = text_len(line)
    if length == 0:
        out[0] = mc_time_millis()
        return 1
    int64 value = 0
    int index = 0
    int negative = 0
    if code_at(line, 0) == 45:
        negative = 1
        index = 1
    while index < length:
        int64 character = code_at(line, index)
        if character < 48 or character > 57:
            print("Invalid seed: use an optional minus sign and digits")
            return 0
        value = value * 10 + (character - 48)
        index = index + 1
    if negative == 1:
        out[0] = 0 - value
    else:
        out[0] = value
    return 1


# Single player. The world runs in this process on the embedded server's own
# threads and the session's bytes go through a pipe instead of a socket, which
# is why one executable covers both modes: multiplayer is unaffected, and the
# mode simply reports itself unavailable when the server library is missing.
def run_single_player() -> int:
    if vt_host_available() != 0:
        str reason = vt_host_error()
        print(f"Single player unavailable: {reason}")
        return 1
    print("Offline username (no password/account credentials):")
    if mc_stdin_read_line() < 0:
        print("Could not read offline username")
        return 1
    str username = mc_stdin_line_copy(0)
    mc_stdin_line_done()
    print("World seed (blank for a random one):")
    if mc_stdin_read_line() < 0:
        print("Could not read world seed")
        return 1
    str seed_text = mc_stdin_line_copy(1)
    mc_stdin_line_done()
    int64 seed = 0
    if read_seed(seed_text, &seed) == 0:
        return 1
    ensure_block_database()
    print("Starting the embedded world ...")
    if vt_host_start(seed, 8, 0) != 0:
        print("Could not start the embedded server")
        return 1
    int64 connection = vt_host_connect()
    if connection < 0:
        str reason = vt_host_error()
        print(f"Could not attach to the embedded server: {reason}")
        vt_host_stop()
        return 1
    print("Opening the render window (ESC unlocks the cursor, closing it ends the session):")
    int result = 0
    if mc_renderer_init(1280, 720, "Minecraft single player (Vortex)") == 0:
        print("Vulkan renderer unavailable; running the session headless")
        result = offline_login("localhost", 25565, username, connection)
    else:
        mc_renderer_attach_view_pump()
        result = offline_login("localhost", 25565, username, connection)
        mc_renderer_detach_view_pump()
        mc_renderer_shutdown()
    # Closing the connection makes the server save the player, and stopping it
    # afterwards runs the world's shutdown saves.
    vt_host_stop()
    return result


# An option from the menus' table, read as a number the way options.txt writes
# it. A value the player typed by hand falls back rather than crashing a frame.
def option_int(key: str, fallback: int) -> int:
    str text = mc_menu_option(key)
    int value = 0
    int index = 0
    int length = text_len(text)
    if length == 0:
        return fallback
    while index < length:
        int64 character = code_at(text, index)
        if character < 48 or character > 57:
            return fallback
        value = value * 10 + (int)character - 48
        index = index + 1
    if value < 1:
        return fallback
    return value


# One embedded world inside this process: the pipe instead of a socket, the
# server on its own threads, the window driven by the session's own publishes.
def join_embedded(seed: int64, username: str) -> int:
    if vt_host_available() != 0:
        str _reason = vt_host_error()
        mc_menu_set_status("Single player is unavailable")
        print(f"Single player unavailable: {_reason}")
        return 1
    int view_distance = option_int("renderDistance", 8)
    if view_distance > 32:
        view_distance = 32
    mc_menu_set_status("Starting the embedded server")
    if vt_host_start(seed, view_distance, 0) != 0:
        str _reason = vt_host_error()
        mc_menu_set_status("The embedded server could not start")
        print(f"Embedded server failed: {_reason}")
        return 1
    int64 connection = vt_host_connect()
    if connection < 0:
        str _reason = vt_host_error()
        mc_menu_set_status("Could not attach to the embedded server")
        print(f"Embedded attach failed: {_reason}")
        vt_host_stop()
        return 1
    mc_renderer_attach_view_pump()
    int result = offline_login("localhost", 25565, username, connection)
    mc_renderer_detach_view_pump()
    # Closing the pipe makes the server save the player; stopping it runs the
    # world's shutdown saves.
    vt_host_stop()
    mc_menu_back_to_title()
    print("Session ended; back at the title screen")
    return result


def join_network(address: str, username: str) -> int:
    int64 port = 0
    str host = resolve_address(address, &port)
    if port < 1 or port > 65535:
        mc_menu_set_status("That address has no usable port")
        print(f"Invalid address: {address}")
        return 1
    mc_menu_set_status(host)
    mc_renderer_attach_view_pump()
    int result = offline_login(host, port, username, 0)
    mc_renderer_detach_view_pump()
    mc_menu_back_to_title()
    print(f"Session with {host}:{port} ended; back at the title screen")
    return result


# The window's answer to one menu action. 1 keeps the loop alive; only "Quit
# Game" returns 0, because disconnect and return-to-title are carried back to
# the Play loop as a typed /quit and need nothing here.
def apply_menu_action(action: int, username: str) -> int:
    if action == 0:
        return 1
    if action == 1:
        # A world chosen from the list. Terrain comes from the folder's own
        # seed because reading level.dat is not wired yet, so the same folder
        # always grows the same world; the saved buildings arrive as soon as
        # the anvil reader is pointed at the embedded server's data path.
        str folder = mc_menu_action_text()
        print(f"World '{mc_menu_action_text2()}' starts from its folder seed; level.dat loading is pending")
        int64 seed = 1469598103934665603
        int index = 0
        int length = text_len(folder)
        while index < length:
            seed = (seed + code_at(folder, index)) * 1099511628211
            index = index + 1
        return join_embedded(seed, username)
    if action == 2:
        int64 seed = mc_menu_action_long()
        if seed == 0:
            seed = mc_time_millis()
        return join_embedded(seed, username)
    if action == 3 or action == 4:
        return join_network(mc_menu_action_text2(), username)
    if action == 5:
        mc_menu_store()
        return 1
    if action == 6:
        str path = mc_menu_action_text()
        if mc_menu_apply_pack(path) != 0:
            mc_renderer_reload_atlas()
            mc_menu_set_status("Resource pack applied")
        else:
            mc_menu_set_status("That pack could not be read")
        return 1
    if action == 10:
        mc_menu_scan_servers()
        return 1
    if action == 11 or action == 15:
        mc_menu_store()
        return 1
    if action == 12:
        mc_menu_scan_worlds()
        return 1
    if action == 13:
        # The window opened the demo world itself; the lists are refreshed so
        # the next screen sees whatever the run left behind.
        mc_menu_scan_worlds()
        mc_menu_scan_servers()
        return 1
    if action == 14:
        if mc_menu_delete_world(mc_menu_action_text()) == 0:
            print("Deleted the save folder")
        mc_menu_scan_worlds()
        return 1
    if action == 9:
        return 0
    return 1


# The whole client behind one window: title screen, world and server lists,
# options, the game and the pause menu, with no terminal menu in between. The
# terminal is used once, for the offline name, because a local account has no
# password and nothing else to ask.
def run_graphical_client() -> int:
    print("Offline username (no password or account credentials):")
    if mc_stdin_read_line() < 0:
        print("Could not read offline username")
        return 1
    str username = mc_stdin_line_copy(0)
    mc_stdin_line_done()
    if text_len(username) == 0:
        username = "Player"
    ensure_block_database()
    if mc_renderer_init(1280, 720, "Minecraft (Vortex Cpyte Edition)") == 0:
        print("Vulkan renderer unavailable: a Vulkan loader, SDL2 and a pack are needed")
        return 1
    mc_menu_open(username)
    int running = 1
    while running == 1:
        if mc_renderer_poll() == 0:
            running = 0
        else:
            mc_renderer_update(0.0166)
            if mc_renderer_frame() == 0:
                running = 0
            else:
                running = apply_menu_action(mc_menu_action(), username)
    mc_menu_store()
    mc_renderer_shutdown()
    return 0


def main() -> int:
    if mc_prepare_stdin() != 0:
        print("Could not configure terminal input for Play polling")
        return 1
    print("Minecraft Java Edition 26.3 client")
    print("Mode (1=status, 2=offline login, 3=local self-test, 4=start Vulkan renderer, 5=offline login with window, 6=single player with window, 7=graphical client with menus):")
    if mc_stdin_read_line() < 0:
        print("Could not read client mode")
        return 1
    str mode = mc_stdin_line_copy(0)
    mc_stdin_line_done()
    if mode == "7":
        return run_graphical_client()
    if mode == "6":
        return run_single_player()
    if mode == "4":
        return mc_renderer_start_loop()
    if mode == "3":
        return run_local_self_test()
    if mode == "2" or mode == "5":
        ensure_block_database()
    print("Server address (host or host:port; SRV lookup when no port):")
    if mc_stdin_read_line() < 0:
        print("Could not read server address")
        return 1
    str address = mc_stdin_line_copy(1)
    mc_stdin_line_done()
    int64 resolved_port = 0
    str host = resolve_address(address, &resolved_port)
    if resolved_port < 1 or resolved_port > 65535:
        print("Invalid port: enter a number from 1 to 65535")
        return 1
    print(f"Connecting to {host}:{resolved_port}")
    if mode == "2" or mode == "5":
        print("Offline username (no password/account credentials):")
        if mc_stdin_read_line() < 0:
            print("Could not read offline username")
            return 1
        str username = mc_stdin_line_copy(2)
        mc_stdin_line_done()
        if mode == "5":
            return play_with_renderer(host, resolved_port, username)
        return offline_login(host, resolved_port, username, 0)
    if mode != "" and mode != "1" and mode != "4":
        print("Invalid mode: choose 1, 2, 3, 4, 5 or 6")
        return 1
    return status_ping(host, resolved_port)
