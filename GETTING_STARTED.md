# Getting started with BB6502

This guide assumes you know nothing about this project, and not much about Verilog or the 6502 either. Follow it top to bottom.

**What you're about to run:** a simulated computer. Icarus Verilog simulates the actual chips (CPU, memory controller, devices) clock cycle by clock cycle. On top of that runs an operating system written for it. A small window shows the computer's screen.

Tested on **macOS** (Apple Silicon, Homebrew). Linux should work with the notes in [Linux](#linux). Windows is not supported, because the run scripts use Unix named pipes.

---

## 1. Install the tools

### 1.1 Command-line developer tools

Open the **Terminal** app and run:

```bash
xcode-select --install
```

A dialog appears; click *Install*. If it says the tools are already installed, that's fine. This gives you `git`, `make`, a C compiler, `python3` and the `ncurses` library.

### 1.2 Homebrew

[Homebrew](https://brew.sh) installs the remaining tools. If `brew --version` already prints a version, skip this step. Otherwise, follow the install instructions on <https://brew.sh>, then close and reopen the Terminal.

### 1.3 Project tools

```bash
brew install icarus-verilog cc65 sdl2 sdl2_ttf mtools pkg-config
```

| Tool | Why it's needed |
|---|---|
| `icarus-verilog` | `iverilog` compiles the hardware description; `vvp` runs it; `iverilog-vpi` builds the debugger |
| `cc65` | C compiler (`cc65`), assembler (`ca65`) and linker (`ld65`) for the 6502 |
| `sdl2`, `sdl2_ttf` | The monitor window and its font rendering |
| `mtools` | `mformat`/`mcopy`, which create the FAT-formatted disk image |
| `pkg-config` | Lets the build find SDL |

Check that everything is there. Each command should print a version or a path:

```bash
iverilog -V 2>&1 | head -1; cc65 --version; sdl2-config --version; which mformat
```

---

## 2. Get the code

```bash
cd ~/Documents
```

```bash
git clone --recurse-submodules https://github.com/swarneel123bh-ux/BB6502_Verilog.git
```

```bash
cd BB6502_Verilog
```

`--recurse-submodules` also downloads the CPU core into `rtl/verilog-65C02-microcode`. If you forgot it, run:

```bash
git submodule update --init
```

You can check the CPU core is present: `ls rtl/verilog-65C02-microcode/generic` should list `cpu.v` and other files.

---

## 3. Build

```bash
make
```

This compiles the hardware (`build/sim.vvp`), the monitor window (`build/gpu`), the boot ROM, the kernel and the demo programs. It then packs everything into a disk image (`build/disk.img`). It takes about a second.

The output includes some warnings. These are expected and harmless:
- `no explicit time unit` (Verilog)
- `Calling system function $fseek() as a task` (shown when the sim starts)
- `Segment 'VECTORS' does not exist` (linker)

`make` should end with lines like `Disk test      -> LBA 220` and no `Error`.

---

## 4. Run

```bash
make run
```

A window titled **BB6502 monitor** opens. Within a few seconds you should see:

```
BB6502 boot ROM
Loading kernel
Jumping to Kernel
FAT boot signature OK
Loading hello.c
Loading hello2.c
Loading disktest.c
Staring scheduler...
Proc1:0
    Proc2:0
        disktest: ret=00 sig=55 AA PASS
Proc1:1
    Proc2:1
...
```

Here's what that means:
1. The CPU starts in the boot ROM, which reads the kernel from the disk image and jumps to it.
2. The kernel loads three programs and starts them as separate **processes**.
3. `hello` and `hello2` each print a line and then *yield*, letting the next process run. This is cooperative multitasking.
4. `disktest` reads the disk's first sector through a syscall once, checks its `55 AA` signature, prints `PASS`, and from then on only yields.

The same text also appears in the Terminal, through the simulated serial port.

**To stop:** close the window, or press **Ctrl-C** in the Terminal.

The simulation runs every clock cycle of every chip, so it is much slower than a real 65C02. Several lines per second is normal.

---

## 5. Run it under the debugger

```bash
make run-dbg
```

The monitor window opens as before, and the Terminal turns into the debugger. It needs a reasonably large Terminal window (about 100×40 or more).

```
┌ terminal pane: serial output ┐┌ source pane (empty) ┐
└──────────────────────────────┘└─────────────────────┘
┌ console ─────────────────────────────────────────────┐
│Loaded 75 symbols total                               │
│Stopped before the first instruction. Type h for help.│
│        8105    SEI                                   │
│>>                                                    │
└──────────────────────────────────────────────────────┘
```

The CPU is frozen before its first instruction. Try this:

| Type | What happens |
|---|---|
| `s 4` | Executes 4 instructions, printing each one |
| `r` | Shows the registers (A, X, Y, SP, flags), the MMU mode and the 32-entry page table |
| `b _main` | Sets a breakpoint at the kernel's `main` function |
| `c` | Runs until the breakpoint. This takes a few seconds while the boot ROM loads the kernel. |
| `d 10` | Disassembles the next 10 instructions |
| `m 0x0200 0x021f` | Dumps memory; `$0200` is where the kernel was loaded (it starts with `42 58` = "BX") |
| `c`, then **Ctrl-C** | Runs freely, then stops again |
| `q` | Quits |

The full reference is in [docs/debugger.md](docs/debugger.md).

---

## 6. Write your first program

Programs are C files compiled with cc65. They run as processes and talk to the kernel through syscalls. The library is `sw/prog/src/include/syslib.h`:

| Function | What it does |
|---|---|
| `sys_putc(c)` | Prints one character |
| `sys_puts(s)` | Prints a string |
| `sys_yield()` | Lets the other processes run |
| `sys_getc()` | Waits for a key (typed in the monitor window) and returns it |
| `sys_block_read(lba, buf)` / `sys_block_write(lba, buf)` | Reads or writes one 512-byte disk sector |
| `sys_exit(code)` | Currently halts the machine |

The kernel doesn't yet load programs by name, so adding one means editing a few files. The project already does this once for `disktest` (`sw/prog/src/disktest.c`, the `PROG3_*` lines); use it as a working reference.

Example: a process called `count` that takes **`disktest`'s place**. Until the kernel has a page allocator, `spawn_bbx` hands out memory in fixed 4 KB blocks. Each process uses blocks `base` and `base + 1`, and they're all taken right now: the kernel 0 and 7, hello 1–2, hello2 3–4, disktest 5–6. So a new program has to replace one.

**1. Write the program**: `sw/prog/src/count.c`

```c
#include "include/syslib.h"

int main(void) {
  char c = 'a';
  while (1) {
    sys_puts("        count:");
    sys_putc(c);
    sys_puts("\r\n");
    c = (c == 'z') ? 'a' : c + 1;
    sys_yield();          // always yield, or the other processes never run
  }
  return 0;
}
```

**2. Give it a file name and a disk location** in `common.mk`, next to `PROG3_*`:

```make
PROG4_LBA := 230
PROG4_BBX := $(BUILD_DIR)/count.bbx
```

**3. Teach `sw/prog/prog.mk` to build it.** Add the object list, add it to `all`, and add a link rule:

```make
COUNT_OBJS  := $(PROG_COMMON) $(BUILD_DIR)/prog_count.o

all: $(PROG_BBX) $(PROG2_BBX) $(PROG3_BBX) $(PROG4_BBX)

$(PROG4_BBX): $(COUNT_OBJS) $(PROG_CFG)
	$(LD65) -C $(PROG_CFG) $(LD65_PROG_FLAGS) -o $@ $(COUNT_OBJS) none.lib
```

The recipe line must start with a **tab**, not spaces. Keep `$(LD65_PROG_FLAGS)`: it tells `prog.cfg` where the syscall area is (see [docs/syscalls.md](docs/syscalls.md#syscall-abi)).

**4. Put it on the disk.** In the root `Makefile`, in the `$(DISK_IMG)` rule, add after the disktest line:

```make
	@dd if=$(PROG4_BBX) of=$@ bs=512 seek=$(PROG4_LBA) conv=notrunc status=none
```

**5. Start it.** In `sw/kernel/src/main.c`, replace the `disktest` line `spawn_bbx(220, 1, 5);` with:

```c
  spawn_bbx(230, 1, 5);    // count.c at lba 230, physical pages from 5
```

The arguments are: disk sector, number of sectors to load (1 is enough while `build/count.bbx` is at most 512 bytes; the demos are 240–400), and `base`, the first 4 KB block. 5 is the base `disktest` used; the demos use 1 and 3. At most 4 processes are supported.

**6. Rebuild and run:**

```bash
make && make run
```

You should now see `count` interleaved with `hello` and `hello2`, in place of the `disktest` line.

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `make: iverilog: No such file or directory` (or `cc65`, `mformat`) | Step 1.3 didn't finish. Re-run the `brew install` line. |
| `rtl/verilog-65C02-microcode/generic/*.v: No such file` | The CPU core submodule is missing: `git submodule update --init`. |
| The window opens but stays black, or the simulation seems frozen | Make sure `/tmp/bb6502_in` is a regular file, not a FIFO (`ls -l /tmp/bb6502_in` must not start with `p`). `make run` recreates it correctly; if you start `vvp` by hand, run `rm -f /tmp/bb6502_in && touch /tmp/bb6502_in` first. |
| `[acia] TX overrun` lines | Code wrote `$8000` without waiting for TX ready (bit 1 of `$8001`). See [docs/hardware.md](docs/hardware.md#acia-serial-port). |
| `TTF_OpenFont(...)` error | The default font is macOS's Menlo. Start the window yourself with a font path: `build/gpu /path/to/font.ttf`. |
| `[tb] FIFO open failed` | Stale files in `/tmp`: `rm -f /tmp/bb6502_gpu /tmp/bb6502_in`, then run again. |
| `[mmu] FAULT AB=... ` lines | A program touched memory the MMU doesn't allow. The fault becomes an NMI, which the boot ROM currently ignores. |
| `make run-dbg` returns at once | Look at `build/sim_dbg.log` for the reason (for example, `cannot open /dev/tty` if not run from a real terminal). |
| The debugger screen looks garbled | Make the Terminal window bigger before starting; the layout is fixed at start-up. |
| Very slow | Expected: it's a cycle-accurate hardware simulation. |

## Linux

Package names on Debian/Ubuntu:

```bash
sudo apt install iverilog cc65 libsdl2-dev libsdl2-ttf-dev mtools pkg-config libncurses-dev python3 bsdextrautils
```

`bsdextrautils` provides `hexdump`. Start the monitor with a font that exists on your system: edit the `$(GPU_BIN)` lines in the root `Makefile` to pass a `.ttf` path. This path is untested.
