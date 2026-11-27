# @RELEASE@ @VERSION@, prebuilt for Windows 10/11 x64

3dfx Voodoo (Glide) and OpenGL games in a **Windows 98 SE** VM under QEMU, drawn by your GPU. This ZIP has
everything built: QEMU with our patches, the SharedGL server, and `guest.iso` with the Windows 98 drivers. Nothing
to install apart from one Windows feature. You bring the Windows 98 SE CD and its product key.

Hobby project, no warranty. Keep backups of your VM disk.

## 1. Before you start

1. **Hypervisor:** Win+R `optionalfeatures` → tick **Windows Hypervisor Platform** → OK → restart.
   (QEMU uses it as its accelerator, WHPX. It can live next to Hyper-V, WSL2 and VirtualBox 6+.)
2. **Folder:** unpack this ZIP to a short path without spaces or commas, e.g. `D:\98`.
3. **Files**, into that folder: your Windows 98 SE CD image as `Win98CD.iso`, and the patcher9x boot floppy
   [patcher9x-0.9.91-boot.ima](https://github.com/JHRobotics/patcher9x/releases/download/v0.9.91/patcher9x-0.9.91-boot.ima)
   (lets Windows 98 install on modern CPUs, used in step 3.1).

Every command below runs in a Command Prompt (Win+R `cmd`) in that folder (`cd /d D:\98`).

## 2. Run the VM

```bat
vm.bat create               & rem an empty 8 GB disk, win98.qcow2; never overwrites an existing one
vm.bat start Win98CD.iso    & rem any CD image, or none
```

The CD image you pass is D: in Windows 98, our `guest.iso` is E:. `vm.bat start` keeps running while the VM
runs: leave its window open (closing it kills the VM). The VM ends when Windows 98 shuts down or you close the VM
window. `vm.bat stop` (in another Command Prompt) kills a stuck VM; `vm.bat status` shows whether it runs.

## 3. Install Windows 98 SE

Until step 3.2 the mouse may not work: use the keyboard (Tab, arrows, Enter, Alt+letter, Win+R for Run).

Start the VM with `Win98CD.iso` (step 2). Boot from CD-ROM → Start Windows 98 Setup from CD-ROM. Let it partition
(large disk support) and format. The DOS file copy is slow; that's normal. Continue until Setup restarts the PC the
first time.

### 3.1 patcher9x (at Setup's first restart)

Close the VM window as the PC restarts, then start the VM with the patcher9x floppy in A: and a boot menu:

```bat
set "QEMU_EXTRA=-boot menu=on,splash-time=6000 -drive if=floppy,format=raw,file=patcher9x-0.9.91-boot.ima"
vm.bat start Win98CD.iso
set QEMU_EXTRA=
```

Press **Esc** at "Press ESC for boot menu", choose **Floppy**. At `A:\>` run `patch9x -auto C:\WINDOWS\SYSTEM`.
Close the VM window and start it again without the floppy: `vm.bat start Win98CD.iso`.

If patcher9x was not run at the first restart, Setup stops with an error. Close the VM, run patcher9x as above, then
start the VM with `Win98CD.iso` again; Setup continues. Setup finishes to the desktop (640x480, 16 colours).

### 3.2 Drivers (one step)

Windows 98 has no drivers for QEMU's hardware. `E:\SETUP.BAT` installs them all: display, mouse, 3D and fast disk
access. Keep the Win98 CD in D:, Windows needs it.

1. Win+R: `E:\SETUP.BAT` → Enter. It takes a few seconds and ends with "Done". Close its window.
2. Restart Windows 98 (Start → Shut Down → Restart).
3. Windows now finds the new devices one by one. For each wizard just press **Enter** (Next … Finish); it finds every
   driver by itself. When it asks to restart, say Yes (two or three times in all).
4. At the end a box says "Windows 98 is now set up for QEMU … Restart now?" → **Yes**.

After that restart: 1024x768 True Color, and the mouse follows the host pointer without grabbing it.

### 3.3 Check 3D, back up

MS-DOS prompt in Windows 98 (Win+R: `command`):

```bat
E:\SGLDIAG
E:\INSTALL /TEST
C:
cd \SGLTEST
GLIDETST
SGLGEARS
```

`SGLDIAG` ends with `gl 4.6` (your host's OpenGL version). `GLIDETST`: a spinning coloured triangle; `SGLGEARS`:
spinning gears; both about 60 fps.

Shut down Windows 98 and copy the disk: `copy win98.qcow2 win98-clean.qcow2`.

## 4. Games

1. Start the VM with the game's CD image (`vm.bat start game.iso`) and install the game.
2. In an MS-DOS prompt in Windows 98, copy our DLLs next to the game's EXE: `E:\INSTALL "C:\Game Folder"` (the
   game's own DLLs are kept as `.sgb`).
3. Start the game from its own folder or shortcut, and pick its 3dfx/Glide or OpenGL renderer.

3D shooters need a grabbed mouse for precise aiming: `set MOUSE=rel` before `vm.bat start`. Click in the window to
grab the mouse, Ctrl+Alt+G releases it. `vm.bat start game.iso fps_cap=0` removes the 60 fps limit.

Logs: `logs\qemu.log`, `logs\server.log`.

