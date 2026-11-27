@echo off
rem E:\SETUP.BAT: sets up a freshly installed Windows 98 SE for QEMU and SharedGL in one
rem go (README step 3.2): mouse, PCI bus, display driver, SharedGL device, DMA, colours.
rem Needs the Windows 98 CD in D: (Windows reads its own drivers from it; nothing is copied
rem from it). Run it once, then restart.
if exist D:\WIN98\BASE4.CAB goto cdok
echo The Windows 98 CD must be in D: (./vm.sh start Win98CD.iso).
echo Nothing was changed.
goto end
:cdok
echo Driver files ...
if not exist C:\DRIVERS\NUL md C:\DRIVERS
copy E:\SETUP\VMDISP9X.INF C:\DRIVERS > NUL
copy E:\SETUP\SGL98.INF C:\DRIVERS > NUL
copy E:\SETUP\FINISH.EXE C:\DRIVERS > NUL
copy E:\VMDISP\QEMUMINI.DRV C:\WINDOWS\SYSTEM > NUL
copy E:\VMDISP\QEMUMINI.VXD C:\WINDOWS\SYSTEM > NUL
copy E:\VMDISP\VMDISP9X.DLL C:\WINDOWS\SYSTEM > NUL
copy E:\VMDISP\VMHAL9X.DLL C:\WINDOWS\SYSTEM > NUL
copy E:\VMDISP\VMHAL486.DLL C:\WINDOWS\SYSTEM > NUL
if not exist C:\WINDOWS\SYSTEM32\NUL md C:\WINDOWS\SYSTEM32
if not exist C:\WINDOWS\SYSTEM32\DRIVERS\NUL md C:\WINDOWS\SYSTEM32\DRIVERS
copy E:\SGL98.SYS C:\WINDOWS\SYSTEM32\DRIVERS > NUL
echo Mouse driver (QEMouse) ...
start /w rundll32 setupx.dll,InstallHinfSection DefaultInstall 128 E:\QEMOUSE\QEMOUSE.INF
echo PCI bus, driver search path ...
regedit /s E:\SETUP\SETUP98.REG
echo.
echo Done. Restart Windows (Start, Shut Down, Restart). Windows then finds
echo the PCI devices: press Enter for each (Next ... Finish) and let it
echo restart when it asks. It sets DMA and True Color by itself and says
echo when everything is done.
:end
