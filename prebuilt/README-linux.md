# @RELEASE@ @VERSION@, prebuilt for Linux x86_64

3dfx Voodoo (Glide) and OpenGL games in a **Windows 98 SE** VM under QEMU, drawn by your GPU. This ZIP has
everything built: QEMU with our patches, the SharedGL server, and `guest.iso` with the Windows 98 drivers. You bring
the Windows 98 SE CD and its product key.

Hobby project, no warranty. Keep backups of your VM disk.

## Before you start

1. **Distribution.** Built on **@DISTRO@**. It runs on that release; on others the libraries below may have
   different versions, and then you have to build from source (see Source code below).
2. **Libraries:**

   ```bash
   sudo apt-get install -y @APT@
   ```

3. **KVM:** your user needs access to `/dev/kvm` (`ls -l /dev/kvm`; on Ubuntu `sudo usermod -aG kvm $USER`, then log
   in again). Virtualization must be on in the BIOS.
4. **Files**, into this folder: your Windows 98 SE CD image as `Win98CD.iso`, and the patcher9x boot floppy
   (lets Windows 98 install on modern CPUs, used in step 3.1):

   ```bash
   curl -L -O https://github.com/JHRobotics/patcher9x/releases/download/v0.9.91/patcher9x-0.9.91-boot.ima
   ```

The steps below are numbered as in the full README of the source code; step 1 (building) is already done.

