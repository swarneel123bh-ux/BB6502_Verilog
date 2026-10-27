# Hardware (the Verilog model)

All of this is in `rtl/tb.v` unless noted otherwise. Addresses are CPU addresses.

## Clock, reset, CPU

- 100 MHz simulated clock (`always #5 clk = ~clk`). Reset is held for 16 cycles at start-up.
- CPU: Arlet Ottens' `verilog-65C02-microcode/generic`, a cycle-accurate 65C02 with all the CMOS instructions. The fork adds a **`VPB`** output (low while the CPU reads `$FFFA-$FFFF`). The MMU uses it to switch to kernel mode on interrupts and BRK.
- The core's `AD` (next address) is registered into `AB` every clock. Memory and I/O are decoded from `AB`, as Arlet's README describes for asynchronous memory.
- `IRQ` is tied low (no interrupt sources yet). `NMI` comes from the MMU's fault output. `RDY` is always 1.

## Read/write decode

| `AB` | Read | Write |
|---|---|---|
| `$0000-$7FFF` | `ram[mmu paddr]` | `ram[mmu paddr]` |
| `$8080-$80BF` | MMU register | MMU register (kernel mode only) |
| `$8000` | `acia_rx_data` | Byte printed on vvp's stdout (debug build: the debugger's terminal pane) |
| `$8001` | `{6'b0, acia_tx_ready, acia_rx_valid}` | — |
| `$8002` | — | Byte written to `/tmp/bb6502_gpu` |
| `$8003` | `$01` (always ready) | — |
| `$80E0-$80E3` | Disk LBA bytes | Disk LBA bytes |
| `$80E4` | — | Disk command |
| `$80E5` | `{err, 6'b0, busy}` | — |
| `$80E6` | `disk_buf[dptr]`, then `dptr++` | `disk_buf[dptr] = byte`, then `dptr++` |
| `$80E7` | — | `dptr = 0` |
| `$8100-$FFFF` | `rom[AB-$8100]` | — |
| other `$80xx` | `$FF` | ignored |

## ACIA (serial port)

Modelled on a 6850 ACIA. The status register at `$8001`:

| Bit | Name | Meaning |
|---|---|---|
| 0 | RX valid | A received byte is waiting in `$8000`. Reading `$8000` clears it. |
| 1 | TX ready (6850 TDRE) | The transmitter can take a byte |

- **TX:** writing `$8000` prints the byte. TX ready then goes low for `ACIA_TX_CYCLES` CPU cycles: 87, which is one 10-bit character at 115200 baud with a 1 MHz CPU. Change the `localparam` in `tb.v` to model another baud rate. Software must wait for bit 1 before each write. Writing while busy prints `[acia] TX overrun: byte … at t=…`, which a real chip would turn into a garbled byte.
- **RX:** every 200 clocks, if no byte is pending, the testbench reads the next byte of `/tmp/bb6502_in` and sets RX valid. The file is a **regular file** that keys are appended to; the testbench re-seeks to the next unread byte, so an empty file just returns EOF. It must not be a FIFO: `$fgetc` on an empty FIFO blocks and freezes the whole simulation. The Makefile recreates it as an empty regular file on every run.

The GPU status register at `$8003` always reads `$01`, so the GPU half of each print never waits.

## GPU stream

Writing `$8002` appends the byte to `/tmp/bb6502_gpu` and flushes it. `tools/gpu.c` reads that pipe and renders an 80×25 character screen in an SDL window:
- `\n` starts a new line, `\r` returns to column 0, `\b` erases, and `\f` clears the screen
- the screen scrolls at the bottom

Keys typed into the window are written to `/tmp/bb6502_in`: printable text, Enter as `\r`, Backspace as `$08`, Tab, Esc, and Ctrl-A..Z as `$01-$1A`.

## Disk controller

A 512-byte sector buffer in front of `build/disk.img` (opened read/write, so writes are saved).

| Step | Read a sector | Write a sector |
|---|---|---|
| 1 | Write LBA to `$80E0-$80E3` | Write `$80E7` (reset `dptr`) |
| 2 | Write `$01` to `$80E4` | Write 512 bytes to `$80E6` |
| 3 | Poll `$80E5` until bit 0 = 0 | Write LBA to `$80E0-$80E3` |
| 4 | Write `$80E7` (reset `dptr`) | Write `$02` to `$80E4` |
| 5 | Read 512 bytes from `$80E6` | Poll `$80E5` until bit 0 = 0 |

In the model the transfer completes instantly, within the same clock as the command. Bit 7 of the status is set if no disk image is open. Reads past the end of the file return zeros. On real hardware (an SD card over SPI), the read loop would have to change; `boot.s` notes this.

## MMU

`rtl/mmu6502.v`, instantiated with `PPN_WIDTH = 5`. Pages are **1 KB**: 32 virtual pages map onto 32 physical pages.

```
                     kernel mode:  paddr = AB[14:0]
 AB[14:10] = vpn ──► user mode:    paddr = { ppn[vpn], AB[9:0] }      (15 bits = 32 KB)
```

The registers are direct-mapped at `$8080-$80BF`:

| Register | Meaning |
|---|---|
| `$8080+n` (n = 0–31) | `ppn[n]`: the physical page for virtual page n (low 5 bits) |
| `$80A0-$80A3` | `u_bits`: user may access the page. Byte k, bit n = virtual page 8k+n. |
| `$80A4-$80A7` | `w_bits`: user may write the page. Same layout. |
| `$80A8` | Mode: bit 0 = 1 kernel, 0 user |
| `$80A9-$80BF` | Reserved (read as 0) |

Rules:
- **Entering kernel mode:** at reset, on any vector fetch (`VPB` low: BRK, IRQ, NMI), and on any fault.
- **Faults** in user mode:
  - accessing RAM in a page whose `u_bits` bit is 0
  - writing RAM in a page whose `w_bits` bit is 0
  - writing any MMU register
- **Reporting faults:** a fault is registered for one cycle and drives `NMI` (through `faultb`). The testbench also prints `[mmu] FAULT AB=… WE=… paddr=…`.
- **Register access:** control registers can be written only in kernel mode. They can be read in either mode.
- **Reset state:** identity page table, all pages writable, no pages user-accessible, kernel mode.
- **Timing:** state changes happen on the falling clock edge (`phi2` negedge).

## Simulation files

| File | Opened as | Purpose |
|---|---|---|
| `build/bootrom.hex` | `$readmemh` | ROM contents |
| `rtl/verilog-65C02-microcode/generic/microcode.hex` | `$readmemb` (in `microcode.v`) | CPU microcode |
| `build/disk.img` | `r+b` | Disk |
| `/tmp/bb6502_in` | `r` | Keyboard input (regular file) |
| `/tmp/bb6502_gpu` | `w` | GPU output (FIFO; `gpu` reads the other end) |

These paths are relative, so `vvp` must run from the project root; the Makefile does this.
