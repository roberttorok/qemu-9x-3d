/*
 * A small Glide 3 program for testing glide3x.dll (OpenGlide's Glide 3 layer).
 *
 * It opens a 640x480 Glide screen and draws a still picture, one test per
 * quarter, on dark brown:
 *   top left      a triangle, red, green and blue corners: packed ARGB colours
 *                 (GR_PARAM_PARGB), grDrawTriangle
 *   top right     a strip of three quads fading green to blue: float RGB,
 *                 grDrawVertexArrayContiguous(GR_TRIANGLE_STRIP)
 *   bottom left   a black and white checkerboard, 8x8 squares: a 64x64 texture
 *                 (log2 LODs, grTexDownloadMipMap, grTexSource), drawn as a fan
 *                 through grDrawVertexArray (pointers)
 *   bottom right  a yellow triangle in clip coordinates (grCoordinateSpace,
 *                 grViewport set to this quarter, w = 2)
 * It logs what grGet, grGetString and grQueryResolutions return.
 *
 * Usage: glide3ts [seconds]      (default 10). Esc stops early.
 * Progress also goes to GLIDE3TS.TXT next to the program.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

typedef unsigned int FxU32;
typedef int FxI32;
typedef int FxBool;
typedef unsigned short FxU16;

/* Glide 3 (glide.h) values used here */
#define GR_RESOLUTION_640x480 7
#define GR_REFRESH_60Hz       0
#define GR_COLORFORMAT_ARGB   0
#define GR_ORIGIN_UPPER_LEFT  0
#define GR_PARAM_XY     0x01
#define GR_PARAM_Z      0x02
#define GR_PARAM_W      0x03
#define GR_PARAM_Q      0x04
#define GR_PARAM_A      0x10
#define GR_PARAM_RGB    0x20
#define GR_PARAM_PARGB  0x30
#define GR_PARAM_ST0    0x40
#define GR_PARAM_DISABLE 0
#define GR_PARAM_ENABLE  1
#define GR_TRIANGLE_STRIP 4
#define GR_TRIANGLE_FAN   5
#define GR_WINDOW_COORDS 0
#define GR_CLIP_COORDS   1
#define GR_COMBINE_FUNCTION_LOCAL       1
#define GR_COMBINE_FUNCTION_SCALE_OTHER 3
#define GR_COMBINE_FACTOR_NONE  0
#define GR_COMBINE_FACTOR_ONE   8
#define GR_COMBINE_LOCAL_ITERATED 0
#define GR_COMBINE_LOCAL_NONE     1
#define GR_COMBINE_OTHER_ITERATED 0
#define GR_COMBINE_OTHER_TEXTURE  1
#define GR_COMBINE_OTHER_NONE     2
#define GR_TMU0 0
#define GR_LOD_LOG2_64  6
#define GR_ASPECT_LOG2_1x1 0
#define GR_TEXFMT_RGB_565 0xa
#define GR_MIPMAPLEVELMASK_BOTH 3
#define GR_TEXTUREFILTER_POINT_SAMPLED 0
#define GR_TEXTURECLAMP_WRAP 0
#define GR_MIPMAP_DISABLE 0
#define GR_NUM_TMU        0x13
#define GR_MEMORY_TMU     0x0d
#define GR_MAX_TEXTURE_SIZE 0x0a
#define GR_GLIDE_STATE_SIZE 0x06
#define GR_HARDWARE 0xa1
#define GR_VERSION  0xa4
#define GR_QUERY_ANY -1

typedef struct { FxI32 smallLodLog2, largeLodLog2, aspectRatioLog2, format; void *data; } GrTexInfo;
typedef struct { FxI32 resolution, refresh, numColorBuffers, numAuxBuffers; } GrResolution;

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
    if (!var) { say("glide3x.dll has no %s", name); return 2; } } while (0)

/* vertex layouts */
typedef struct { float x, y; FxU32 argb; } PVertex;                 /* window, packed colour */
typedef struct { float x, y; float r, g, b; } CVertex;             /* window, float colour */
typedef struct { float x, y, q, s, t; } TVertex;                   /* window, textured */
typedef struct { float x, y, z, w; float r, g, b; } KVertex;       /* clip coordinates */

int main(int argc, char **argv)
{
    int seconds = argc > 1 ? atoi(argv[1]) : 10;
    char path[MAX_PATH], *slash;
    HMODULE dll;
    HWND hwnd;
    WNDCLASSA wc;
    DWORD start;
    FxU32 ctx, tex_addr;
    static FxU16 texels[64 * 64];
    GrTexInfo ti;
    FxI32 v;
    int x, y;

    void   (__stdcall *pGlideInit)(void);
    void   (__stdcall *pSelect)(int);
    FxU32  (__stdcall *pGet)(FxU32, FxU32, FxI32 *);
    const char *(__stdcall *pGetString)(FxU32);
    FxI32  (__stdcall *pQueryRes)(const GrResolution *, GrResolution *);
    FxU32  (__stdcall *pWinOpen)(FxU32, FxI32, FxI32, FxI32, FxI32, int, int);
    void   (__stdcall *pVertexLayout)(FxU32, FxI32, FxU32);
    void   (__stdcall *pCoordSpace)(FxU32);
    void   (__stdcall *pViewport)(FxI32, FxI32, FxI32, FxI32);
    void   (__stdcall *pDepthRange)(float, float);
    void   (__stdcall *pColorCombine)(FxI32, FxI32, FxI32, FxI32, FxBool);
    void   (__stdcall *pTexCombine)(FxI32, FxI32, FxI32, FxI32, FxI32, FxBool, FxBool);
    FxU32  (__stdcall *pTexMinAddress)(FxI32);
    FxU32  (__stdcall *pTexMemRequired)(FxU32, GrTexInfo *);
    void   (__stdcall *pTexDownload)(FxI32, FxU32, FxU32, GrTexInfo *);
    void   (__stdcall *pTexSource)(FxI32, FxU32, FxU32, GrTexInfo *);
    void   (__stdcall *pTexFilter)(FxI32, FxI32, FxI32);
    void   (__stdcall *pTexClamp)(FxI32, FxI32, FxI32);
    void   (__stdcall *pTexMipMap)(FxI32, FxI32, FxBool);
    void   (__stdcall *pClear)(FxU32, FxU32, FxU32);
    void   (__stdcall *pTriangle)(const void *, const void *, const void *);
    void   (__stdcall *pArrayContig)(FxU32, FxU32, void *, FxU32);
    void   (__stdcall *pArray)(FxU32, FxU32, void *);
    void   (__stdcall *pSwap)(FxU32);
    FxBool (__stdcall *pWinClose)(FxU32);
    void   (__stdcall *pShutdown)(void);

    GetModuleFileNameA(NULL, path, sizeof(path));
    slash = strrchr(path, '\\');
    strcpy(slash ? slash + 1 : path, "GLIDE3TS.TXT");
    logfile = fopen(path, "w");

    dll = LoadLibraryA("glide3x.dll");
    if (!dll) {
        say("cannot load glide3x.dll, error %lu. Is opengl32.dll next to it?", GetLastError());
        return 2;
    }
    GetModuleFileNameA(dll, path, sizeof(path));
    say("loaded %s", path);

    GET(pGlideInit, "_grGlideInit@0");
    GET(pSelect, "_grSstSelect@4");
    GET(pGet, "_grGet@12");
    GET(pGetString, "_grGetString@4");
    GET(pQueryRes, "_grQueryResolutions@8");
    GET(pWinOpen, "_grSstWinOpen@28");
    GET(pVertexLayout, "_grVertexLayout@12");
    GET(pCoordSpace, "_grCoordinateSpace@4");
    GET(pViewport, "_grViewport@16");
    GET(pDepthRange, "_grDepthRange@8");
    GET(pColorCombine, "_grColorCombine@20");
    GET(pTexCombine, "_grTexCombine@28");
    GET(pTexMinAddress, "_grTexMinAddress@4");
    GET(pTexMemRequired, "_grTexTextureMemRequired@8");
    GET(pTexDownload, "_grTexDownloadMipMap@16");
    GET(pTexSource, "_grTexSource@16");
    GET(pTexFilter, "_grTexFilterMode@12");
    GET(pTexClamp, "_grTexClampMode@12");
    GET(pTexMipMap, "_grTexMipMapMode@12");
    GET(pClear, "_grBufferClear@12");
    GET(pTriangle, "_grDrawTriangle@12");
    GET(pArrayContig, "_grDrawVertexArrayContiguous@16");
    GET(pArray, "_grDrawVertexArray@12");
    GET(pSwap, "_grBufferSwap@4");
    GET(pWinClose, "_grSstWinClose@4");
    GET(pShutdown, "_grGlideShutdown@0");

    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc = window_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = "glide3test";
    RegisterClassA(&wc);
    hwnd = CreateWindowExA(WS_EX_TOPMOST, "glide3test", "glide3test", WS_POPUP | WS_VISIBLE,
                           0, 0, 640, 480, NULL, NULL, wc.hInstance, NULL);
    if (!hwnd) {
        say("cannot create a window, error %lu", GetLastError());
        return 2;
    }
    SetForegroundWindow(hwnd);

    pGlideInit();
    say("grGetString: hardware %s, version %s", pGetString(GR_HARDWARE), pGetString(GR_VERSION));
    v = 0; pGet(GR_NUM_TMU, 4, &v);           say("grGet NUM_TMU %ld", (long)v);
    v = 0; pGet(GR_MEMORY_TMU, 4, &v);        say("grGet MEMORY_TMU %ld", (long)v);
    v = 0; pGet(GR_MAX_TEXTURE_SIZE, 4, &v);  say("grGet MAX_TEXTURE_SIZE %ld", (long)v);
    v = 0; pGet(GR_GLIDE_STATE_SIZE, 4, &v);  say("grGet GLIDE_STATE_SIZE %ld", (long)v);
    {
        GrResolution any = { GR_QUERY_ANY, GR_QUERY_ANY, GR_QUERY_ANY, GR_QUERY_ANY };
        say("grQueryResolutions: %ld modes", (long)(pQueryRes(&any, NULL) / sizeof(GrResolution)));
    }
    pSelect(0);

    ctx = pWinOpen((FxU32)hwnd, GR_RESOLUTION_640x480, GR_REFRESH_60Hz, GR_COLORFORMAT_ARGB,
                   GR_ORIGIN_UPPER_LEFT, 2, 1);
    if (!ctx) {
        say("grSstWinOpen FAILED");
        return 3;
    }
    say("grSstWinOpen OK, context %lu", (unsigned long)ctx);

    /* the checkerboard: 8x8 texel squares, white and black */
    for (y = 0; y < 64; y++)
        for (x = 0; x < 64; x++)
            texels[y * 64 + x] = ((x / 8) ^ (y / 8)) & 1 ? 0x0000 : 0xFFFF;
    ti.smallLodLog2 = ti.largeLodLog2 = GR_LOD_LOG2_64;
    ti.aspectRatioLog2 = GR_ASPECT_LOG2_1x1;
    ti.format = GR_TEXFMT_RGB_565;
    ti.data = texels;
    tex_addr = pTexMinAddress(GR_TMU0);
    say("texture: %lu bytes at %lu", (unsigned long)pTexMemRequired(GR_MIPMAPLEVELMASK_BOTH, &ti),
        (unsigned long)tex_addr);
    pTexDownload(GR_TMU0, tex_addr, GR_MIPMAPLEVELMASK_BOTH, &ti);
    pTexFilter(GR_TMU0, GR_TEXTUREFILTER_POINT_SAMPLED, GR_TEXTUREFILTER_POINT_SAMPLED);
    pTexClamp(GR_TMU0, GR_TEXTURECLAMP_WRAP, GR_TEXTURECLAMP_WRAP);
    pTexMipMap(GR_TMU0, GR_MIPMAP_DISABLE, FALSE);

    int first = 1;
#define STEP(name) do { if (first) say("frame 1: %s", name); } while (0)
    start = GetTickCount();
    while (!quit && GetTickCount() - start < (DWORD)seconds * 1000u) {
        MSG msg;
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
            DispatchMessageA(&msg);

        STEP("clear");
        pClear(0x00201008, 0, 0xFFFF);
        pCoordSpace(GR_WINDOW_COORDS);

        /* top left: packed colour */
        {
            PVertex p[3] = { { 160, 20, 0xFFFF0000 }, { 290, 220, 0xFF00FF00 }, { 30, 220, 0xFF0000FF } };
            pVertexLayout(GR_PARAM_RGB, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_ST0, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_Q, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_Z, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_W, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_XY, 0, GR_PARAM_ENABLE);
            pVertexLayout(GR_PARAM_PARGB, 8, GR_PARAM_ENABLE);
            pColorCombine(GR_COMBINE_FUNCTION_LOCAL, GR_COMBINE_FACTOR_NONE, GR_COMBINE_LOCAL_ITERATED,
                          GR_COMBINE_OTHER_NONE, FALSE);
            STEP("packed triangle");
            pTriangle(&p[0], &p[1], &p[2]);
        }

        /* top right: a strip of float-colour vertices */
        {
            CVertex c[8];
            int i;
            for (i = 0; i < 8; i++) {
                c[i].x = 340 + (i / 2) * 90.0f;
                c[i].y = i & 1 ? 220.0f : 20.0f;
                c[i].r = 0;
                c[i].g = 255.0f - (i / 2) * 85.0f;
                c[i].b = (i / 2) * 85.0f;
            }
            pVertexLayout(GR_PARAM_PARGB, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_RGB, 8, GR_PARAM_ENABLE);
            STEP("strip");
            pArrayContig(GR_TRIANGLE_STRIP, 8, c, sizeof(CVertex));
        }

        /* bottom left: textured fan, the 64x64 texture repeated 2x2 */
        {
            TVertex t[4] = { { 30, 260, 1, 0, 0 }, { 290, 260, 1, 512, 0 },
                             { 290, 460, 1, 512, 512 }, { 30, 460, 1, 0, 512 } };
            /* window coordinates: s and t in texels of a 256-texel texture, as in Glide 2 */
            void *list[4] = { &t[0], &t[1], &t[2], &t[3] };
            pVertexLayout(GR_PARAM_RGB, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_Q, 8, GR_PARAM_ENABLE);
            pVertexLayout(GR_PARAM_ST0, 12, GR_PARAM_ENABLE);
            STEP("texture source");
            pTexSource(GR_TMU0, tex_addr, GR_MIPMAPLEVELMASK_BOTH, &ti);
            pTexCombine(GR_TMU0, GR_COMBINE_FUNCTION_LOCAL, GR_COMBINE_FACTOR_NONE,
                        GR_COMBINE_FUNCTION_LOCAL, GR_COMBINE_FACTOR_NONE, FALSE, FALSE);
            pColorCombine(GR_COMBINE_FUNCTION_SCALE_OTHER, GR_COMBINE_FACTOR_ONE, GR_COMBINE_LOCAL_NONE,
                          GR_COMBINE_OTHER_TEXTURE, FALSE);
            STEP("textured fan");
            pArray(GR_TRIANGLE_FAN, 4, list);
        }

        /* bottom right: clip coordinates, viewport = that quarter */
        {
            /* x, y in -1..1 times w; colour 0..1 */
            KVertex k[3] = { { 0.0f, -1.6f, 0, 2, 1, 1, 0 }, { 1.6f, 1.6f, 0, 2, 1, 1, 0 },
                             { -1.6f, 1.6f, 0, 2, 1, 1, 0 } };
            pVertexLayout(GR_PARAM_Q, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_ST0, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_Z, 8, GR_PARAM_ENABLE);
            pVertexLayout(GR_PARAM_W, 12, GR_PARAM_ENABLE);
            pVertexLayout(GR_PARAM_RGB, 16, GR_PARAM_ENABLE);
            pColorCombine(GR_COMBINE_FUNCTION_LOCAL, GR_COMBINE_FACTOR_NONE, GR_COMBINE_LOCAL_ITERATED,
                          GR_COMBINE_OTHER_NONE, FALSE);
            STEP("clip coords");
            pCoordSpace(GR_CLIP_COORDS);
            pViewport(320, 240, 320, 240);
            pDepthRange(0.0f, 1.0f);
            STEP("clip triangle");
            pTriangle(&k[0], &k[1], &k[2]);
            pVertexLayout(GR_PARAM_Z, 0, GR_PARAM_DISABLE);
            pVertexLayout(GR_PARAM_W, 0, GR_PARAM_DISABLE);
        }

        STEP("swap");
        pSwap(1);
        STEP("frame done");
        first = 0;
    }

    pWinClose(ctx);
    pShutdown();
    DestroyWindow(hwnd);
    say("done");
    if (logfile)
        fclose(logfile);
    return 0;
}
