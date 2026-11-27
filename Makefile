# Compiles what you have downloaded and cloned. See README.md. The same commands on both hosts:
# Linux (a terminal), Windows (MSYS2's UCRT64 terminal). It works out the host itself.
# This file never downloads, clones or patches anything. If something is missing, it stops and says so.
#
#   make            everything below, in order, then how long each part took
#   make qemu       configures and compiles QEMU (Linux: KVM, GTK, SDL; Windows: WHPX, SDL)
#   make server     the program on the host that draws on your GPU
#   make opengl32   the replacement opengl32.dll for Windows 98
#   make glide      glide2x.dll and glide3x.dll for Windows 98: OpenGlide, drawing through opengl32.dll
#   make driver     the Windows 98 kernel driver and its .inf
#   make programs   the installer and small test programs for Windows 98
#   make cd         puts all the Windows 98 files on a CD image, guest.iso
#   make clean      deletes everything make built on this host (never sources, downloads or the VM disk)

OBJ := build-98
SGL := sharedgl
OGL := openglide
W98K := $(SGL)/kernel/win98

MKISO := xorriso -as mkisofs -quiet
# Text files for Windows 98 get CRLF line endings: its COMMAND.COM misreads a batch file with
# LF-only lines ("Bad command or file name"). Safe on files that already have CRLF.
CRLF := sed 's/\r*$$/\r/'
# sgl98.inf from SharedGL lists only the plain ivshmem ID (1af4:1110). vm.sh gives the device
# 3dfx Voodoo2 IDs by default (VOODOO=1, 121a:0002): without this line Windows installs it as
# a generic "PCI standard RAM Controller", sgl98.sys never loads, and 3D programs quit.
SGLINF := sed -e '/^%DeviceDesc%=SglInstall,PCI.VEN_1AF4&DEV_1110/a %VoodooDesc%=SglInstall,PCI\\VEN_121A&DEV_0002' \
  -e '/^DeviceDesc=/a VoodooDesc="SharedGL shared memory device (3dfx Voodoo2 ID)"'
# sort and comm in check-imports must agree on the order; also keeps tool messages in English.
export LC_ALL := C

# The host: Windows (MSYS2) or Linux. Only compiler names, QEMU's build folder and options, and the
# server differ; everything else is the same.
ifneq (,$(filter MINGW% MSYS% CYGWIN%,$(shell uname -s)))
HOST := windows
# Windows 98 is 32-bit, so its files need MSYS2's 32-bit compilers, which have to find their own DLLs first.
CC32  := PATH=/mingw32/bin:/usr/bin gcc
CXX32 := PATH=/mingw32/bin:/usr/bin g++
DDK   := /mingw32/include/ddk
OBJDUMP := objdump
QEMU_BUILD := qemu-11.0.1/build
EXE := .exe
QEMU_CONFIG := --enable-whpx --enable-sdl --enable-opengl --disable-gtk --disable-vnc --disable-spice
SERVER_BIN := $(SGL)/build-win/sglrenderer.exe
else
HOST := linux
# The distribution's i686-w64-mingw32 cross compilers (win32 thread model, see check-cc32).
CC32  := i686-w64-mingw32-gcc
CXX32 := i686-w64-mingw32-g++
DDK   := /usr/i686-w64-mingw32/include/ddk
OBJDUMP := i686-w64-mingw32-objdump
OBJ   := build-98-linux
QEMU_BUILD := qemu-11.0.1/build-linux
EXE :=
QEMU_CONFIG := --enable-kvm --enable-sdl --enable-gtk --enable-opengl
SERVER_BIN := $(SGL)/build-linux/sglrenderer
endif

# What goes on guest.iso is staged here, in this host's build folder: guest/ holds only sources.
CD := $(OBJ)/cd

# pentium2 matches the VM's virtual CPU (-cpu pentium2). It has no SSE, so floating point
# uses the x87 unit, which Windows 98 always saves and restores.
# 0x0410 means "target Windows 98". GCC 16 defaults to C23, which this older code doesn't
# compile as. MSYS2's C library needs printf from the old msvcrt.dll Windows 98 has.
W98FLAGS := -march=pentium2 -mtune=generic -mfpmath=387 -mstackrealign -O2 -s \
            -D_WIN32_WINNT=0x0410 -DWINVER=0x0410 -D__USE_MINGW_ANSI_STDIO=0
CFLAGS98 := -std=gnu17 $(W98FLAGS)

.PHONY: all clean qemu server server-linux opengl32 glide driver programs cd qemouse vmdisp check-qemu check-sharedgl check-openglide check-imports check-cc32

# Each part is built by its own make, timed, and a summary is printed at the end. A part that is
# already up to date takes about 0 s; delete its build folder to time a full build.
# QEMU's ninja uses every CPU core on its own; -j only speeds up the other parts.
COMPONENTS := qemu server opengl32 glide driver programs cd

all:
	@times=; \
	for c in $(COMPONENTS); do \
	  s=$$(date +%s%N); \
	  $(MAKE) --no-print-directory $$c || exit 1; \
	  e=$$(date +%s%N); \
	  times="$$times $$c:$$(( (e - s) / 1000000 ))"; \
	done; \
	echo; \
	echo "Build times ($(HOST), $$(nproc) CPUs, make $(or $(filter -j%,$(MAKEFLAGS)),-j1)):"; \
	total=0; \
	for t in $$times; do \
	  c=$${t%%:*}; ms=$${t#*:}; total=$$((total + ms)); \
	  case $$c in \
	    qemu)     n="QEMU";; \
	    server)   n="SharedGL server";; \
	    opengl32) n="opengl32.dll (SharedGL)";; \
	    glide)    n="glide2x/3x.dll (OpenGLide)";; \
	    driver)   n="sgl98.sys driver";; \
	    programs) n="Windows 98 programs";; \
	    cd)       n="guest.iso";; \
	  esac; \
	  printf '  %-26s built in %5d.%d s\n' "$$n" $$((ms / 1000)) $$((ms % 1000 / 100)); \
	done; \
	printf '  %-26s          %5d.%d s\n' "Total" $$((total / 1000)) $$((total % 1000 / 100))


# Only this host's build folders: a Linux and a Windows build of the same folder don't touch each other.
clean:
	rm -rf $(QEMU_BUILD) $(dir $(SERVER_BIN)) $(OBJ) guest.iso

# ---- Checks that the README's download, clone and patch steps were done ----

check-qemu:
	@test -f qemu-11.0.1/configure || { echo "QEMU's source is missing. Do the download step for QEMU in README.md."; exit 1; }
	@grep -q bar64 qemu-11.0.1/hw/misc/ivshmem-win.c 2>/dev/null || { echo "QEMU isn't patched with this repository's patch. Do the patch step for QEMU in README.md."; exit 1; }
	@grep -q ivshmem-win qemu-11.0.1/hw/misc/meson.build && grep -q QEMU_CLOCK_VIRTUAL qemu-11.0.1/hw/dma/i8257.c || { echo "QEMU's patch is only partly applied. Extract the QEMU tarball again and do the patch step in README.md."; exit 1; }

check-sharedgl:
	@test -d $(SGL)/src || { echo "SharedGL's source is missing. Do the clone step for SharedGL in README.md."; exit 1; }
	@test -f $(W98K)/sgl98.c || { echo "This SharedGL has no Windows 98 support. Clone its windows-support branch (README.md step 1.2)."; exit 1; }
	@grep -q SGL_CMD_SECONDARYCOLORPOINTER $(SGL)/src/server/processor.c || { echo "This SharedGL lacks the Windows 9x fixes. Clone its windows-support branch (README.md step 1.2)."; exit 1; }

# Linux: a cross compiler with the posix thread model makes files that need libwinpthread-1.dll,
# which Windows 98 doesn't have.
check-cc32:
ifeq ($(HOST),linux)
	@$(CC32) -v 2>&1 | grep -q 'Thread model: win32' || { echo "$(CC32) uses the posix thread model. Switch it to win32 (README.md step 1)."; exit 1; }
endif

check-openglide:
	@test -f $(OGL)/grguSstGlide.cpp || { echo "OpenGlide's source is missing. Do the clone step for OpenGlide in README.md."; exit 1; }
	@grep -q BufferEmuInit $(OGL)/grguSstGlide.cpp || { echo "OpenGlide isn't patched. Do the patch step for OpenGlide in README.md."; exit 1; }


# ---- QEMU ----

# Linux: qemu-11.0.1/build-linux; Windows: qemu-11.0.1/build. vm.sh looks for it there.
qemu: check-qemu $(QEMU_BUILD)/build.ninja
	cd $(QEMU_BUILD) && ninja qemu-system-x86_64$(EXE) qemu-img$(EXE)
	$(QEMU_BUILD)/qemu-system-x86_64$(EXE) -device ivshmem-win,help | grep bar64

$(QEMU_BUILD)/build.ninja:
	mkdir -p $(QEMU_BUILD)
	cd $(QEMU_BUILD) && ../configure --target-list=x86_64-softmmu $(QEMU_CONFIG) --disable-werror --disable-docs --disable-capstone --disable-guest-agent


# ---- The server, for the host. The same program as for Windows XP. ----

SERVER_SRC := $(addprefix $(SGL)/src/server/,context.c dynarr.c frameprof.c main.c overlay.c processor.c sgldebug.c) $(SGL)/src/client/scratch.c

# The host's server: build-win/sglrenderer.exe on Windows, build-linux/sglrenderer on Linux.
server: check-sharedgl $(SERVER_BIN)
$(SGL)/build-win/sglrenderer.exe: $(SERVER_SRC)
	mkdir -p $(@D)
	PATH=/ucrt64/bin:/usr/bin gcc -O2 -std=gnu17 -w -DSDL_MAIN_HANDLED -I$(SGL)/inc $(SERVER_SRC) -o $@ -lSDL2 -lepoxy -lws2_32 -lwinmm -liphlpapi

# The same server for Linux hosts (SDL2 and libepoxy from the distribution). server-linux: old name.
server-linux: server
$(SGL)/build-linux/sglrenderer: $(SERVER_SRC)
	mkdir -p $(@D)
	gcc -O2 -std=gnu17 -w -I$(SGL)/inc $(SERVER_SRC) -o $@ -lSDL2 -lepoxy -lm -lpthread -lrt


# ---- opengl32.dll, for Windows 98 ----

# SGL_XP: the client is opengl32.dll itself, as on XP. SGL_WIN98: the Windows 98 differences.
CLIENT_DEFS := -DSGL_XP -DSGL_WIN98 -DSGL_NO_NETWORK
CLIENT_OBJ  := $(addprefix $(OBJ)/,winmain.o pb.o spinlock.o glimpl.o scratch.o windrv.o)
CLIENT_DEP  := $(wildcard $(SGL)/inc/client/*.h) $(SGL)/inc/sglprof.h $(SGL)/src/client/platform/xpwgl.inl

opengl32: check-cc32 check-sharedgl $(CD)/opengl32.dll

$(CD)/opengl32.dll: $(CLIENT_OBJ)
	mkdir -p $(@D)
	$(CC32) -shared -s -o $@ $^ -Wl,--kill-at -Wl,--export-all-symbols -static-libgcc -lgdi32 -luser32 -lwinmm

# GL functions must be stdcall, and -mrtd does that for the whole file. It would also make GCC
# treat its own fprintf and friends as stdcall, which corrupts the stack, so those are turned off.
$(OBJ)/glimpl.o: EXTRA := -mrtd -fno-builtin-fprintf -fno-builtin-printf -fno-builtin-fputs -fno-builtin-fputc -fno-builtin-puts -fno-builtin-putchar

$(OBJ)/%.o: $(SGL)/src/client/%.c $(CLIENT_DEP)
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -I$(SGL)/inc -w $(CLIENT_DEFS) $(EXTRA) -c $< -o $@

$(OBJ)/windrv.o: $(SGL)/src/client/platform/windrv.c $(CLIENT_DEP)
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -I$(SGL)/inc -w $(CLIENT_DEFS) -c $< -o $@


# ---- glide2x.dll and glide3x.dll, for Windows 98 ----

GLIDE_SRC := grguDepth.cpp grguMisc.cpp grgu3df.cpp grguDraw.cpp grguSstGlide.cpp grguFog.cpp grguTex.cpp \
             grguLfb.cpp GLRender.cpp OGLFogTables.cpp OGLTextureTables.cpp OGLColorAlphaTables.cpp TexDB.cpp \
             PGUTexture.cpp Glide.cpp GLExtensions.cpp PGTexture.cpp FormatConversion.cpp grguBuffer.cpp \
             grguColorAlpha.cpp GLutil.cpp gsplash.cpp lfbtrace.cpp \
             platform/windows/clock.cpp platform/windows/error.cpp platform/windows/openglext.cpp \
             platform/windows/library.cpp platform/windows/window.cpp
GLIDE_OBJ := $(addprefix $(OBJ)/glide/,$(GLIDE_SRC:.cpp=.o))

glide: check-cc32 check-openglide $(CD)/glide2x.dll $(CD)/glide3x.dll

# glide3x.dll: the same OpenGlide plus grglide3.cpp, which translates the Glide 3 functions that
# changed (vertex layouts, log2 LODs, grGet, ...). Glide3x.def exports the unchanged ones directly.
$(CD)/glide3x.dll: $(GLIDE_OBJ) $(OBJ)/glide/grglide3.o $(OBJ)/w98compat.o $(OGL)/Glide3x.def
	mkdir -p $(@D)
	$(CXX32) -shared -s -o $@ $(GLIDE_OBJ) $(OBJ)/glide/grglide3.o $(OBJ)/w98compat.o $(OGL)/Glide3x.def -static -lopengl32 -lgdi32 -luser32 -lwinmm

# Glide2x.def gives the decorated names (_grGlideInit@0) that games import.
# Linked against MSYS2's opengl32 import library: the names are the same, and at run time
# Windows finds SharedGL's opengl32.dll next to the game first. check-imports makes sure
# that DLL has everything this one needs.
# -static: the C++ runtime and its thread library go inside, since Windows 98 has neither DLL.
$(CD)/glide2x.dll: $(GLIDE_OBJ) $(OBJ)/w98compat.o $(OGL)/Glide2x.def
	mkdir -p $(@D)
	$(CXX32) -shared -s -o $@ $(GLIDE_OBJ) $(OBJ)/w98compat.o $(OGL)/Glide2x.def -static -lopengl32 -lgdi32 -luser32 -lwinmm

$(OBJ)/w98compat.o: guest/w98compat.c
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -c $< -o $@

# C_USE_SDL stays undefined: platform/windows is the Win32 code. HAVE_MMX stays undefined:
# the C paths are used, and the GCC MMX paths have known bugs.
$(OBJ)/glide/%.o: $(OGL)/%.cpp $(wildcard $(OGL)/*.h)
	mkdir -p $(@D)
	$(CXX32) $(W98FLAGS) -std=gnu++11 -w -fpermissive -DWIN32 -D__WIN32__ -I$(OGL) -I$(OGL)/platform/windows -c $< -o $@

# Windows refuses to load a program whose imports are missing, with no useful message.
# So: every function glide2x.dll takes from opengl32.dll must exist in SharedGL's; and no
# Windows 98 file may need a DLL Windows 98 lacks, or a function only later Windows has.
W98_DLLS := kernel32.dll user32.dll gdi32.dll advapi32.dll msvcrt.dll winmm.dll opengl32.dll ntoskrnl.exe hal.dll
W98_LACKS := IsProcessorFeaturePresent AddVectoredExceptionHandler RemoveVectoredExceptionHandler              GetModuleHandleExA GetModuleHandleExW InitializeCriticalSectionAndSpinCount              SetupDiGetClassDevsA SetupDiGetClassDevsW GetTickCount64 FlsAlloc InterlockedCompareExchange64

check-imports: $(CD)/glide2x.dll $(CD)/glide3x.dll $(CD)/opengl32.dll $(CD)/sgl98.sys $(CD)/INSTALL.EXE $(CD)/SGLDIAG.EXE $(CD)/GLIDETST.EXE $(CD)/GLIDE3TS.EXE $(CD)/SGLGEARS.EXE $(CD)/CLOCKTST.EXE $(CD)/SETUP/FINISH.EXE
	@for f in $^; do 	  $(OBJDUMP) -p $$f | awk '/DLL Name:/{print tolower($$3)}' | while read d; do 	    case " $(W98_DLLS) " in *" $$d "*) ;; *) echo "$$f needs $$d, which Windows 98 doesn't have"; exit 1;; esac; 	  done || exit 1; 	  for fn in $(W98_LACKS); do 	    if $(OBJDUMP) -p $$f | grep -qw "$$fn"; then echo "$$f imports $$fn, which Windows 98 doesn't have"; exit 1; fi; 	  done; 	done
	@$(OBJDUMP) -p $(CD)/glide2x.dll | awk '/DLL Name:/{d=tolower($$3)} d=="opengl32.dll" && /^\t[0-9a-f]+ +<none> +[0-9a-f]+ /{print $$4}' | sort -u > $(OBJ)/glide-needs.txt
	@$(OBJDUMP) -p $(CD)/opengl32.dll | awk '/\[ *[0-9]+\] /{print $$NF}' | sort -u > $(OBJ)/opengl32-has.txt
	@missing=$$(comm -23 $(OBJ)/glide-needs.txt $(OBJ)/opengl32-has.txt); \
	  if [ -n "$$missing" ]; then echo "SharedGL's opengl32.dll lacks: $$missing"; exit 1; fi
	@echo "glide2x.dll's $$(wc -l < $(OBJ)/glide-needs.txt) OpenGL imports are all in opengl32.dll"


# ---- The kernel driver, for Windows 98 ----

driver: check-cc32 check-sharedgl $(CD)/sgl98.sys $(CD)/sgl98.inf

# A WDM driver for NTKERN: no C library or start-up code. Every import must be one that
# Windows 98's NTKERN provides; the driver defines its own memcpy and memset for that reason.
$(CD)/sgl98.sys: $(W98K)/sgl98.c
	mkdir -p $(@D)
	$(CC32) -std=gnu17 -O2 -s -march=pentium2 -w -ffreestanding -fno-tree-loop-distribute-patterns -fno-stack-protector -fno-stack-check \
	  -fno-aggressive-loop-optimizations -fno-asynchronous-unwind-tables -D_X86_=1 -I$(DDK) \
	  -shared -nostdlib -nostartfiles -o $@ $< \
	  -Wl,--subsystem,native:4.0 -Wl,--major-os-version,4,--minor-os-version,10 -Wl,--entry,_DriverEntry@8 \
	  -Wl,--enable-reloc-section -Wl,--image-base,0x10000 -Wl,--disable-nxcompat -Wl,--disable-dynamicbase \
	  -lntoskrnl -lhal

$(CD)/sgl98.inf: $(W98K)/sgl98.inf
	mkdir -p $(@D)
	$(SGLINF) $< | $(CRLF) > $@


# ---- The installer and test programs, for Windows 98 ----

programs: check-cc32 $(CD)/INSTALL.EXE $(CD)/SGLDIAG.EXE $(CD)/GLIDETST.EXE $(CD)/GLIDE3TS.EXE $(CD)/SGLGEARS.EXE $(CD)/CLOCKTST.EXE $(CD)/SETUP/FINISH.EXE

$(CD)/INSTALL.EXE: guest/install98.c
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -o $@ $< -static-libgcc

$(CD)/SGLDIAG.EXE: guest/sgldiag98.c
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -o $@ $< -static-libgcc

$(CD)/GLIDETST.EXE: guest/glidetest.c
	mkdir -p $(@D)
	$(CXX32) $(W98FLAGS) -x c++ -I$(OGL) -o $@ $< -luser32 -lm -static-libgcc -static-libstdc++

$(CD)/GLIDE3TS.EXE: guest/glide3test.c
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -o $@ $< -luser32 -static-libgcc

$(CD)/CLOCKTST.EXE: guest/clocktest.c
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -o $@ $< -lwinmm -static-libgcc

# FINISH.EXE: second half of E:\SETUP.BAT (DMA, True Color), see guest/finish98.c.
$(CD)/SETUP/FINISH.EXE: guest/finish98.c
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -mwindows -o $@ $< -ladvapi32 -luser32 -static-libgcc

$(CD)/SGLGEARS.EXE: guest/sglgears.c
	mkdir -p $(@D)
	$(CC32) $(CFLAGS98) -o $@ $< -lopengl32 -lgdi32 -luser32 -lm -static-libgcc


# ---- The CD image ----

# QEMouse: absolute mouse driver for Windows 98 (QEMU vmport), the release unpacked in README.md step 1.2.
qemouse:
	@test -f guest/qemouse/qemouse.drv || { echo "QEMouse is missing: download and unpack qemouse.zip into guest/qemouse (README.md step 1.2)."; exit 1; }
	mkdir -p $(CD)/QEMOUSE
	cp guest/qemouse/qemouse.drv $(CD)/QEMOUSE/QEMOUSE.DRV
	$(CRLF) guest/qemouse/qemouse.inf > $(CD)/QEMOUSE/QEMOUSE.INF

# vmdisp9x: Windows 98 driver for QEMU's standard VGA (-vga std), the release unpacked in README.md step 1.2.
vmdisp:
	@test -f guest/vmdisp9x/qemumini.drv || { echo "vmdisp9x is missing: download and unpack its 2D driver ZIP into guest/vmdisp9x (README.md step 1.2)."; exit 1; }
	mkdir -p $(CD)/VMDISP
	cp guest/vmdisp9x/* $(CD)/VMDISP/

# 8.3 names in capitals: Windows 98's CD driver shows Joliet long names, but its
# command prompt and the hardware wizard are happier with short ones.
# SETUP.BAT + SETUP\: one-step driver setup of a fresh Windows 98 (README step 3.2), see
# guest/setup/SETUP.BAT. Its INF copies have no CopyFiles lines: SETUP.BAT puts the driver
# files in place itself, because Windows, finding an INF through DevicePath, asks for its
# files on the Windows CD instead of looking next to the INF.
cd: opengl32 glide check-imports driver programs qemouse vmdisp
	$(CRLF) guest/setup/SETUP.BAT > $(CD)/SETUP.BAT
	mkdir -p $(CD)/SETUP
	$(CRLF) guest/setup/SETUP98.REG > $(CD)/SETUP/SETUP98.REG
	sed '/^[Cc]opy[Ff]iles *=/d' guest/vmdisp9x/vmdisp9x.inf | $(CRLF) > $(CD)/SETUP/VMDISP9X.INF
	$(SGLINF) $(W98K)/sgl98.inf | sed '/^[Cc]opy[Ff]iles *=/d' | $(CRLF) > $(CD)/SETUP/SGL98.INF
	$(MKISO) -J -r -V SGL98 -o guest.iso $(CD)
	@echo guest.iso contains: && ls $(CD)
