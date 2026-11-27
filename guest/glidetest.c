/*
 * A small Glide 2 program for testing the whole path: glide2x.dll (OpenGlide),
 * opengl32.dll (SharedGL), the shared memory and the server.
 *
 * It opens a 640x480 Glide screen on its own window and draws, for the given
 * number of seconds:
 *   - a spinning triangle with a red, green and blue corner, on dark brown
 *   - a white square in the top left corner, written through the linear frame
 *     buffer (grLfbLock), which games use for menus and movies
 * Then it prints the frame rate. Press Esc to stop early.
 *
 * Usage: glidetest [seconds]      (default 10)
 * Progress also goes to GLIDETEST.TXT next to the program.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <math.h>

#define FX_GLIDE_NO_FUNC_PROTO
#include "sdk2_glide.h"

static FILE *logfile;

static void say(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\n");
    fflush(stdout);
    if (logfile) {
        va_start(ap, fmt);
        vfprintf(logfile, fmt, ap);
        va_end(ap);
        fprintf(logfile, "\n");
        fflush(logfile);
    }
}

static volatile int quit;

static LRESULT CALLBACK window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_KEYDOWN && wp == VK_ESCAPE)
        quit = 1;
    if (msg == WM_CLOSE || msg == WM_DESTROY) {
        quit = 1;
        return 0;
    }
    return DefWindowProcA(hwnd, msg, wp, lp);
}

#define GET(var, name) do { *(FARPROC*)&var = GetProcAddress(dll, name); \
    if (!var) { say("glide2x.dll has no %s", name); return 2; } } while (0)

int main(int argc, char **argv)
{
    int seconds = argc > 1 ? atoi(argv[1]) : 10;
    char path[MAX_PATH], *slash;
    HMODULE dll;
    HWND hwnd;
    WNDCLASSA wc;
    GrHwConfiguration hw;
    DWORD start, now, frames = 0;
    char version[80] = "";

    void   (__stdcall *pGlideInit)(void);
    void   (__stdcall *pGlideGetVersion)(char *);
    FxBool (__stdcall *pQuery)(GrHwConfiguration *);
    void   (__stdcall *pSelect)(int);
    FxBool (__stdcall *pWinOpen)(FxU32, GrScreenResolution_t, GrScreenRefresh_t, GrColorFormat_t, GrOriginLocation_t, int, int);
    void   (__stdcall *pColorCombine)(GrCombineFunction_t, GrCombineFactor_t, GrCombineLocal_t, GrCombineOther_t, FxBool);
    void   (__stdcall *pClear)(GrColor_t, GrAlpha_t, FxU16);
    void   (__stdcall *pTriangle)(const GrVertex *, const GrVertex *, const GrVertex *);
    void   (__stdcall *pSwap)(int);
    FxBool (__stdcall *pLfbLock)(GrLock_t, GrBuffer_t, GrLfbWriteMode_t, GrOriginLocation_t, FxBool, GrLfbInfo_t *);
    FxBool (__stdcall *pLfbUnlock)(GrLock_t, GrBuffer_t);
    void   (__stdcall *pWinClose)(void);
    void   (__stdcall *pShutdown)(void);

    GetModuleFileNameA(NULL, path, sizeof(path));
    slash = strrchr(path, '\\');
    strcpy(slash ? slash + 1 : path, "GLIDETEST.TXT");
    logfile = fopen(path, "w");

    dll = LoadLibraryA("glide2x.dll");
    if (!dll) {
        say("cannot load glide2x.dll, error %lu. Is opengl32.dll next to it?", GetLastError());
        return 2;
    }
    GetModuleFileNameA(dll, path, sizeof(path));
    say("loaded %s", path);

    GET(pGlideInit, "_grGlideInit@0");
    GET(pGlideGetVersion, "_grGlideGetVersion@4");
    GET(pQuery, "_grSstQueryHardware@4");
    GET(pSelect, "_grSstSelect@4");
    GET(pWinOpen, "_grSstWinOpen@28");
    GET(pColorCombine, "_grColorCombine@20");
    GET(pClear, "_grBufferClear@12");
    GET(pTriangle, "_grDrawTriangle@12");
    GET(pSwap, "_grBufferSwap@4");
    GET(pLfbLock, "_grLfbLock@24");
    GET(pLfbUnlock, "_grLfbUnlock@8");
    GET(pWinClose, "_grSstWinClose@0");
    GET(pShutdown, "_grGlideShutdown@0");

    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc = window_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = "glidetest";
    RegisterClassA(&wc);
    hwnd = CreateWindowExA(WS_EX_TOPMOST, "glidetest", "glidetest", WS_POPUP | WS_VISIBLE,
                           0, 0, 640, 480, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) {
        say("cannot create a window, error %lu", GetLastError());
        return 2;
    }
    SetForegroundWindow(hwnd);

    pGlideInit();
    pGlideGetVersion(version);
    say("grGlideGetVersion: %s", version);
    memset(&hw, 0, sizeof(hw));
    {
        /* called first: the arguments of say() may be evaluated in any order */
        FxBool found = pQuery(&hw);
        say("grSstQueryHardware: %d, %d board(s), type %d", found, hw.num_sst, hw.SSTs[0].type);
    }
    pSelect(0);

    if (!pWinOpen((FxU32)hwnd, GR_RESOLUTION_640x480, GR_REFRESH_60Hz, GR_COLORFORMAT_ARGB,
                  GR_ORIGIN_UPPER_LEFT, 2, 1)) {
        say("grSstWinOpen FAILED");
        return 3;
    }
    say("grSstWinOpen OK");

    pColorCombine(GR_COMBINE_FUNCTION_LOCAL, GR_COMBINE_FACTOR_NONE, GR_COMBINE_LOCAL_ITERATED,
                  GR_COMBINE_OTHER_NONE, FXFALSE);

    start = GetTickCount();
    while (!quit) {
        GrVertex v[3];
        GrLfbInfo_t info;
        MSG msg;
        float angle;
        int i;

        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
            DispatchMessageA(&msg);
        now = GetTickCount();
        if (now - start >= (DWORD)seconds * 1000u)
            break;

        angle = (now - start) * 0.002f;
        memset(v, 0, sizeof(v));
        for (i = 0; i < 3; i++) {
            float a = angle + i * 2.0944f;
            v[i].x = 320 + 200 * (float)cos(a);
            v[i].y = 240 + 200 * (float)sin(a);
            v[i].ooz = 65535.f;
            v[i].oow = 1.f;
            v[i].r = i == 0 ? 255.f : 0;
            v[i].g = i == 1 ? 255.f : 0;
            v[i].b = i == 2 ? 255.f : 0;
            v[i].a = 255.f;
        }
        pClear(0x00201008, 0, 0xFFFF); /* ARGB: dark brown */
        pTriangle(&v[0], &v[1], &v[2]);

        info.size = sizeof(info);
        if (pLfbLock(GR_LFB_WRITE_ONLY, GR_BUFFER_BACKBUFFER, GR_LFBWRITEMODE_565, GR_ORIGIN_UPPER_LEFT, FXFALSE, &info)) {
            int x, y;
            for (y = 16; y < 80; y++) {
                FxU16 *row = (FxU16 *)((char *)info.lfbPtr + y * info.strideInBytes);
                for (x = 16; x < 80; x++)
                    row[x] = 0xFFFF;
            }
            pLfbUnlock(GR_LFB_WRITE_ONLY, GR_BUFFER_BACKBUFFER);
        }

        pSwap(1);
        frames++;
    }
    now = GetTickCount();

    pWinClose();
    pShutdown();
    DestroyWindow(hwnd);
    say("%lu frames in %.1f s: %.1f fps", frames, (now - start) / 1000.0,
        now > start ? frames * 1000.0 / (now - start) : 0.0);
    if (logfile)
        fclose(logfile);
    return 0;
}
