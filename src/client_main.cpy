import stdlib


def main() -> int:
    if mc_prepare_stdin() != 0:
        print("Could not configure terminal input for Play polling")
        return 1
    print("Minecraft Java Edition 26.3 client")
    print("Mode (1=status, 2=offline login):")
    if mc_stdin_read_line() < 0:
        print("Could not read client mode")
        return 1
    str mode = mc_stdin_line_copy(0)
    mc_stdin_line_done()
    print("Server host:")
    if mc_stdin_read_line() < 0:
        print("Could not read server host")
        return 1
    str host = mc_stdin_line_copy(1)
    mc_stdin_line_done()
    print("Server port (default 25565):")
    if mc_stdin_read_line() < 0:
        print("Could not read server port")
        return 1
    str port_text = mc_stdin_line_copy(2)
    mc_stdin_line_done()
    int64[] port = parse_port(port_text)
    if port[0] != 1:
        print("Invalid port: enter a number from 1 to 65535")
        return 1
    if mode == "2":
        print("Offline username (no password/account credentials):")
        if mc_stdin_read_line() < 0:
            print("Could not read offline username")
            return 1
        str username = mc_stdin_line_copy(3)
        mc_stdin_line_done()
        return offline_login(host, port[1], username)
    if mode != "" and mode != "1":
        print("Invalid mode: choose 1 or 2")
        return 1
    return status_ping(host, port[1])
