/*
 * Checks, step by step, the path from a Windows 98 client to the server's shared
 * memory: the sgl98.sys driver, its view of the PCI device, the mapping, and the
 * registers the server publishes. Each line says what it found.
 */
#include <windows.h>
#include <stdio.h>

#define IOSIZE   CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOMAP    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOSTATUS CTL_CODE(FILE_DEVICE_UNKNOWN, 0x820, METHOD_BUFFERED, FILE_ANY_ACCESS)

struct m { WORD peer; DWORD64 size; PVOID ptr; WORD vec; };

/* matches SGL98_STATUS in kernel/win98/sgl98.c */
struct sgl98_status {
    DWORD version, started, lower_start, descriptors, memory_start, memory_length;
    DWORD mapped, pages_made_user, pdes_made_user, large_pages, maps;
};

int main(void)
{
    struct sgl98_status st;
    struct m map;
    DWORD64 size = 0;
    DWORD got = 0;
    BYTE mode = 1;
    HANDLE h;
    volatile char *p;

    h = CreateFileA("\\\\.\\SGL98", 0, 0, NULL, OPEN_EXISTING, 0, 0);
    if (h == INVALID_HANDLE_VALUE) {
        printf("open \\\\.\\SGL98 FAILED, error %lu\n", GetLastError());
        printf("The driver isn't loaded. In Device Manager, the SharedGL shared memory\n"
               "device should be under System devices, without a yellow mark.\n");
        return 1;
    }
    printf("open \\\\.\\SGL98 OK\n");

    memset(&st, 0, sizeof(st));
    if (DeviceIoControl(h, IOSTATUS, NULL, 0, &st, sizeof(st), &got, NULL))
        printf("driver v%lu: started %lu, bus start %08lx, %lu resources, BAR %08lx + %lu KiB, mapped at %08lx\n",
               st.version, st.started, st.lower_start, st.descriptors, st.memory_start,
               st.memory_length >> 10, st.mapped);
    else
        printf("status FAILED, error %lu\n", GetLastError());

    if (!DeviceIoControl(h, IOSIZE, NULL, 0, &size, 8, &got, NULL)) {
        printf("size FAILED, error %lu (device not started: see above)\n", GetLastError());
        return 1;
    }
    printf("size %lu MiB\n", (unsigned long)(size >> 20));

    if (!DeviceIoControl(h, IOMAP, &mode, 1, &map, sizeof(map), &got, NULL)) {
        printf("map FAILED, error %lu\n", GetLastError());
        return 1;
    }
    if (DeviceIoControl(h, IOSTATUS, NULL, 0, &st, sizeof(st), &got, NULL))
        printf("mapped at %p; made user-accessible: %lu pages, %lu directory entries (%lu large)\n",
               map.ptr, st.pages_made_user, st.pdes_made_user, st.large_pages);

    if (IsBadReadPtr(map.ptr, 4096) || IsBadWritePtr(map.ptr, 4096)) {
        printf("the mapping is NOT reachable from applications\n");
        return 1;
    }
    p = map.ptr;
    printf("registers: memsize %lu MiB, fifo %d KiB, gl %d.%d, max_clients %d\n",
           *(volatile DWORD*)(p + 32) >> 20, *(volatile int*)(p + 64) >> 10,
           *(volatile int*)(p + 44), *(volatile int*)(p + 48), *(volatile int*)(p + 68));
    if (*(volatile DWORD*)(p + 32) == 0)
        printf("The server isn't running: start the VM with windows/run-98.sh\n");
    else
        printf("gl %d.%d\n", *(volatile int*)(p + 44), *(volatile int*)(p + 48));
    return 0;
}
