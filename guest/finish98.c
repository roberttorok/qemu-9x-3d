/*
 * FINISH.EXE: the second half of E:\SETUP.BAT (Windows 98 for QEMU + SharedGL).
 *
 * SETUP.BAT copies it to C:\DRIVERS and registers it under RunOnce. Windows then runs it
 * at each start while it is still needed. It waits until the PCI drivers are in, then:
 *   - turns on DMA for both IDE channels (what Device Manager's DMA tick box writes:
 *     IDEDMADRIVE0/1 = 01 in the "Primary/Secondary IDE controller (dual fifo)" driver
 *     keys; their numbers differ between installs, so they are looked up by device ID);
 *   - sets 1024x768 True Color once the QEMU STD VGA driver (vmdisp9x) is installed.
 * Both take effect at the next restart. While either is still missing it registers
 * itself again for the next start. No console window: it is a GUI program.
 */
#include <windows.h>
#include <string.h>

#define CLASS_KEY "System\\CurrentControlSet\\Services\\Class\\"

/* Calls fn(key, subkey name) for each subkey of HKLM\...\Class\<cls> whose
 * MatchingDeviceId equals one of ids[]; returns how many matched. */
static int for_matching(const char *cls, const char *const *ids, int nids,
                        void (*fn)(HKEY))
{
    HKEY root, sub;
    char name[64], id[256];
    DWORD i, len, type;
    int found = 0, k;

    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, cls, 0, KEY_READ, &root) != ERROR_SUCCESS)
        return 0;
    for (i = 0; RegEnumKeyA(root, i, name, sizeof name) == ERROR_SUCCESS; i++) {
        if (RegOpenKeyExA(root, name, 0, KEY_READ | KEY_WRITE, &sub) != ERROR_SUCCESS)
            continue;
        len = sizeof id;
        if (RegQueryValueExA(sub, "MatchingDeviceId", NULL, &type, (BYTE *)id, &len) ==
                ERROR_SUCCESS && type == REG_SZ) {
            for (k = 0; k < nids; k++)
                if (!lstrcmpiA(id, ids[k])) {
                    found++;
                    if (fn)
                        fn(sub);
                    break;
                }
        }
        RegCloseKey(sub);
    }
    RegCloseKey(root);
    return found;
}

static void set_dma(HKEY channel)
{
    BYTE on = 1;
    RegSetValueExA(channel, "IDEDMADRIVE0", 0, REG_BINARY, &on, 1);
    RegSetValueExA(channel, "IDEDMADRIVE1", 0, REG_BINARY, &on, 1);
}

static int set_true_color(void)
{
    HKEY key;
    if (RegCreateKeyA(HKEY_CURRENT_CONFIG, "Display\\Settings", &key) != ERROR_SUCCESS)
        return 0;
    RegSetValueExA(key, "BitsPerPixel", 0, REG_SZ, (const BYTE *)"32", 3);
    RegSetValueExA(key, "Resolution", 0, REG_SZ, (const BYTE *)"1024,768", 9);
    RegCloseKey(key);
    return 1;
}

static void run_again(void)
{
    HKEY key;
    char self[MAX_PATH];
    DWORD n = GetModuleFileNameA(NULL, self, sizeof self);
    if (!n || n >= sizeof self)
        return;
    if (RegCreateKeyA(HKEY_LOCAL_MACHINE,
                      "Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce",
                      &key) == ERROR_SUCCESS) {
        RegSetValueExA(key, "QemuSetup", 0, REG_SZ, (const BYTE *)self, n + 1);
        RegCloseKey(key);
    }
}

int WINAPI WinMain(HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
    static const char *const ide[] = { "MF\\GOODPRIMARY", "MF\\GOODSECONDARY" };
    static const char *const vga[] = { "PCI\\VEN_1234&DEV_1111" };
    int dma, color;

    (void)inst; (void)prev; (void)cmd; (void)show;
    dma = for_matching(CLASS_KEY "hdc", ide, 2, set_dma) > 0;
    color = for_matching(CLASS_KEY "Display", vga, 1, NULL) > 0 && set_true_color();

    if (!dma || !color) {
        run_again();
        return 0;
    }
    if (MessageBoxA(NULL,
                    "Windows 98 is now set up for QEMU: PCI devices, display driver, "
                    "SharedGL device, mouse, DMA and True Color.\n\n"
                    "DMA and True Color start working after a restart. Restart now?",
                    "QEMU setup", MB_YESNO | MB_ICONINFORMATION) == IDYES)
        ExitWindowsEx(EWX_REBOOT, 0);
    return 0;
}
