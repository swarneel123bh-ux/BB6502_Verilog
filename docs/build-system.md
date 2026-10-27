# Build system

## Makefiles

| File | Builds |
|---|---|
| `Makefile` | Entry point: `all`, `run`, `debug`, `run-dbg`, `clean`, and the disk image |
| `common.mk` | Shared settings: tool names, flags, disk LBAs, output file names. Included by every makefile. |
| `rtl/rtl.mk` | `sim` → `build/sim.vvp`, `gpu` → `build/gpu`, `dbg` → `build/sim_dbg.vvp` + `build/bbdbg.vpi` |
| `sw/kernel/kernel.mk` | Kernel → `build/kernel.bbx`, boot ROM → `build/bootrom.bin/.hex`, boot record → `build/bootrec.bin` |
| `sw/prog/prog.mk` | User programs → `build/hello.bbx`, `build/hello2.bbx` |

Everything goes to `build/`, which is git-ignored.

## Pipeline

```
sw/kernel/src/*.c ─cc65─► build/*.s ─ca65─► build/*.o ┐
sw/kernel/src/*.s ─────────────────ca65─► build/*.o ──┴─ld65 kernel.cfg─► kernel.bbx (+ kernel.map, kernel.dbg)
sw/boot/boot.s ────────────────────ca65─► boot.o ─────ld65 boot.cfg─► bootrom.bin ─hexdump─► bootrom.hex
kernel.bbx size ─mkbootrec.py─► bootrec.bin
sw/prog/src/*.c,*.s ─cc65/ca65─► prog_*.o ─ld65 prog.cfg─► hello.bbx, hello2.bbx (+ .dbg)

dd 1.44 MB zeros ─mformat -F─► FAT32 ─mcopy disk/*─► ─dd bootrec @100, kernel @101, hello @200, hello2 @210─► disk.img

rtl/verilog-65C02-microcode/generic/*.v + rtl/tb.v + rtl/mmu6502.v ─iverilog─► sim.vvp
                                              same + -DBBDBG ─iverilog─► sim_dbg.vvp
rtl/dbg/*.c ─iverilog-vpi (-lncurses)─► bbdbg.vpi
tools/gpu.c ─cc (SDL2, SDL2_ttf)─► gpu
```

## Flags

- `cc65 -Oir --cpu 65c02 -g`: optimize, inline, register variables; 65C02 instructions; debug info.
- `ca65 --cpu 65c02 -g`
- `-g` and `ld65 --dbgfile` only produce the `build/*.dbg` symbol files the debugger loads. **The binaries are byte-identical with or without them.**
- Linking uses `none.lib` (cc65's runtime with no target system).

## Linker configs

| Config | Places |
|---|---|
| `sw/boot/boot.cfg` | ROM from `$8100` (NOP-filled) and vectors at `$FFF8-$FFFF` |
| `sw/kernel/kernel.cfg` | Zero page `$00-$1F`, BBX header at `$0200`, everything else at `$0206-$0FFF`. **The kernel must fit in its 4 KB page**; the area is filled, so `kernel.bbx` is always 3584 bytes. |
| `sw/prog/prog.cfg` | Zero page `$30-$4F`, header at `$1000`, program from `$1006` |

## Disk LBAs

Set in `common.mk`:

| Variable | Value |
|---|---|
| `BOOT_REC_LBA` | 100 |
| `KERNEL_LBA` | 101 |
| `PROG_LBA` | 200 |
| `PROG2_LBA` | 210 |

The boot ROM hardcodes LBA 100 (`BOOT_REC_LBA` in `boot.s`). The program LBAs are also hardcoded in `sw/kernel/src/main.c`. Keep all three in sync.

## Gotchas

- Object rules don't depend on `common.mk`. After changing a flag, run `make clean`.
- `vvp` must be started from the project root: `tb.v` and `microcode.v` open files by relative path.
- `make run`, `make run-dbg` and `make gpu` create the FIFO `/tmp/bb6502_gpu` if it doesn't exist. They also recreate `/tmp/bb6502_in` as an empty **regular file** every time; a FIFO there would freeze the simulation, see [hardware.md](hardware.md#acia-serial-port).
- The whole build takes under a second. The read multiplexer in `tb.v` reads RAM, ROM and the disk buffer through continuous assignments (`ram_q`, `rom_q`, `dbuf_q`). Indexing the arrays directly inside `always @(*)` makes Icarus expand the block's sensitivity list to every array word (~65,000). That made `iverilog` take about 15 s per build and slowed the simulation down.
- `kernel.cfg` declares a `VECTORS` segment that nothing defines; ld65 warns and it's harmless.
