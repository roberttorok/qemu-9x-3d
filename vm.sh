#!/usr/bin/env bash
# Start/stop the Windows 98 VM and its SharedGL server. One script for both hosts:
# Linux (KVM) and Windows (WHPX, run it in MSYS2's UCRT64 terminal).
#
#   ./vm.sh start [CD.iso] [fps_cap=N]   CD.iso is D: in Windows 98, guest.iso is E:
#   ./vm.sh stop                         quits QEMU (shut Windows 98 down first) and the server
#   ./vm.sh status
#   ./vm.sh create                       a new empty disk (DISK, default win98.qcow2); never overwrites
#
# fps_cap=N   frame limit for 3D games (default 60, 0 = none)
# Optional environment variables:
#   DISK=file.qcow2       another VM disk (default win98.qcow2)
#   QEMU=path             another QEMU (default: our patched build, see README.md)
#   QEMU_EXTRA=-snapshot  extra QEMU options (-snapshot: forget all disk changes when the VM stops)
#   QDISPLAY=...          QEMU -display option (default sdl,gl=on; Linux with MOUSE=abs gtk,gl=on,grab-on-hover=on)
#   AUDIO=pa              QEMU sound backend (default sdl; pa = PulseAudio/PipeWire on Linux)
#   NOSOUND=1             no sound card
#   MOUSE=abs             absolute mouse via QEMouse: the pointer moves freely in and out of the window, no grab
#                         (desktop, menu games); 3D shooters can't aim with it. Default rel: relative PS/2 mouse
#                         that the window grabs (click in it; Ctrl+Alt+G releases it). On Linux rel uses the SDL
#                         window (GTK can't grab on Wayland), abs the GTK one.
#   VGA=cirrus            the Cirrus card instead of QEMU's standard VGA (don't: restarts hang)
#   VOODOO=0              SharedGL device with its plain ivshmem PCI IDs instead of 3dfx Voodoo2 ones
#                         (default 1 with our QEMU on both hosts; a stock QEMU on Linux gets 0)
#
# Logs: logs/qemu.log, logs/server.log
# Debugging the server: SERVER=path/to/sglrenderer, SERVER_WRAP="gdb -batch -x tools/server-crash.gdb --args"

cd "$(dirname "$0")" || exit 1
mkdir -p logs

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) WIN=1 ;;
  *)                    WIN= ;;
esac

DISK="${DISK:-win98.qcow2}"
RAM=256                 # MB; Windows 98 becomes unstable above 512
SHM_MB=64               # the server's -m and QEMU's shared memory size must match
# Settings that differ between the hosts. Keep everything else the same on both.
if [ -n "$WIN" ]; then
  OUR_QEMU=qemu-11.0.1/build/qemu-system-x86_64.exe
  SERVER="${SERVER:-sharedgl/build-win/sglrenderer.exe}"
  # Its own shared memory name, so this can run next to the Windows XP VM.
  SHM='Local\sharedgl_win98'
  ACCEL=whpx            # in-hypervisor irqchip (WHPX's default): with kernel-irqchip=off the clock runs slow
  DISPLAY_OPT=${QDISPLAY:-sdl,gl=on}
else
  OUR_QEMU=qemu-11.0.1/build-linux/qemu-system-x86_64
  SERVER_DEFAULT=sharedgl/build-linux/sglrenderer
  # The prebuilt ZIP (prebuild.sh) has QEMU, its firmware and the server in bin/, and the
  # libraries they need that a distribution may lack or have in another version in bin/lib.
  if [ -x bin/qemu-system-x86_64 ]; then
    PREBUILT=1
    OUR_QEMU=bin/qemu-system-x86_64
    SERVER_DEFAULT=bin/sglrenderer
    export LD_LIBRARY_PATH="$PWD/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
  SERVER="${SERVER:-$SERVER_DEFAULT}"
  SHM=sharedgl_win98    # /dev/shm/sharedgl_win98
  ACCEL=kvm
  if [ "${MOUSE:-rel}" = rel ]; then DISPLAY_OPT=${QDISPLAY:-sdl,gl=on}
  else DISPLAY_OPT=${QDISPLAY:-gtk,gl=on,grab-on-hover=on}
  fi
fi
# Our patched QEMU (qemu-all.patch: sound DMA fix, vmmouse fix, ivshmem-win) if it is built.
# With stock QEMU the window freezes while the guest plays sound, and the mouse can die.
if [ -z "$QEMU" ]; then
  if [ -x "$OUR_QEMU" ]; then QEMU=$OUR_QEMU
  elif [ -n "$WIN" ]; then echo "QEMU isn't built: run make (README.md step 1)"; exit 1
  else QEMU=qemu-system-x86_64
  fi
fi

# The SharedGL PCI device: ivshmem-win (in our QEMU, both hosts) shares the server's memory by
# name: a Win32 mapping on Windows, /dev/shm/$SHM on Linux. bar64=off: Win98 can't use a 64-bit BAR.
# A stock QEMU (Linux) lacks it: then ivshmem-plain on the same /dev/shm file, without VOODOO.
# VOODOO=1 (default): the device reports 3dfx Voodoo2 IDs (121a:0002) instead of 1af4:1110, so game
# setup programs that look for a 3dfx card (EA's 3DSetup) offer Glide. Windows 98 then finds "new
# hardware" once: install it from E:\ like the shared memory device (sgl98.inf lists both IDs).
if [ -n "$WIN" ] || "$QEMU" -device help 2>/dev/null | grep -q '"ivshmem-win"'; then
  SHMDEV=(-device "ivshmem-win,name=$SHM,size=${SHM_MB}M,bar64=off")
  VOODOO=${VOODOO:-1}
  [ "$VOODOO" = 1 ] && SHMDEV[1]="${SHMDEV[1]},vendor-id=0x121a,device-id=0x0002"
else
  if [ "$VOODOO" = 1 ]; then
    echo "VOODOO=1 needs ivshmem-win, which $QEMU doesn't have: build our QEMU (README.md step 1) or use VOODOO=0"; exit 1
  fi
  SHMDEV=(-object "memory-backend-file,id=sglshm,size=${SHM_MB}M,share=on,mem-path=/dev/shm/$SHM"
          -device ivshmem-plain,memdev=sglshm)
fi

# Process IDs in logs/*.pid. On Windows they are Windows process IDs (QEMU and the server
# are native Windows programs), so they are checked and stopped with tasklist/taskkill.
pid_of() { [ -f "$1" ] && tr -dc '0-9' < "$1"; }
running() {
  local pid; pid=$(pid_of "$1"); [ -n "$pid" ] || return 1
  if [ -n "$WIN" ]; then tasklist //fo csv //nh //fi "PID eq $pid" 2> /dev/null | grep -q "\"$pid\""
  else kill -0 "$pid" 2> /dev/null
  fi
}
kill_pid() {
  local pid; pid=$(pid_of "$1"); [ -n "$pid" ] || return 0
  if [ -n "$WIN" ]; then taskkill //f //pid "$pid" > /dev/null 2>&1
  else kill "$pid" 2> /dev/null
  fi
}
# For QEMU's command line: a Windows path on Windows, commas doubled (QEMU's option separator).
qpath() {
  local p
  if [ -n "$WIN" ]; then p=$(cygpath -am "$1"); else p=$(realpath "$1"); fi
  echo "${p//,/,,}"
}
# Windows: all sglrenderer.exe process IDs, to find the one this script starts.
server_pids() { tasklist //fo csv //nh //fi "IMAGENAME eq sglrenderer.exe" 2> /dev/null | tr -d '\r' | awk -F'","' '/sglrenderer/{print $2}'; }

stop_server() {
  running logs/server.pid && kill_pid logs/server.pid
  rm -f logs/server.pid
}

start_server() {
  if [ -n "$WIN" ]; then
    # The server is a UCRT64 program and needs that environment's DLLs.
    local old=" $(server_pids | tr '\n' ' ') " p i
    PATH=/ucrt64/bin:/usr/bin $SERVER_WRAP "$SERVER" -m $SHM_MB -f "$FPS_CAP" -s "$SHM" > logs/server.log 2>&1 &
    disown
    # MSYS2's $! is not the Windows process ID: ask Windows which sglrenderer.exe is new.
    for i in 1 2 3 4 5 6 7 8 9 10; do
      sleep 0.5
      for p in $(server_pids); do case "$old" in *" $p "*) ;; *) echo "$p" > logs/server.pid ;; esac; done
      [ -f logs/server.pid ] && break
    done
  else
    $SERVER_WRAP "$SERVER" -m $SHM_MB -f "$FPS_CAP" -s "$SHM" > logs/server.log 2>&1 &
    echo $! > logs/server.pid
    sleep 1
  fi
}

start() {
  local CD="" arg
  FPS_CAP=60
  for arg in "$@"; do
    case "$arg" in
      fps_cap=*) FPS_CAP="${arg#fps_cap=}" ;;
      *)         CD="$arg" ;;
    esac
  done
  [[ "$FPS_CAP" =~ ^[0-9]+$ ]] && [ "$FPS_CAP" -le 1000 ] || { echo "fps_cap takes a number from 0 (no limit) to 1000"; exit 1; }
  [ -f "$DISK" ] || { echo "No VM disk at $DISK (./vm.sh create makes one, README.md step 2)"; exit 1; }
  if [ -z "$WIN" ] && ! [ -r /dev/kvm -a -w /dev/kvm ]; then
    echo "No access to /dev/kvm: virtualization off in the BIOS, or your user is not in the kvm group"; exit 1
  fi
  [ -z "$CD" ] || [ -f "$CD" ] || { echo "No CD image at $CD"; exit 1; }
  [ -x "$SERVER" ] || { echo "The SharedGL server isn't built: $SERVER (README.md step 1)"; exit 1; }
  if running logs/qemu.pid; then echo "The VM is already running."; exit 1; fi

  # Always start a fresh server: an old one would still hold the last VM's state.
  stop_server
  start_server
  if ! running logs/server.pid; then echo "The SharedGL server didn't start, see logs/server.log"; cat logs/server.log; exit 1; fi

  local CD_FILE="" SOUND=() EXTRA=() VMPORT=on
  case "${MOUSE:-rel}" in
    abs) ;;
    rel) VMPORT=off ;;
    *)   echo "MOUSE must be abs or rel"; stop_server; exit 1 ;;
  esac
  [ -n "$CD" ] && CD_FILE=",format=raw,file=$(qpath "$CD")"
  [ "$NOSOUND" = 1 ] || SOUND=(-audiodev "${AUDIO:-sdl},id=snd,in.voices=0" -device sb16,audiodev=snd)
  [ -n "$WIN" ] && EXTRA=(-L qemu-11.0.1/pc-bios)
  [ -n "$PREBUILT" ] && EXTRA=(-L bin/pc-bios)
  rm -f logs/qemu.pid

  # Don't change the order of the devices: it decides the PCI slots, and the drivers
  # installed in Windows 98 expect their cards in those slots.
  # -cpu pentium2: a CPU Windows 98 knows; the Windows 98 files are compiled for it.
  # -vga std: QEMU's standard VGA with the vmdisp9x driver. Not Cirrus: restarts hang.
  # MOUSE=rel (default): vmport=off, QEMouse works as a plain PS/2 mouse (games that read mouse
  # movement need that). MOUSE=abs: vmport=on, absolute mouse through the QEMouse driver.  -qmp: used by stop.
  # MSYS2_ARG_CONV_EXCL: MSYS2 must not turn QEMU's arguments into Windows paths.
  # setsid (Linux): the VM keeps running after this terminal is closed.
  # Linux on Wayland: SDL2 would pick X11 (XWayland), where with screens of different scales the
  # window is shrunk on the unscaled ones (1024x768 shown as 602x452 next to a 170% screen).
  # As a native Wayland window it is pixel for pixel on a scale-1 screen.
  local LAUNCH=()
  if [ -z "$WIN" ]; then
    LAUNCH=(setsid)
    [ -n "$WAYLAND_DISPLAY" ] && LAUNCH=(setsid env SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-wayland}")
  fi
  SDL_RENDER_SCALE_QUALITY=linear SDL_RENDER_VSYNC=0 MSYS2_ARG_CONV_EXCL='*' \
  "${LAUNCH[@]}" "$QEMU" "${EXTRA[@]}" \
    -name "Windows 98" \
    -accel $ACCEL \
    -machine pc,hpet=off,vmport=$VMPORT \
    -cpu pentium2 -smp 1 -m $RAM \
    -rtc base=localtime \
    -drive "if=none,id=hd,format=qcow2,file=$(qpath "$DISK")" \
    -device ide-hd,bus=ide.0,drive=hd,bootindex=0 \
    -drive "if=none,id=cd,media=cdrom,readonly=on$CD_FILE" \
    -device ide-cd,bus=ide.1,unit=0,drive=cd,bootindex=1 \
    -drive "if=none,id=helper,media=cdrom,readonly=on,format=raw,file=guest.iso" \
    -device ide-cd,bus=ide.1,unit=1,drive=helper \
    -vga "${VGA:-std}" \
    "${SHMDEV[@]}" \
    -display "$DISPLAY_OPT" \
    "${SOUND[@]}" \
    -nic none \
    -qmp tcp:127.0.0.1:4445,server=on,wait=off \
    -pidfile logs/qemu.pid \
    $QEMU_EXTRA > logs/qemu.log 2>&1 < /dev/null &
  disown

  sleep 3
  if ! running logs/qemu.pid; then
    echo "QEMU didn't start, see logs/qemu.log"
    cat logs/qemu.log
    stop_server
    exit 1
  fi
  echo "VM started. Windows needs about a minute to reach the desktop."
}

# Tell QEMU to quit through its QMP socket (-qmp below), with bash's /dev/tcp: no other tools needed.
# Reads QEMU's replies until it closes the connection, so QEMU has handled the quit before we go on.
qmp_quit() {
  exec 3<> /dev/tcp/127.0.0.1/4445 || return 1
  printf '%s\n' '{"execute":"qmp_capabilities"}' '{"execute":"quit"}' >&3
  while read -t 5 -r _ <&3; do :; done
  exec 3<&-
}

stop() {
  if running logs/qemu.pid; then
    qmp_quit 2> /dev/null
    sleep 2
    running logs/qemu.pid && kill_pid logs/qemu.pid
    echo "VM stopped"
  fi
  rm -f logs/qemu.pid
  stop_server
}

status() {
  if running logs/qemu.pid; then echo "VM: running"; else echo "VM: stopped"; fi
  if running logs/server.pid; then echo "server: running"; else echo "server: stopped"; fi
}

# A new, empty 8 GB disk for installing Windows 98. Never overwrites one.
create() {
  [ -e "$DISK" ] && { echo "$DISK already exists; not touching it. Use DISK=other.qcow2 for a new one."; exit 1; }
  local img=${OUR_QEMU%/*}/qemu-img
  [ -n "$WIN" ] && img=$img.exe
  [ -x "$img" ] || img=qemu-img
  "$img" create -f qcow2 "$DISK" 8G
}

case "$1" in
  start)  shift; start "$@" ;;
  stop)   stop ;;
  status) status ;;
  create) create ;;
  *)      echo "Usage: $0 start [CD.iso] [fps_cap=N] | stop | status | create"; exit 1 ;;
esac
