/*
 * CLOCKTST.EXE: checks whether Windows 98's clock keeps real time inside the VM.
 *
 *   CLOCKTST MHZ [SECONDS]      e.g. CLOCKTST 3700 600
 *
 * MHZ is the host CPU's time-stamp counter rate (the frame profile's tsc_mhz; under
 * WHPX the guest's TSC runs at the host's rate). Every real second, measured with the
 * TSC, it writes how many milliseconds Windows' timer (timeGetTime) advanced. 1000 is
 * right; less means timer interrupts were lost, and games that time themselves with it
 * run in slow motion for that second. Runs in the background next to a game, writing to
 * CLOCKTST.TXT next to the program.
 */
#include <windows.h>
#include <mmsystem.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned long long rdtsc(void)
{
    unsigned int lo, hi;
    __asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
    return ((unsigned long long)hi << 32) | lo;
}

int main(int argc, char **argv)
{
    double mhz = argc > 1 ? atof(argv[1]) : 0;
    int seconds = argc > 2 ? atoi(argv[2]) : 300;
    char path[MAX_PATH], *slash;
    unsigned long long ticks_per_second, start, next;
    DWORD last_tgt;
    FILE *out;
    int i, low = 0;

    if (mhz <= 0) {
        printf("Usage: CLOCKTST MHZ [SECONDS]   (MHZ = host TSC rate, e.g. 3700)\n");
        return 1;
    }
    GetModuleFileNameA(NULL, path, sizeof(path));
    slash = strrchr(path, '\\');
    strcpy(slash ? slash + 1 : path, "CLOCKTST.TXT");
    out = fopen(path, "w");
    if (!out)
        return 2;

    timeBeginPeriod(1);
    ticks_per_second = (unsigned long long)(mhz * 1e6);
    start = rdtsc();
    next = start + ticks_per_second;
    last_tgt = timeGetTime();
    fprintf(out, "second  timeGetTime_ms_per_real_second\n");
    fflush(out);

    for (i = 1; i <= seconds; i++) {
        DWORD now_tgt;
        while (rdtsc() < next)
            Sleep(10);
        now_tgt = timeGetTime();
        fprintf(out, "%4d  %5lu%s\n", i, now_tgt - last_tgt, now_tgt - last_tgt < 950 ? "  SLOW" : "");
        fflush(out);
        if (now_tgt - last_tgt < 950)
            low++;
        last_tgt = now_tgt;
        next += ticks_per_second;
    }
    fprintf(out, "%d of %d seconds below 950 ms\n", low, seconds);
    fclose(out);
    timeEndPeriod(1);
    return 0;
}
