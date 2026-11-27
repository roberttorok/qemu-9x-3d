/*
 * INSTALL.EXE: copies the 3D files next to a game's .exe, inside Windows 98.
 *
 *   E:\INSTALL "C:\Program Files\My Game"
 *   E:\INSTALL /TEST      the same into C:\SGLTEST, with the test programs
 *
 * Copies glide2x.dll and glide3x.dll (Glide 2 and 3, translated to OpenGL by
 * OpenGlide) and opengl32.dll (SharedGL, which sends OpenGL to the host). A copy
 * of one of them the game already has is kept once as glide2x.sgb, glide3x.sgb
 * or opengl32.sgb. It refuses the
 * Windows folders: these files must never go there.
 *
 * A batch file can't do this on Windows 98: COMMAND.COM has no %~dp0, and copy
 * can't report errors to it.
 */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* the first GAME_FILES go into games; /TEST also copies the rest */
static const char *files[] = { "glide2x.dll", "glide3x.dll", "opengl32.dll", "GLIDETST.EXE", "GLIDE3TS.EXE", "SGLGEARS.EXE" };
/* text that only our build of each file contains; NULL: never back up */
static const char *markers[] = { "OpenGLide", "OpenGLide", "SharedGL", NULL, NULL, NULL };
#define GAME_FILES 3

/* Whether the file contains the text: tells our DLLs from a game's own. */
static int file_contains(const char *path, const char *text)
{
    HANDLE h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    DWORD size, got = 0, i;
    size_t length = strlen(text);
    char *data;
    int found = 0;

    if (h == INVALID_HANDLE_VALUE)
        return 0;
    size = GetFileSize(h, NULL);
    data = size != 0xFFFFFFFF && size < 16u << 20 ? malloc(size) : NULL;
    if (data && ReadFile(h, data, size, &got, NULL) && got == size)
        for (i = 0; !found && i + length <= size; i++)
            found = memcmp(data + i, text, length) == 0;
    free(data);
    CloseHandle(h);
    return found;
}

static int same_folder(const char *a, const char *b)
{
    char fa[MAX_PATH], fb[MAX_PATH];
    if (!GetFullPathNameA(a, sizeof(fa), fa, NULL) || !GetFullPathNameA(b, sizeof(fb), fb, NULL))
        return 0;
    while (strlen(fa) > 3 && fa[strlen(fa) - 1] == '\\') fa[strlen(fa) - 1] = 0;
    while (strlen(fb) > 3 && fb[strlen(fb) - 1] == '\\') fb[strlen(fb) - 1] = 0;
    return lstrcmpiA(fa, fb) == 0;
}

int main(int argc, char **argv)
{
    char here[MAX_PATH], windir[MAX_PATH], sysdir[MAX_PATH], target[MAX_PATH], *slash;
    DWORD attributes;
    size_t i, count = GAME_FILES;

    if (argc != 2) {
        printf("Usage: INSTALL \"C:\\Game Folder\"\n");
        printf("       INSTALL /TEST    copies the test programs to C:\\SGLTEST\n");
        return 1;
    }
    if (lstrcmpiA(argv[1], "/test") == 0) {
        strcpy(target, "C:\\SGLTEST");
        CreateDirectoryA(target, NULL);
        count = sizeof(files) / sizeof(files[0]);
    }
    else
        strcpy(target, argv[1]);
    while (strlen(target) > 3 && target[strlen(target) - 1] == '\\')
        target[strlen(target) - 1] = 0;

    attributes = GetFileAttributesA(target);
    if (attributes == 0xFFFFFFFF || !(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        printf("The folder %s does not exist.\n", target);
        return 1;
    }
    GetWindowsDirectoryA(windir, sizeof(windir));
    GetSystemDirectoryA(sysdir, sizeof(sysdir));
    if (same_folder(target, windir) || same_folder(target, sysdir)) {
        printf("Never copy these files into %s. Use the game's own folder.\n", target);
        return 1;
    }

    GetModuleFileNameA(NULL, here, sizeof(here));
    slash = strrchr(here, '\\');
    if (!slash)
        return 2;

    for (i = 0; i < count; i++) {
        char from[MAX_PATH], to[MAX_PATH], backup[MAX_PATH];
        strcpy(slash + 1, files[i]);
        strcpy(from, here);
        sprintf(to, "%s\\%s", target, files[i]);
        sprintf(backup, "%s\\%.*s.sgb", target, (int)(strlen(files[i]) - 4), files[i]);

        /* keep the game's own copy once, but never one of ours (an older build, say) */
        if (markers[i] && GetFileAttributesA(to) != 0xFFFFFFFF && GetFileAttributesA(backup) == 0xFFFFFFFF &&
            !file_contains(to, markers[i]) && CopyFileA(to, backup, TRUE))
            printf("Kept the game's %s as %s\n", files[i], backup);

        SetFileAttributesA(to, FILE_ATTRIBUTE_NORMAL);
        if (!CopyFileA(from, to, FALSE)) {
            printf("FAILED to copy %s to %s, error %lu. Is the game still running?\n", files[i], target, GetLastError());
            return 1;
        }
        /* files from a CD are read-only */
        SetFileAttributesA(to, FILE_ATTRIBUTE_NORMAL);
    }

    printf("Installed in %s\n", target);
    return 0;
}
