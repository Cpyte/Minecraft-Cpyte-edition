#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <process.h>
static CRITICAL_SECTION cs;
static CONDITION_VARIABLE cv;
static int flag = 0;
static unsigned __stdcall producer(void *a) {
    (void)a;
    Sleep(200);
    EnterCriticalSection(&cs);
    flag = 1;
    WakeAllConditionVariable(&cv);
    LeaveCriticalSection(&cs);
    return 0;
}
int main(void) {
    DWORD start;
    InitializeCriticalSection(&cs);
    InitializeConditionVariable(&cv);
    _beginthreadex(NULL, 0, producer, NULL, 0, NULL);
    EnterCriticalSection(&cs);
    start = GetTickCount();
    while (!flag) SleepConditionVariableCS(&cv, &cs, 5000);
    printf("flag=%d waited=%lu ms\n", flag, GetTickCount() - start);
    LeaveCriticalSection(&cs);
    return 0;
}
