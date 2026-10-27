# Debugger

An ncurses debugger that runs **inside the Verilog simulation**. It stops the real Arlet 65C02 RTL at instruction boundaries. You can set breakpoints, step, look at registers and MMU state, dump memory the way the CPU sees it, and disassemble 65C02 code, while the MMU, disk, ACIA, GPU stream and the SDL monitor keep behaving exactly as in a normal run.

The debugger (commands, UI, breakpoints, disassembler, symbol loader) is the BB6502 author's debugger from the earlier fake6502-based emulator. It was ported to the Verilog system as a VPI module; the changes are listed at the top of `rtl/dbg/debugger.c`.

## Running

```bash
make run-dbg
```

This builds everything plus `build/sim_dbg.vvp` and `build/bbdbg.vpi`, starts the SDL monitor, and runs:

```bash
vvp -M build -m bbdbg build/sim_dbg.vvp +dbg_sym=build/boot.dbg +dbg_sym=build/kernel.dbg +dbg_sym=build/hello.dbg > build/sim_dbg.log
```

The debugger draws on your terminal (`/dev/tty`), and vvp's own messages go to `build/sim_dbg.log`. To load more symbol files or pick a source file:

```bash
make run-dbg DBG_ARGS="+dbg_sym=build/disktest.dbg"
```

## Screen

```
┌ terminal pane ───────────────┐┌ source pane ─────────────┐
│ ACIA output (what the CPU    ││ (not implemented yet)    │
│ writes to $8000)             ││                          │
└──────────────────────────────┘└──────────────────────────┘
┌ console ──────────────────────────────────────────────────┐
│ messages, disassembly, memory dumps                       │
│ >> your commands                                          │
└───────────────────────────────────────────────────────────┘
```

The layout is computed once at start-up, so size the terminal first (about 100×40 or larger).

## Commands

| Command | Aliases | Action |
|---|---|---|
| `b [addr\|symbol]` | `bp`, `break`, `breakpoint` | Set a breakpoint at the current instruction, at `0x…`, or at a symbol (`b _main`) |
| `rb <addr\|symbol>` | `rbp`, `rmb`, `rmbp`, `remb`, `rembp`, `remove`, `removebp` | Remove the breakpoint(s) at that address |
| `l` | `ls`, `list`, `lbp`, `listbp` | List breakpoints with their disassembly |
| `c` | `cont`, `continue` | Run until a breakpoint, STP, or **Ctrl-C** |
| `s [n]` | `step` | Execute 1 or *n* instructions, printing each. Stops early at a breakpoint. |
| `d [n]` | `dis`, `disas`, `disassemble` | Disassemble 5 or *n* instructions from the PC |
| `m [start] [end]` | `mem`, `memory` | Hex dump; prompts for missing addresses. Accepts `0x…`. |
| `r` | `reg`, `regis`, `register`, `registers` | PC, SP, A, X, Y, status; decoded flags; MMU mode and page table |
| `reset` | `rst` | Reset the machine (16-cycle reset pulse) and stop at the first instruction |
| `ld` | `lds`, `load`, `ldsrc` | Source view: not implemented yet |
| `h` | `help` | Help |
| `q` | `quit`, `exit` | End the simulation |

At start-up the CPU is stopped before its first instruction, `8105 SEI` in the boot ROM.

### Input to the 6502

While running (`c`), keys typed in the terminal are sent to the 6502's keyboard input. They're appended to `/tmp/bb6502_in`, just like the SDL window does it: Enter → `\r`, Backspace → `$08`. **Ctrl-C** stops execution instead of being sent. The SDL window keeps working as a keyboard too.

### STP: "Program exited"

When the CPU is about to execute `STP` (`$DB`), the debugger asks `Program exited (STP at …). Restart/Exit? [r/E]`:
- `r` resets the machine and stops at the first instruction.
- Anything else ends the simulation.

The BB6502 software doesn't execute `STP` yet. Making `sys_exit` end with `STP` would hook into this.

## What you see, exactly

- **Instruction boundaries.** The debugger runs at every opcode fetch (the cycle with `sync` high). Registers are sampled half a cycle later, after the previous instruction's register write-back has landed. So `r` shows the state just before the instruction at `PC` executes. After `reset; s 4` (`SEI CLD LDX #$FF TXS`), `r` shows `SP=ff X=ff`.
- **Registers** come from Arlet's register file: `regs[2]` = A, `[0]` = X, `[1]` = Y, `[3]` = S. Flags come from `P`. The PC is the fetch address. Stopped inside `disktest`, `r` looks like this. Each `PPN` group lists the physical page for 8 consecutive 1 KB virtual pages:
  ```
  PC=1050 SP=fb A=90 X=11 Y=00 status=21
  flags=..-....C  MMU=user
  PPN [ 0.. 7] 20 21 22 23 24 25 26 27  [ 8..15] 28 29 30 31  0  1  2  3  [16..23] ...
  ```
- **Memory** is shown through the MMU's current state, the same way the CPU sees it:
  - **`$0000-$7FFF`:** in kernel mode, physical = virtual. In user mode it goes through `ppn[VA[14:10]]` (1 KB pages). Stopping inside a process therefore shows *that process's* memory: `m 0x1000 0x1005` shows its BBX header.
  - **`$8000-$80FF`** is shown as `..`. Reading a device register can change it (reading the ACIA clears RX-valid), so the debugger never touches the I/O window.
  - **`$8100-$FFFF`** is the boot ROM.
- **Disassembly** covers the full WDC 65C02 instruction set. `BRK` is shown as `BRK #$nn`, because on BB6502 the byte after it is the syscall number.
- **MMU faults** are printed in the console as `[mmu] FAULT AB=… WE=… paddr=… (pc …)`.
- **Symbols** are labels from ld65 `--dbgfile` output. All-caps names are skipped, treated as hardware equates. If two files define the same name (both the kernel and `hello` have `_main`), `b` uses the first file loaded.

## How it works

```
rtl/tb.v (built with -DBBDBG)                rtl/dbg/bbdbg_vpi.c          rtl/dbg/debugger.c
──────────────────────────────               ───────────────────          ──────────────────
posedge: sync → latch dbg_pc, dbg_op
negedge: $bbdbg_fetch(dbg_pc, dbg_op) ──────► fetchCalltf ───────────────► dbgOnFetch
                                                                           stop? → command loop
                                                                           (sim time frozen
                                                                            until you resume)
ACIA write: $bbdbg_tx(DO) ──────────────────► txCalltf ──────────────────► dbgOnTx → terminal pane
MMU fault:  $bbdbg_fault(AB, WE, paddr) ────► faultCalltf ───────────────► dbgOnFault
reg dbg_reset_req ◄── vpi_put_value ◄──────── simRequestReset ◄─────────── `reset`, STP restart
tb.ram, tb.rom, tb.dut.regfile.regs, ◄─────── simReadMem, simGetRegs ◄──── m, d, r
tb.dut.P, tb.mmu.kernel, tb.mmu.ppn
```

- **The normal build is unaffected.** Everything in `tb.v` is under `` `ifdef BBDBG `` (the normal build keeps `$write` for the ACIA and `$display` for faults), so `build/sim.vvp` is logically identical to a build without the debugger.
- **Pausing freezes the whole machine.** The debugger stops by not returning from `$bbdbg_fetch`. Nothing in the simulation advances while you're at the prompt, devices included. The SDL monitor is a separate process, so it stays responsive and keeps showing the last output.
- **Ctrl-C arrives as a key.** ncurses is opened with `newterm` on `/dev/tty` in raw mode, so Ctrl-C reaches the debugger as a key press instead of a signal that would stop vvp. While running, the terminal is polled every 512 instructions.

## Limitations

- **Breakpoints match the virtual PC, not a process.** Every user program is linked at `$1000`, so a breakpoint in one program's code also triggers in another program at the same address.
- **No memory or register writes.**
- **The source pane is empty** (`+dbg_src=` / `ld` are placeholders, as `-s` / `ld` were in the original debugger).
- **The SDL window only updates when the CPU writes to the GPU port.** While stopped, it shows the last output.
- **Debug runs can be slower** than `make run`, because the testbench calls into the VPI module once per instruction.
