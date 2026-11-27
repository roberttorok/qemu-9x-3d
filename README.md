# qemu-9x-3d

3dfx Voodoo (Glide) and OpenGL games in a **Windows 98 SE** VM under QEMU, drawn by the host's GPU. No GPU
passthrough, no emulated Voodoo card. Hosts: **Linux** (KVM) and **Windows 10/11** (WHPX, with MSYS2).

```
Glide game  -> glide2x/glide3x.dll (OpenGLide) -> opengl32.dll (SharedGL) -> shared memory -> host GPU
OpenGL game ---------------------------------> opengl32.dll (SharedGL) -> shared memory -> host GPU
```

Hobby project, no warranty. Keep backups of your VM disk.

## 1. Build

All commands run in a bash terminal in this folder (on Windows: **MSYS2 UCRT64**).

### 1.1 Tools

**Linux** (tested on Ubuntu):

```bash
sudo apt-get install -y git make patch curl unzip xz-utils xorriso gcc g++ \
  gcc-mingw-w64-i686 g++-mingw-w64-i686 binutils-mingw-w64-i686 mingw-w64-i686-dev libsdl2-dev libepoxy-dev \
  ninja-build pkg-config python3-venv libglib2.0-dev libpixman-1-dev libgtk-3-dev libgbm-dev libdrm-dev \
  libslirp-dev libpulse-dev libpipewire-0.3-dev libasound2-dev zlib1g-dev
sudo update-alternatives --set i686-w64-mingw32-gcc /usr/bin/i686-w64-mingw32-gcc-win32
sudo update-alternatives --set i686-w64-mingw32-g++ /usr/bin/i686-w64-mingw32-g++-win32
```

(The 32-bit compiler must use the win32 thread model; `make` checks it.)

**Windows 10/11:**

1. Win+R `optionalfeatures` → tick **Windows Hypervisor Platform** → restart.
2. Install [MSYS2](https://www.msys2.org/), open **MSYS2 UCRT64** and `cd` to this folder (a short path without
   spaces, e.g. `/d/98`).
3. Install the packages (`-Syu` may close the terminal once: reopen it and run it again):

   ```bash
   pacman -Syu
   pacman -S --needed git make patch diffutils unzip curl xz xorriso \
     mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-pkgconf mingw-w64-ucrt-x86_64-python \
     mingw-w64-ucrt-x86_64-glib2 mingw-w64-ucrt-x86_64-pixman mingw-w64-ucrt-x86_64-SDL2 mingw-w64-ucrt-x86_64-libepoxy \
     mingw-w64-i686-gcc mingw-w64-i686-binutils
   ```

### 1.2 Downloads

```bash
# QEMU, SharedGL and OpenGLide, with our patches
curl -L -o qemu-11.0.1.tar.xz https://download.qemu.org/qemu-11.0.1.tar.xz
tar xf qemu-11.0.1.tar.xz
(cd qemu-11.0.1 && patch -p1 < ../patches/qemu/qemu-all.patch)
git clone -b windows-support https://github.com/roberttorok/sharedgl.git
git clone https://github.com/voyageur/openglide.git
(cd openglide && git checkout ad9a3dd && git apply ../patches/openglide/openglide-win98.patch)

# Windows 98 display and mouse drivers
curl -L -O https://github.com/JHRobotics/vmdisp9x/releases/download/v1.2025.0.119/vmdisp9x-1.2025.0.119b-driver-2d.zip
curl -L -O https://github.com/qemus/qemouse/releases/download/v1.03/qemouse.zip
sha256sum -c guest/drivers.sha256
unzip -o vmdisp9x-1.2025.0.119b-driver-2d.zip -d guest/vmdisp9x
unzip -o qemouse.zip -d guest/qemouse

# patcher9x boot floppy: Windows 98 Setup needs it on modern CPUs (step 3.1)
curl -L -O https://github.com/JHRobotics/patcher9x/releases/download/v0.9.91/patcher9x-0.9.91-boot.ima
```

On Windows, `tar`'s "Cannot create symlink" errors are harmless. Use MSYS2's own `git`, not Git for Windows.

### 1.3 Make

```bash
make
```

This builds our QEMU, the SharedGL server (`./vm.sh` uses and starts both) and `guest.iso`, the CD with the
Windows 98 drivers, DLLs and tests (drive E: in the VM).

## 2. Run the VM

```bash
./vm.sh create              # an empty 8 GB disk, win98.qcow2 (never overwrites)
./vm.sh start Win98CD.iso   # any CD image (drive D:), or none
./vm.sh status
./vm.sh stop                # shut down Windows 98 first
```

## 3. Install Windows 98 SE

Until step 3.2 the mouse may not work: use the keyboard (Tab, arrows, Enter, Win+R).

Put your Windows 98 SE CD image here as `Win98CD.iso` and start the VM with it. Boot from CD-ROM → Start Windows 98
Setup, let it partition and format, and continue until Setup restarts the PC the first time.

### 3.1 patcher9x

At that first restart, stop the VM and start it with the patcher9x floppy:

```bash
QEMU_EXTRA="-boot menu=on,splash-time=6000 -drive if=floppy,format=raw,file=patcher9x-0.9.91-boot.ima" ./vm.sh start Win98CD.iso
```

Press **Esc** for the boot menu, choose **Floppy**, and at `A:\>` run `patch9x -auto C:\WINDOWS\SYSTEM`. Then
`./vm.sh stop`, `./vm.sh start Win98CD.iso`, and Setup finishes.

### 3.2 Drivers

With the Win98 CD still in D:

1. Win+R: `E:\SETUP.BAT`, wait for "Done", restart Windows.
2. Windows finds the new devices one by one: press **Enter** through each wizard and say Yes to each restart.
3. At "Windows 98 is now set up for QEMU … Restart now?" → **Yes**.

Result: 1024x768 True Color, sound, 3D.

### 3.3 Check 3D

In an MS-DOS prompt (Win+R: `command`): `E:\SGLDIAG` should end with your host's OpenGL version. `E:\INSTALL /TEST`
puts test programs in `C:\SGLTEST` (`GLIDETST`, `GLIDE3TS`, `SGLGEARS`).

Then shut down and back up the disk: `cp win98.qcow2 win98-clean.qcow2`.

## 4. Games

1. Start the VM with the game's CD (`./vm.sh start game.iso`) and install the game.
2. In an MS-DOS prompt: `E:\INSTALL "C:\Game Folder"` copies our Glide 2, Glide 3 and OpenGL DLLs next to the game
   (its own DLLs are kept as `.sgb`).
3. Start the game and pick its 3dfx/Glide or OpenGL renderer. Direct3D is not supported.

The mouse is captured on click (Ctrl+Alt+G releases it), which 3D shooters need. `MOUSE=abs ./vm.sh start` gives a
free pointer instead, for the desktop and menu games. `fps_cap=0` removes the 60 fps limit.

## Built on

[QEMU](https://www.qemu.org/) 11.0.1, [SharedGL](https://github.com/roberttorok/sharedgl) (`windows-support`) and
[OpenGLide](https://github.com/voyageur/openglide), each with our patches; [patcher9x](https://github.com/JHRobotics/patcher9x),
[vmdisp9x](https://github.com/JHRobotics/vmdisp9x) and [QEMouse](https://github.com/qemus/qemouse) as released.

## License

This repository: MIT. QEMU patch: GPL-2.0. OpenGLide patch: LGPL-2.1. The downloaded drivers keep their own licenses
(QEMouse GPL-2.0, vmdisp9x MIT). Not affiliated with QEMU, Microsoft or 3dfx.
