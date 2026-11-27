@echo off
rem Starts the Windows 98 VM and its SharedGL server: the Windows launcher of the prebuilt ZIP
rem (prebuild.sh). Plain cmd, nothing to install. A source checkout uses vm.sh instead; keep the
rem QEMU options here the same as there.
rem
rem   vm.bat start [CD.iso] [fps_cap=N]   CD.iso is D: in Windows 98, guest.iso is E:.
rem                                       Runs until the VM window closes, then stops the server.
rem   vm.bat stop                         kills the VM and the server (shut Windows 98 down first)
rem   vm.bat status
rem   vm.bat create                       a new empty 8 GB disk (DISK, default win98.qcow2); never overwrites
rem
rem Optional settings, as in vm.sh. Set them first, e.g.  set MOUSE=rel
rem   DISK=file.qcow2  QEMU_EXTRA=...  QDISPLAY=...  AUDIO=...  NOSOUND=1  MOUSE=rel  VGA=...  VOODOO=0
rem Logs: logs\qemu.log, logs\server.log
setlocal EnableExtensions

set "FIND=%SystemRoot%\System32\find.exe"
set "QEMU=bin\qemu-system-x86_64.exe"
rem The server has its own name, so stopping it never touches another SharedGL server (the XP VM's).
set "SERVER_EXE=sgl98server.exe"
set "SHM=Local\sharedgl_win98"
set "SHM_MB=64"
if not defined FPS_CAP set "FPS_CAP=60"

rem cmd splits fps_cap=N at the "=", so it arrives as two arguments.
set "ARG_CD=%~2"
if /i "%~2"=="fps_cap" set "FPS_CAP=%~3"& set "ARG_CD="
if /i "%~3"=="fps_cap" set "FPS_CAP=%~4"

rem The CD image: relative to the folder you are in, else to this folder.
set "CDIMG="
if "%ARG_CD%"=="" goto cd_done
for %%F in ("%ARG_CD%") do set "CDIMG=%%~fF"
if exist "%CDIMG%" goto cd_done
for %%F in ("%~dp0%ARG_CD%") do set "CDIMG=%%~fF"
if exist "%CDIMG%" goto cd_done
echo No CD image at %ARG_CD%
exit /b 1
:cd_done

cd /d "%~dp0"
if not exist logs mkdir logs
if not defined DISK set "DISK=win98.qcow2"

if /i "%~1"=="start"  goto start
if /i "%~1"=="stop"   goto stop
if /i "%~1"=="status" goto status
if /i "%~1"=="create" goto create
echo Usage: vm.bat start [CD.iso] [fps_cap=N] ^| stop ^| status ^| create
exit /b 1


:start
echo %FPS_CAP%| findstr /r /x "[0-9][0-9]*" >nul || goto bad_fps
if %FPS_CAP% gtr 1000 goto bad_fps
if not exist "%DISK%" echo No VM disk at %DISK% ("vm.bat create" makes one)& exit /b 1
call :qemu_running && echo The VM is already running.&& exit /b 1
if not defined MOUSE set "MOUSE=abs"
set "VMPORT="
if /i "%MOUSE%"=="abs" set "VMPORT=on"
if /i "%MOUSE%"=="rel" set "VMPORT=off"
if not defined VMPORT echo MOUSE must be abs or rel& exit /b 1

rem QEMU's option separator is the comma: commas in paths are doubled.
for %%F in ("%DISK%") do set "DISKFULL=%%~fF"
set "DISKFULL=%DISKFULL:,=,,%"
set "CDOPT=if=none,id=cd,media=cdrom,readonly=on"
if defined CDIMG set "CDOPT=%CDOPT%,format=raw,file=%CDIMG:,=,,%"

rem The SharedGL device. bar64=off: Windows 98 can't use a 64-bit BAR. VOODOO=1 (default): it
rem reports 3dfx Voodoo2 IDs, so game setup programs that look for a 3dfx card offer Glide.
set "SHMDEV=ivshmem-win,name=%SHM%,size=%SHM_MB%M,bar64=off"
if not "%VOODOO%"=="0" set "SHMDEV=%SHMDEV%,vendor-id=0x121a,device-id=0x0002"
if not defined QDISPLAY set "QDISPLAY=sdl,gl=on"
if not defined AUDIO set "AUDIO=sdl"
if not defined VGA set "VGA=std"
set "SOUND=-audiodev %AUDIO%,id=snd,in.voices=0 -device sb16,audiodev=snd"
if "%NOSOUND%"=="1" set "SOUND="

rem Always a fresh server: an old one would still hold the last VM's state.
taskkill /f /im %SERVER_EXE% >nul 2>&1
start "" /b bin\%SERVER_EXE% -m %SHM_MB% -f %FPS_CAP% -s %SHM% >logs\server.log 2>&1
ping -n 2 127.0.0.1 >nul
tasklist /nh /fi "IMAGENAME eq %SERVER_EXE%" 2>nul | "%FIND%" /i "%SERVER_EXE%" >nul || goto server_failed

echo VM started. Windows needs about a minute to reach the desktop.
echo Leave this window open: closing it kills the VM. Shut Windows 98 down to quit.
set SDL_RENDER_SCALE_QUALITY=linear
set SDL_RENDER_VSYNC=0
rem Don't change the order of the devices: it decides the PCI slots, and the drivers
rem installed in Windows 98 expect their cards in those slots. See vm.sh for the reasons.
"%QEMU%" -L bin\pc-bios -name "Windows 98" -accel whpx ^
  -machine pc,hpet=off,vmport=%VMPORT% -cpu pentium2 -smp 1 -m 256 -rtc base=localtime ^
  -drive "if=none,id=hd,format=qcow2,file=%DISKFULL%" -device ide-hd,bus=ide.0,drive=hd,bootindex=0 ^
  -drive "%CDOPT%" -device ide-cd,bus=ide.1,unit=0,drive=cd,bootindex=1 ^
  -drive if=none,id=helper,media=cdrom,readonly=on,format=raw,file=guest.iso ^
  -device ide-cd,bus=ide.1,unit=1,drive=helper ^
  -vga %VGA% -device "%SHMDEV%" -display %QDISPLAY% %SOUND% -nic none ^
  -pidfile logs\qemu.pid %QEMU_EXTRA% >logs\qemu.log 2>&1 <nul
set "RC=%ERRORLEVEL%"
taskkill /f /im %SERVER_EXE% >nul 2>&1
del logs\qemu.pid 2>nul
if "%RC%"=="0" echo VM stopped.& exit /b 0
echo QEMU stopped with an error (logs\qemu.log):
type logs\qemu.log
exit /b %RC%

:bad_fps
echo fps_cap takes a number from 0 (no limit) to 1000
exit /b 1

:server_failed
echo The SharedGL server didn't start (logs\server.log):
type logs\server.log
exit /b 1


:stop
rem Two lines: cmd expands %QPID% when it reads a line, before :qemu_running has set it.
call :qemu_running || goto stop_server
taskkill /f /pid %QPID% >nul 2>&1
:stop_server
taskkill /f /im %SERVER_EXE% >nul 2>&1
del logs\qemu.pid 2>nul
echo VM stopped.
exit /b 0


:status
call :qemu_running && echo VM: running|| echo VM: stopped
tasklist /nh /fi "IMAGENAME eq %SERVER_EXE%" 2>nul | "%FIND%" /i "%SERVER_EXE%" >nul && echo server: running|| echo server: stopped
exit /b 0


:create
if exist "%DISK%" echo %DISK% already exists; not touching it. Set DISK=other.qcow2 for a new one.& exit /b 1
bin\qemu-img.exe create -f qcow2 "%DISK%" 8G
exit /b


rem Sets QPID; succeeds if logs\qemu.pid names a running QEMU.
:qemu_running
set "QPID="
if not exist logs\qemu.pid exit /b 1
set /p QPID=<logs\qemu.pid
if not defined QPID exit /b 1
tasklist /nh /fi "PID eq %QPID%" /fi "IMAGENAME eq qemu-system-x86_64.exe" 2>nul | "%FIND%" "%QPID%" >nul
exit /b
