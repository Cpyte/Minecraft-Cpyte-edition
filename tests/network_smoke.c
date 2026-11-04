/* Behaviour smoke test for the network C layer: codec round trip, big endian
 * helpers, buffered sockets, terminal lines and the poll multiplexing. Plain C
 * with a thin platform shim so the same checks run on Linux, macOS and Windows;
 * see docs/BUILD.md for the commands. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <io.h>
typedef uintptr_t peer_fd;
#define PEER_INVALID INVALID_SOCKET
#else
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
typedef int peer_fd;
#define PEER_INVALID (-1)
#endif

int64_t mc_set_compression_threshold(int64_t threshold);
int64_t mc_get_compression_threshold(void);
int64_t mc_codec_reset(void);
int64_t mc_codec_input_byte(int64_t value);
int64_t mc_codec_run(int64_t inflate, int64_t expected_length);
int64_t mc_codec_output_length(void);
int64_t mc_codec_output_byte(int64_t index);
double mc_double_from_be(int64_t b0, int64_t b1, int64_t b2, int64_t b3,
                         int64_t b4, int64_t b5, int64_t b6, int64_t b7);
int64_t mc_double_be_byte(double value, int64_t index);
int64_t mc_tcp_connect(char *host, int64_t port);
int64_t mc_tcp_send_begin(int64_t socket_handle);
int64_t mc_tcp_send_byte(int64_t value);
int64_t mc_tcp_send_end(void);
int64_t mc_tcp_recv_byte(int64_t socket_handle);
int64_t mc_tcp_close(int64_t socket_handle);
int64_t mc_prepare_stdin(void);
int64_t mc_poll_events(int64_t socket_handle);
int64_t mc_stdin_read_line(void);
int64_t mc_stdin_line_length(void);
int64_t mc_stdin_line_byte(int64_t index);
char *mc_stdin_line_copy(int64_t slot);
int64_t mc_stdin_line_done(void);
int64_t mc_time_millis(void);
int64_t mc_offline_uuid_byte(char *name, int64_t index);
int64_t mc_string_length(char *text);

static int failures = 0;

static void check(const char *what, int ok) {
    if (ok) return;
    failures++;
    printf("  FAIL %s\n", what);
}

static long peer_send(peer_fd fd, const unsigned char *data, size_t length) {
#ifdef _WIN32
    return (long)send(fd, (const char *)data, (int)length, 0);
#else
    return (long)write(fd, data, length);
#endif
}

static long peer_recv(peer_fd fd, unsigned char *data, size_t length) {
#ifdef _WIN32
    return (long)recv(fd, (char *)data, (int)length, 0);
#else
    return (long)read(fd, data, length);
#endif
}

static int peer_wait_readable(peer_fd fd, int milliseconds) {
#ifdef _WIN32
    WSAPOLLFD descriptor;
    descriptor.fd = fd;
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    return WSAPoll(&descriptor, 1, milliseconds) > 0;
#else
    struct pollfd descriptor;
    descriptor.fd = fd;
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    return poll(&descriptor, 1, milliseconds) > 0;
#endif
}

static void peer_close(peer_fd fd) {
#ifdef _WIN32
    closesocket(fd);
#else
    close(fd);
#endif
}

static peer_fd listen_local(int *port) {
    struct sockaddr_in address;
    peer_fd fd;
#ifdef _WIN32
    WSADATA startup_data;
    int length = sizeof(address);
    if (WSAStartup(MAKEWORD(2, 2), &startup_data) != 0) return PEER_INVALID;
#else
    socklen_t length = sizeof(address);
#endif
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd == PEER_INVALID) return PEER_INVALID;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(fd, (struct sockaddr *)&address, (int)sizeof(address)) != 0) return PEER_INVALID;
    if (listen(fd, 4) != 0) return PEER_INVALID;
    if (getsockname(fd, (struct sockaddr *)&address, &length) != 0) return PEER_INVALID;
    *port = (int)ntohs(address.sin_port);
    return fd;
}

static const unsigned char reply_bytes[5] = {1, 2, 3, 4, 5};

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    unsigned char payload[512];
    unsigned char restored[256];
    unsigned char wire[300];
    unsigned char client_bytes[5];
    unsigned char deflated[256];
    peer_fd listener;
    peer_fd server;
    int64_t client;
    int port = 0;
    int deflated_length;
    int64_t first_line;
    int64_t second_line;
    int i;

    for (i = 0; i < 512; i++) payload[i] = (unsigned char)(i / 8);

    /* --- codec ---------------------------------------------------------- */
    check("threshold accepted", mc_set_compression_threshold(2) == 0);
    check("threshold read back", mc_get_compression_threshold() == 2);
    check("reset empty", mc_codec_reset() == 0 && mc_codec_output_length() == 0);
    /* A repeated byte is what the wire codec sees in practice: a palette array
     * of the same id, so the compressed form has to be the shorter one. */
    for (i = 0; i < 200; i++) {
        if (mc_codec_input_byte((int64_t)payload[i]) != 0) {
            check("deflate feed", 0);
            break;
        }
    }
    check("deflate run", mc_codec_run(0, 0) == 0);
    deflated_length = (int)mc_codec_output_length();
    check("deflate shrank", deflated_length > 0 && deflated_length < 200);
    /* reset clears both directions, so keep the compressed form aside. */
    for (i = 0; i < deflated_length; i++) deflated[i] = (unsigned char)mc_codec_output_byte(i);
    mc_codec_reset();
    for (i = 0; i < deflated_length; i++) {
        if (mc_codec_input_byte(deflated[i]) != 0) {
            check("inflate feed", 0);
            break;
        }
    }
    check("inflate run", mc_codec_run(1, 200) == 0);
    check("inflate length", mc_codec_output_length() == 200);
    for (i = 0; i < 200; i++) restored[i] = (unsigned char)mc_codec_output_byte(i);
    check("inflate matches", memcmp(restored, payload, 200) == 0);
    mc_codec_reset();
    mc_codec_input_byte(0xff);
    check("garbage rejected", mc_codec_run(1, 4) != 0);

    /* --- big endian doubles --------------------------------------------- */
    {
        double sample = 123.5;
        int64_t bytes[8];
        for (i = 0; i < 8; i++) bytes[i] = mc_double_be_byte(sample, i);
        check("double round trip", mc_double_from_be(bytes[0], bytes[1], bytes[2], bytes[3],
                                                     bytes[4], bytes[5], bytes[6],
                                                     bytes[7]) == sample);
        check("double index bounds", mc_double_be_byte(sample, 8) == -1);
    }

    /* --- sockets -------------------------------------------------------- */
    listener = listen_local(&port);
    check("listener built", listener != PEER_INVALID);
    client = mc_tcp_connect("127.0.0.1", port);
    check("connect succeeded", client >= 0);
    check("connect reached listener", peer_wait_readable(listener, 3000));
    server = accept(listener, NULL, NULL);
    check("accepted", server != PEER_INVALID);
    mc_tcp_send_begin(client);
    for (i = 0; i < 300; i++) {
        if (mc_tcp_send_byte(payload[i]) != 0) {
            check("send feed", 0);
            break;
        }
    }
    check("send flush", mc_tcp_send_end() == 0);
    {
        long got = 0;
        while (got < 300) {
            long read_now = peer_recv(server, wire + got, (size_t)(300 - got));
            if (read_now <= 0) break;
            got += read_now;
        }
        check("peer received all bytes", got == 300 && memcmp(wire, payload, 300) == 0);
    }
    check("peer wrote reply", peer_send(server, reply_bytes, sizeof(reply_bytes)) == 5);
    check("poll reports socket", (mc_poll_events(client) & 1) != 0);
    for (i = 0; i < 3; i++) {
        client_bytes[i] = (unsigned char)mc_tcp_recv_byte(client);
    }
    /* Three of the five bytes are still buffered, so a poll must report the
     * socket without touching it. */
    check("buffered bytes reported", (mc_poll_events(client) & 1) != 0);
    for (i = 3; i < 5; i++) {
        client_bytes[i] = (unsigned char)mc_tcp_recv_byte(client);
    }
    check("recv bytes match", memcmp(client_bytes, reply_bytes, 5) == 0);
    check("threshold cleared on connect", mc_get_compression_threshold() == -1);
    check("close", mc_tcp_close(client) == 0);
    peer_close(server);
    peer_close(listener);

    /* --- terminal lines -------------------------------------------------- */
    check("prepare stdin", mc_prepare_stdin() == 0);
    first_line = mc_stdin_read_line();
    check("first line length", first_line == 7);
    check("first line bytes", mc_stdin_line_byte(0) == 'h' &&
          mc_stdin_line_byte(6) == 'w' && mc_stdin_line_byte(7) == -1);
    check("first line copy", mc_stdin_line_copy(0) != NULL &&
          strcmp(mc_stdin_line_copy(0), "hello w") == 0);
    check("line done", mc_stdin_line_done() == 0);
    second_line = mc_stdin_read_line();
    check("second line length", second_line == 5);
    check("second line bytes", mc_stdin_line_byte(0) == 'o' &&
          mc_stdin_line_byte(4) == '!');
    check("second line copy", strcmp(mc_stdin_line_copy(1), "orld!") == 0);
    mc_stdin_line_done();
    check("eof gives empty line", mc_stdin_read_line() == 0);
    check("eof line length", mc_stdin_line_length() == 0);
    mc_stdin_line_done();
    check("poll reports closed stdin", (mc_poll_events(-1) & 4) != 0);

    puts("mark: misc");
    /* --- misc ------------------------------------------------------------ */
    check("clock moves", mc_time_millis() > 1700000000000LL);
    check("string length", mc_string_length("abc") == 3);
    {
        unsigned char digest[16];
        for (i = 0; i < 16; i++) digest[i] = (unsigned char)mc_offline_uuid_byte("Notch", i);
        check("uuid version nibble", (digest[6] & 0xf0) == 0x30);
        check("uuid variant nibble", (digest[8] & 0xc0) == 0x80);
        printf("  OfflinePlayer:Notch = %02x%02x%02x%02x-%02x%02x-%02x%02x-"
               "%02x%02x-%02x%02x%02x%02x%02x%02x\n",
               digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
               digest[6], digest[7], digest[8], digest[9], digest[10], digest[11],
               digest[12], digest[13], digest[14], digest[15]);
    }

    if (failures != 0) {
        printf("network smoke: %d failure(s)\n", failures);
        return 1;
    }
    printf("network smoke: all passed\n");
    return 0;
}
