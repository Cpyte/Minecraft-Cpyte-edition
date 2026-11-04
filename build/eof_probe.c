#include <stdio.h>
#include <stdint.h>

int64_t mc_prepare_stdin(void);
int64_t mc_stdin_read_line(void);
int64_t mc_stdin_line_length(void);
int64_t mc_stdin_line_byte(int64_t index);
int64_t mc_stdin_line_done(void);
int64_t mc_poll_events(int64_t socket_handle);

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("prepare=%lld\n", (long long)mc_prepare_stdin());
    for (int i = 0; i < 4; i++) {
        printf("--> read %d\n", i);
        fflush(stderr);
        long long n = (long long)mc_stdin_read_line();
        printf("<-- read %d = %lld\n", i, n);
        for (long long b = 0; b < n; b++) putchar((int)mc_stdin_line_byte(b));
        putchar('\n');
        printf("    done=%lld\n", (long long)mc_stdin_line_done());
    }
    printf("poll=%lld\n", (long long)mc_poll_events(-1));
    return 0;
}
