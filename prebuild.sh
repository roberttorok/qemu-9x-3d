#!/usr/bin/env bash
# prebuild.sh: the release ZIPs for the host it runs on. Run it where you run make: on Linux any
# terminal, on Windows the MSYS2 UCRT64 terminal. It builds first (make), then writes to dist/:
#
#   9x-3d-for-qemu-VERSION-windows-x64.zip   or  9x-3d-for-qemu-VERSION-linux-x64.zip
#       QEMU, firmware, the SharedGL server, guest.iso, the launcher (vm.bat / vm.sh), the libraries
#       they need, README.md (prebuilt/README-HOST.md filled in) and LICENSES/.
#   9x-3d-for-qemu-VERSION-src.zip
#       The source of everything in the binary ZIPs that we build: this repository, and the exact
#       QEMU, SharedGL, OpenGLide and QEMouse sources (the same from either host).
#
# VERSION comes from the VERSION file. Optional: REPO_URL (links in the README, default below).
# Needs, besides the build tools of README.md step 1: python3 (python in MSYS2), curl, ldd, strip.

set -euo pipefail
cd "$(dirname "$0")"

NAME=9x-3d-for-qemu
VERSION=$(tr -d ' \r\n' < VERSION)
REPO_URL=${REPO_URL:-https://github.com/roberttorok/9x-3d-for-qemu}
QEMU_VER=11.0.1
OPENGLIDE_BASE=ad9a3dd
QEMOUSE_TAG=v1.03
QEMOUSE_URL=https://github.com/qemus/qemouse/archive/refs/tags/$QEMOUSE_TAG.tar.gz
# The released guest drivers (README.md step 1.2; checked by guest/drivers.sha256).
DRIVER_ZIPS="vmdisp9x-1.2025.0.119b-driver-2d.zip qemouse.zip"
# The firmware our VM loads (vm.sh: -machine pc, -vga std or cirrus, no network card).
FIRMWARE="bios-256k.bin vgabios-stdvga.bin vgabios-cirrus.bin kvmvapic.bin linuxboot_dma.bin multiboot_dma.bin"
DIST=dist
CACHE=.prebuild-cache

die() { echo "prebuild.sh: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 1.2.3, not '$VERSION'"
# A GitHub tag build: the tag must be this version.
if [ "${GITHUB_REF_TYPE:-}" = tag ] && [ "${GITHUB_REF_NAME:-}" != "v$VERSION" ]; then
  die "tag ${GITHUB_REF_NAME} doesn't match VERSION $VERSION (tag v$VERSION)"
fi

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    HOST=windows; EXE=.exe; PY=python
    [ "${MSYSTEM:-}" = UCRT64 ] || die "on Windows run this in the MSYS2 UCRT64 terminal (now: ${MSYSTEM:-none})"
    QEMU_BUILD=qemu-11.0.1/build
    SERVER_BUILD=sharedgl/build-win/sglrenderer.exe
    ;;
  Linux)
    HOST=linux; EXE=; PY=python3
    QEMU_BUILD=qemu-11.0.1/build-linux
    SERVER_BUILD=sharedgl/build-linux/sglrenderer
    ;;
  *) die "unknown host $(uname -s)" ;;
esac
[ "$(uname -m)" = x86_64 ] || die "only x86_64 hosts are supported"
for t in $PY curl ldd strip git make; do command -v $t > /dev/null || die "$t is missing"; done

BIN_NAME=$NAME-$VERSION-$HOST-x64
SRC_NAME=$NAME-$VERSION-src
STAGE=$DIST/stage
mkdir -p "$DIST" "$CACHE"
rm -rf "$STAGE"
mkdir -p "$STAGE"
# The ZIPs' contents are put together here; only the ZIPs stay in dist/, also when this stops early.
trap 'rm -rf "$STAGE"' EXIT

# ---- vm.bat must start the VM like vm.sh: same machine, devices and options ----
# Only on Windows: only the Windows ZIP has vm.bat. A Linux build doesn't stop on a vm.bat that
# lags behind vm.sh; the next Windows build does.
if [ $HOST = windows ]; then
  step "vm.sh and prebuilt/vm.bat use the same QEMU options"
  for opt in '-machine pc,hpet=off,vmport=' '-cpu pentium2 -smp 1' '-rtc base=localtime' \
             'ide-hd,bus=ide.0,drive=hd,bootindex=0' 'ide-cd,bus=ide.1,unit=0,drive=cd,bootindex=1' \
             'if=none,id=helper,media=cdrom,readonly=on,format=raw,file=guest.iso' 'ide-cd,bus=ide.1,unit=1,drive=helper' \
             'bar64=off' 'vendor-id=0x121a,device-id=0x0002' 'id=snd,in.voices=0' 'sb16,audiodev=snd' \
             '-nic none' '-qmp tcp:127.0.0.1:4445,server=on,wait=off' '-name "Windows 98"' 'MOUSE:-rel' ; do
    bat_opt=$opt
    if [ "$opt" = 'MOUSE:-rel' ]; then bat_opt='if not defined MOUSE set "MOUSE=rel"'; fi
    if [ "$opt" = '-cpu pentium2 -smp 1' ]; then bat_opt='-cpu pentium2 -smp 1 -m 256'; fi
    grep -qF -- "$opt" vm.sh || die "vm.sh lacks '$opt' (update this check if vm.sh changed on purpose)"
    grep -qF -- "$bat_opt" prebuilt/vm.bat || die "prebuilt/vm.bat lacks '$bat_opt': make it start the VM like vm.sh"
  done
  grep -q '^RAM=256 ' vm.sh || die "vm.sh's RAM changed: change -m in prebuilt/vm.bat and this check"
  echo "ok"
fi

# ---- Build ----
step "make"
make
make check-imports
[ -x "$QEMU_BUILD/qemu-system-x86_64$EXE" ] || die "QEMU wasn't built"
[ -x "$SERVER_BUILD" ] || die "the SharedGL server wasn't built"
[ -f guest.iso ] || die "guest.iso wasn't built"

# The OpenGLide we built must be exactly ad9a3dd + our patch, or the source ZIP wouldn't match.
step "openglide/ is $OPENGLIDE_BASE + patches/openglide/openglide-win98.patch"
# A clone made with Git for Windows has CRLF files (core.autocrlf in its own settings, which MSYS2's
# git doesn't read): without the same setting every line would differ.
GIT_EOL=()
if [ $HOST = windows ]; then GIT_EOL=(-c core.autocrlf=true); fi
# Files the patch adds are untracked after "git apply": mark them, so the diff shows them.
git -C openglide ls-files -z --others --exclude-standard | xargs -0 -r git -C openglide add -N --
git "${GIT_EOL[@]}" -C openglide diff "$OPENGLIDE_BASE" | tr -d '\r' > "$STAGE/ogl.diff"
tr -d '\r' < patches/openglide/openglide-win98.patch | cmp -s - "$STAGE/ogl.diff" ||
  die "openglide/ differs from the patch: regenerate it (cd openglide && git add -N <new files> && git diff $OPENGLIDE_BASE > ../patches/openglide/openglide-win98.patch)"
rm "$STAGE/ogl.diff"
[ -z "$(git -C sharedgl status --porcelain --untracked-files=no)" ] ||
  die "sharedgl/ has uncommitted changes: commit them on windows-support first"
SGL_COMMIT=$(git -C sharedgl rev-parse HEAD)
echo "ok (SharedGL $SGL_COMMIT)"

# ---- Binary ZIP ----
step "staging $BIN_NAME"
B=$STAGE/$BIN_NAME
mkdir -p "$B/bin/pc-bios" "$B/LICENSES/third-party"
QEMU_DATA=qemu-11.0.1/pc-bios
for f in $FIRMWARE; do cp "$QEMU_DATA/$f" "$B/bin/pc-bios/"; done
strip -o "$B/bin/qemu-system-x86_64$EXE" "$QEMU_BUILD/qemu-system-x86_64$EXE"
strip -o "$B/bin/qemu-img$EXE" "$QEMU_BUILD/qemu-img$EXE"
cp guest.iso "$B/"
if [ $HOST = windows ]; then
  # vm.bat starts the server under its own name (so it never stops another SharedGL server).
  strip -o "$B/bin/sgl98server.exe" "$SERVER_BUILD"
  cp prebuilt/vm.bat "$B/"
  sed -i 's/$/\r/; s/\r\r$/\r/' "$B/vm.bat"
  BINS=("$B/bin/qemu-system-x86_64.exe" "$B/bin/qemu-img.exe" "$B/bin/sgl98server.exe")
else
  strip -o "$B/bin/sglrenderer" "$SERVER_BUILD"
  cp vm.sh "$B/"
  mkdir -p "$B/tools"
  cp tools/vmctl.py "$B/tools/"
  chmod 755 "$B/vm.sh" "$B/bin/"* "$B/tools/vmctl.py" 2> /dev/null || true
  chmod 644 "$B/bin/pc-bios/"*
  BINS=("$B/bin/qemu-system-x86_64" "$B/bin/qemu-img" "$B/bin/sglrenderer")
fi

# The libraries the programs need. Windows: every DLL from MSYS2's UCRT64 (Windows' own stay out).
# Linux: everything but the C library, the graphics driver's OpenGL and the desktop/sound
# libraries, which must be the system's own (AppImage's usual exclusions).
LIBS=()
if [ $HOST = windows ]; then
  mapfile -t LIBS < <(ldd "${BINS[@]}" | awk '$3 ~ /^\/ucrt64\// {print $3}' | sort -u)
  for l in "${LIBS[@]}"; do cp "$l" "$B/bin/"; done
else
  mkdir -p "$B/bin/lib"
  SYSTEM_LIBS='^(ld-linux|linux-vdso|libc|libm|libdl|libpthread|librt|libresolv|libutil|libanl|libnsl|libBrokenLocale|libgcc_s|libstdc\+\+|libGL|libGLX|libGLdispatch|libEGL|libOpenGL|libGLES|libgbm|libdrm|libX|libxcb|libxkbcommon|libwayland|libdecor|libasound|libpulse|libpipewire|libjack|libsystemd|libudev|libdbus|libexpat|libfontconfig|libfreetype|libharfbuzz|libgtk|libgdk|libatk|libcairo|libpango|libgio|libglib|libgobject|libgmodule|libgthread|libffi|libmount|libblkid|libselinux|libz)\.'
  mapfile -t LIBS < <(ldd "${BINS[@]}" | awk '$2 == "=>" && $3 ~ /^\// {print $3}' | sort -u |
                      while read -r l; do basename "$l" | grep -Eq "$SYSTEM_LIBS" || echo "$l"; done)
  for l in "${LIBS[@]}"; do cp -L "$l" "$B/bin/lib/"; done
  chmod 644 "$B/bin/lib/"* 2> /dev/null || true
  # The system libraries left out: their Debian/Ubuntu packages go in the README's apt-get line (@APT@).
  # With merged /usr, ldd may name /lib/... while dpkg knows /usr/lib/...: ask for both.
  command -v dpkg-query > /dev/null || die "dpkg-query is missing: the README's apt-get line needs a Debian/Ubuntu host"
  APT=$(ldd "${BINS[@]}" | awk '$2 == "=>" && $3 ~ /^\// {print $3}' | sort -u |
        while read -r l; do
          basename "$l" | grep -Eq "$SYSTEM_LIBS" || continue
          dpkg-query -S "$l" 2> /dev/null || dpkg-query -S "/usr$l" 2> /dev/null ||
            dpkg-query -S "$(realpath "$l")" 2> /dev/null || die "no package has $l"
        done | cut -d: -f1 | sort -u | tr '\n' ' ' | sed 's/ $//')
  [ -n "$APT" ] || die "found no system libraries for the README's apt-get line"
  echo "system packages: $APT"
fi
echo "${#LIBS[@]} libraries"

step "testing the staged QEMU alone (its own libraries and firmware)"
if [ $HOST = windows ]; then
  missing=$(cd "$B/bin" && PATH=/usr/bin:/c/Windows/System32 ldd ./*.exe | grep -E 'not found|\?\?\?' || true)
  [ -z "$missing" ] || die "missing DLLs: $missing"
  TEST_ENV=(env PATH=/c/Windows/System32:/c/Windows)
else
  missing=$(LD_LIBRARY_PATH="$B/bin/lib" ldd "${BINS[@]}" | grep 'not found' || true)
  [ -z "$missing" ] || die "missing libraries: $missing"
  TEST_ENV=(env LD_LIBRARY_PATH="$B/bin/lib")
fi
for vga in std cirrus; do
  set +e
  out=$(cd "$B" && timeout 8 "${TEST_ENV[@]}" "bin/qemu-system-x86_64$EXE" -L bin/pc-bios -accel tcg \
        -machine pc,hpet=off -cpu pentium2 -m 256 -vga $vga -display none -nic none -monitor none -S 2>&1)
  rc=$?
  set -e
  # 124: still running after 8 s (killed by timeout), as it should be.
  [ $rc = 124 ] || die "the staged QEMU (-vga $vga) stopped with code $rc: $out"
  # On Linux QEMU reports the timeout's SIGTERM ("terminating on signal 15 from pid N (timeout)"): expected.
  out=$(printf '%s\n' "$out" | grep -v '^qemu-system-x86_64: terminating on signal 15 ' || true)
  [ -z "$out" ] || die "the staged QEMU (-vga $vga) printed: $out"
done
echo "ok"

step "licenses"
L=$B/LICENSES
cp qemu-11.0.1/COPYING "$L/QEMU-COPYING-GPL-2.0.txt"
cp qemu-11.0.1/COPYING.LIB "$L/QEMU-COPYING.LIB-LGPL-2.1.txt"
cp qemu-11.0.1/LICENSE "$L/QEMU-LICENSE.txt"
cp sharedgl/LICENSE "$L/SharedGL-MIT.txt"
cp openglide/LICENSE "$L/OpenGLide-LGPL-2.1.txt"
cp guest/qemouse/license.md "$L/QEMouse-GPL-2.0.txt"
cp guest/vmdisp9x/license.txt "$L/vmdisp9x-MIT.txt"
cp LICENSE "$L/$NAME-MIT.txt"
{
  echo "$NAME $VERSION ($HOST x64): third-party libraries in this ZIP"
  echo
  echo "Our programs and their sources (in $SRC_NAME.zip):"
  echo "  QEMU $QEMU_VER with our patches        GPL-2.0 (parts LGPL-2.1, BSD, MIT)   https://www.qemu.org"
  echo "  SharedGL $SGL_COMMIT   MIT   https://github.com/roberttorok/sharedgl"
  echo "  OpenGLide $OPENGLIDE_BASE with our patch (in guest.iso)   LGPL-2.1   https://github.com/voyageur/openglide"
  echo "  QEMouse ${QEMOUSE_TAG#v} (in guest.iso)   GPL-2.0   https://github.com/qemus/qemouse"
  echo "  vmdisp9x 1.2025.0.119b (in guest.iso)   MIT   https://github.com/JHRobotics/vmdisp9x"
  echo "  Firmware in bin/pc-bios (SeaBIOS, SeaVGABIOS, QEMU's option ROMs): built from the sources in the QEMU tarball"
  echo "  (roms/), see QEMU's LICENSE and pc-bios/README there."
  echo
  echo "Libraries the programs use, unchanged, as packaged by the distribution named below. Their license texts are"
  echo "in LICENSES/third-party/ where the package provides them."
  echo
  if [ $HOST = windows ]; then
    echo "From MSYS2 (UCRT64 repository, https://www.msys2.org). Source of each package:"
    echo "https://packages.msys2.org/base/<base name>, and https://github.com/msys2/MINGW-packages."
    echo
    # pacman is slow to start: one query for all files, then one per package.
    declare -A files_of=()
    while read -r path _ _ _ pkg _; do
      files_of[$pkg]="${files_of[$pkg]:-}$(basename "$path") "
    done < <(pacman -Qo "${LIBS[@]}")
    for pkg in $(printf '%s\n' "${!files_of[@]}" | sort); do
      info=$(pacman -Qi "$pkg")
      ver=$(sed -n 's/^Version *: //p' <<< "$info")
      lic=$(sed -n 's/^Licenses *: //p' <<< "$info")
      url=$(sed -n 's/^URL *: //p' <<< "$info")
      printf '%s %s\n    license: %s\n    upstream: %s\n    files: %s\n' "$pkg" "$ver" "$lic" "$url" "${files_of[$pkg]}"
      short=${pkg#mingw-w64-ucrt-x86_64-}
      if [ -d "/ucrt64/share/licenses/$short" ]; then cp -r "/ucrt64/share/licenses/$short" "$L/third-party/$short"; fi
    done
  else
    # A subshell: os-release also sets NAME and VERSION, which would replace ours.
    PRETTY_NAME=$(. /etc/os-release 2> /dev/null && echo "${PRETTY_NAME:-}" || true)
    echo "From ${PRETTY_NAME:-this Linux distribution}."
    echo
    for l in "${LIBS[@]}"; do
      real=$(readlink -f "$l")
      if command -v dpkg-query > /dev/null && pkg=$(dpkg -S "$real" 2> /dev/null | head -1 | cut -d: -f1); then
        ver=$(dpkg-query -W -f='${Version}' "$pkg")
        src=$(dpkg-query -W -f='${source:Package}' "$pkg")
        printf '%s %s (source package %s: apt-get source %s=%s)\n    file: %s\n' "$pkg" "$ver" "$src" "$src" "$ver" "$(basename "$l")"
        if [ -f "/usr/share/doc/$pkg/copyright" ]; then cp "/usr/share/doc/$pkg/copyright" "$L/third-party/$pkg.txt"; fi
      elif command -v rpm > /dev/null && pkg=$(rpm -qf "$real" 2> /dev/null); then
        printf '%s\n    license: %s\n    file: %s\n' "$pkg" "$(rpm -q --qf '%{LICENSE}' "$pkg")" "$(basename "$l")"
      else
        printf '%s (package unknown)\n' "$(basename "$l")"
      fi
    done
  fi
} > "$L/THIRD-PARTY.txt"
# Windows users open it in Notepad.
if [ $HOST = windows ]; then sed -i 's/$/\r/' "$L/THIRD-PARTY.txt"; fi

step "README.md"
if [ $HOST = linux ]; then
  # A subshell: os-release also sets NAME and VERSION, which would replace ours.
  PRETTY_NAME=$(. /etc/os-release 2> /dev/null && echo "${PRETTY_NAME:-}" || true)
  GLIBC=$(ldd --version | head -1 | grep -oE '[0-9]+\.[0-9]+$')
else
  PRETTY_NAME=; GLIBC=
fi
sed -e "s|@RELEASE@|$NAME|g" -e "s|@VERSION@|$VERSION|g" -e "s|@REPO_URL@|$REPO_URL|g" \
    -e "s|@QEMU_VERSION@|$QEMU_VER|g" -e "s|@DISTRO@|${PRETTY_NAME:-}|g" -e "s|@GLIBC@|$GLIBC|g" -e "s|@APT@|${APT:-}|g" \
    "prebuilt/README-$HOST.md" > "$B/README.md"
! grep -n '@[A-Z_]*@' "$B/README.md" || die "a placeholder in prebuilt/README-$HOST.md wasn't filled in"

step "$BIN_NAME.zip"
rm -f "$DIST/$BIN_NAME.zip"
$PY tools/mkzip.py "$DIST/$BIN_NAME.zip" "$B"

# ---- Source ZIP ----
step "staging $SRC_NAME"
S=$STAGE/$SRC_NAME
mkdir -p "$S/$NAME" "$S/upstream"
# This repository: what git has and what it would add (no build outputs, downloads or VM disks).
git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  size=$(stat -c %s "$f")
  [ "$size" -lt 20000000 ] || die "$f is $size bytes: not source; add it to .gitignore"
  mkdir -p "$S/$NAME/$(dirname "$f")"
  cp -p "$f" "$S/$NAME/$f"
done
for f in prebuild.sh Makefile vm.sh VERSION LICENSE patches/qemu/qemu-all.patch patches/openglide/openglide-win98.patch \
         prebuilt/vm.bat guest/install98.c; do
  [ -f "$S/$NAME/$f" ] || die "$f is missing from the source ZIP: is it ignored by .gitignore?"
done

if [ ! -f qemu-$QEMU_VER.tar.xz ]; then
  curl -fL -o "$CACHE/qemu-$QEMU_VER.tar.xz" "https://download.qemu.org/qemu-$QEMU_VER.tar.xz"
  cp "$CACHE/qemu-$QEMU_VER.tar.xz" "$S/upstream/"
else
  cp qemu-$QEMU_VER.tar.xz "$S/upstream/"
fi
git -C sharedgl archive --format=tar.gz --prefix=sharedgl/ -o "$PWD/$S/upstream/sharedgl-$SGL_COMMIT.tar.gz" "$SGL_COMMIT"
git -C openglide archive --format=tar.gz --prefix=openglide/ -o "$PWD/$S/upstream/openglide-$OPENGLIDE_BASE.tar.gz" "$OPENGLIDE_BASE"
[ -f "$CACHE/qemouse-$QEMOUSE_TAG.tar.gz" ] || curl -fL -o "$CACHE/qemouse-$QEMOUSE_TAG.tar.gz" "$QEMOUSE_URL"
cp "$CACHE/qemouse-$QEMOUSE_TAG.tar.gz" "$S/upstream/"
for z in $DRIVER_ZIPS; do
  [ -f "$z" ] || die "$z is missing: download it (README.md step 1.2)"
  cp "$z" "$S/upstream/"
done
(cd "$S/upstream" && sha256sum -c --quiet "$OLDPWD/guest/drivers.sha256") || die "a driver ZIP doesn't match guest/drivers.sha256"
cat > "$S/SOURCES.txt" <<EOF
$NAME $VERSION: the source code of the release ZIPs.

$NAME/                                     this repository (Makefile, vm.sh, prebuild.sh, guest programs, patches)
upstream/qemu-$QEMU_VER.tar.xz                  QEMU $QEMU_VER release tarball; our changes: $NAME/patches/qemu/
upstream/sharedgl-$SGL_COMMIT.tar.gz
                                           SharedGL as built (branch windows-support of
                                           https://github.com/roberttorok/sharedgl, commit $SGL_COMMIT)
upstream/openglide-$OPENGLIDE_BASE.tar.gz           OpenGLide $OPENGLIDE_BASE; our changes: $NAME/patches/openglide/
upstream/qemouse-$QEMOUSE_TAG.tar.gz               QEMouse ${QEMOUSE_TAG#v} source
upstream/qemouse.zip                           QEMouse ${QEMOUSE_TAG#v} released driver (goes on guest.iso unmodified)
upstream/vmdisp9x-1.2025.0.119b-driver-2d.zip  vmdisp9x released 2D driver (goes on guest.iso unmodified;
                                           source: https://github.com/JHRobotics/vmdisp9x, tag v1.2025.0.119)

To build: put the upstream sources where README.md step 1.2 puts them, instead of downloading and cloning:

  cd $NAME
  tar xf ../upstream/qemu-$QEMU_VER.tar.xz && (cd qemu-$QEMU_VER && patch -p1 < ../patches/qemu/qemu-all.patch)
  tar xf ../upstream/sharedgl-$SGL_COMMIT.tar.gz
  tar xf ../upstream/openglide-$OPENGLIDE_BASE.tar.gz && (cd openglide && patch -p1 < ../patches/openglide/openglide-win98.patch)
  unzip -o ../upstream/vmdisp9x-1.2025.0.119b-driver-2d.zip -d guest/vmdisp9x
  unzip -o ../upstream/qemouse.zip -d guest/qemouse
  make

(The OpenGLide patch is a git diff: with git, "git apply" works too.) The build tools: README.md step 1.1.
EOF

step "$SRC_NAME.zip"
rm -f "$DIST/$SRC_NAME.zip"
$PY tools/mkzip.py "$DIST/$SRC_NAME.zip" "$S"

rm -rf "$STAGE"
step "done"
ls -l "$DIST/$BIN_NAME.zip" "$DIST/$SRC_NAME.zip"
