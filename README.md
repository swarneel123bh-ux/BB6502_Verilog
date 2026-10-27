# BB6502_Verilog

A 65C02 computer simulated at the hardware level, with its own operating system and a debugger.

- **Hardware (Verilog, Icarus Verilog):**
  - Arlet Ottens' 65C02 core (with a small `VPB` addition)
  - a custom **MMU** (8 × 4 KB pages, kernel/user modes, faults → NMI)
  - 32 KB RAM and a 32 KB boot ROM
  - a serial port (ACIA), a text "GPU" stream, and a 512-byte-sector disk controller
- **Software (cc65 C + ca65 assembly):**
  - a boot ROM that loads the kernel from disk
  - a kernel with **processes**, **cooperative multitasking** (`yield`), **BRK-based syscalls** and a loader for `.bbx` executables
  - two demo programs that run side by side
- **Tools:**
  - an SDL "monitor" window
  - an **ncurses debugger** that runs inside the simulator as a VPI module and controls the real RTL CPU: breakpoints, stepping, registers, MMU-aware memory dumps, 65C02 disassembly

```
 ┌─────────────── vvp (Icarus Verilog) ───────────────┐      ┌──────────────┐
 │  65C02 core ── MMU ── RAM 32K / ROM 32K            │◄────►│ gpu (SDL)    │
 │       │                                            │ FIFO │ monitor +    │
 │       └── I/O: ACIA · GPU stream · disk controller │      │ keyboard     │
 │                         (debug build: bbdbg.vpi)   │      └──────────────┘
 └──────────────────────────┬─────────────────────────┘
                            └── build/disk.img: boot record · kernel.bbx · programs
```

## Quick start

New to all of this? Read **[GETTING_STARTED.md](GETTING_STARTED.md)**. It goes from an empty Mac to a running machine.

```bash
git clone --recurse-submodules https://github.com/swarneel123bh-ux/BB6502_Verilog.git
```

```bash
cd BB6502_Verilog && make run
```

An SDL window opens showing the boot messages, followed by the two demo processes taking turns:

```
BB6502 boot ROM
Loading kernel
Jumping to Kernel
FAT boot signature OK
...
Proc1:0
    Proc2:0
Proc1:1
```

To run under the debugger:

```bash
make run-dbg
```

## Documentation

| Doc | Contents |
|---|---|
| [GETTING_STARTED.md](GETTING_STARTED.md) | Install, build, run, debug, write your first program, troubleshooting |
| [docs/architecture.md](docs/architecture.md) | How the pieces fit, boot sequence, repository layout |
| [docs/memory-map.md](docs/memory-map.md) | CPU address space, physical RAM layout, disk layout |
| [docs/hardware.md](docs/hardware.md) | Every I/O register, the MMU, the testbench model |
| [docs/syscalls.md](docs/syscalls.md) | Syscall ABI, syscall list, BBX executable format, boot record |
| [docs/processes.md](docs/processes.md) | Process table, loader, scheduler, context switch |
| [docs/build-system.md](docs/build-system.md) | Makefiles, linker configs, how the disk image is made |
| [docs/debugger.md](docs/debugger.md) | Using the debugger and how it is wired into the simulation |

## Credits

- 65C02 core: [Arlet Ottens, verilog-65C02-microcode](https://github.com/Arlet/verilog-65C02-microcode). This project uses a [fork](https://github.com/swarneel123bh-ux/verilog-65C02-microcode/tree/bb6502) that adds a `VPB` output and a project-relative microcode path.
- Everything else, including the MMU, testbench, OS, tools and debugger, is part of the BB6502 project.
