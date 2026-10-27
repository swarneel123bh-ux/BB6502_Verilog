# Memory map

## CPU address space (what code sees)

| Range | What |
|---|---|
| `$0000-$7FFF` | **RAM, through the MMU**: 8 virtual pages of 4 KB (`VA[14:12]` = page number). Identity-mapped in kernel mode. |
| `$8000-$80FF` | **I/O window** (see [hardware.md](hardware.md)). Never put code or data here. |
| `$8100-$FFF7` | Boot ROM (`sw/boot/boot.s`; unused space is `$EA` = NOP) |
| `$FFF8-$FFF9` | `ret_user_mode` pointer (BB6502-specific; the kernel uses `JMP ($FFF8)`) |
| `$FFFA-$FFFB` | NMI vector → `nmi_handler` (`RTI`) |
| `$FFFC-$FFFD` | RESET vector → `reset` |
| `$FFFE-$FFFF` | IRQ/BRK vector → `brk_trampoline` (`JMP ($00FE)`) |

### I/O window

| Address | Register |
|---|---|
| `$8000` | ACIA data |
| `$8001` | ACIA status |
| `$8002` | GPU data |
| `$8003` | GPU status |
| `$80E0-$80E3` | Disk LBA (32-bit, little-endian) |
| `$80E4` | Disk command |
| `$80E5` | Disk status |
| `$80E6` | Disk data |
| `$80E7` | Disk buffer pointer reset |
| `$80F0-$80F7` | MMU page table `ppn[0..7]` |
| `$80F8` | MMU write-permission bits |
| `$80F9` | MMU user-access bits |
| `$80FA` | MMU mode (bit 0: 1 = kernel, 0 = user) |

## Physical RAM (32 KB = 8 pages of 4 KB)

| Physical page | Range | Used by |
|---|---|---|
| 0 | `$0000-$0FFF` | **Kernel**: zero page (`$00-$1F` cc65, `$30-$55` fixed slots, `$FE/$FF` BRK handler pointer), stack `$0100`, kernel image `$0200-$0FFF` |
| 1–2 | `$1000-$2FFF` | `hello` (spawned with base 1: virtual page 0 → physical 1, virtual page 1 → physical 2) |
| 3–4 | `$3000-$4FFF` | `hello2` (base 3) |
| 5–7 | `$5000-$7FFF` | free; the kernel's cc65 software stack grows down from `$7EFF` |

A process spawned with `base` gets `ppn[i] = base + i` for all 8 virtual pages. Since physical page numbers are 3 bits, `base + i` wraps around: with base 3, virtual pages 5–7 map to physical 0–2. `sched_start` also sets every user-access and write bit, so **processes are not isolated** from each other or from the kernel yet. They just happen to touch only their first two virtual pages.

## Inside a process (virtual addresses)

| Range | What |
|---|---|
| `$0000-$00FF` | Its own zero page: syscall ABI block at `$30-$40`, then cc65's variables from `$41` (both positions derived from `common.mk`, see [syscalls.md](syscalls.md#syscall-abi)) |
| `$0100-$01FF` | Its own hardware stack (starts at `SP=$FC` with an RTI frame built by `spawn_bbx`) |
| `$1000-$1005` | BBX header |
| `$1006-` | Code, read-only data, data, BSS |
| `$7EFF` down | cc65 software stack |

## Disk image (`build/disk.img`, 1.44 MB, 2880 sectors of 512 bytes)

The disk is first formatted **FAT32** by `mformat -F`: reserved sectors 0–31, FATs 32–75, data from LBA 76. The boot pieces are then written **raw** with `dd` at fixed sectors (numbers in `common.mk`):

| LBA | Contents |
|---|---|
| 0 | FAT32 boot sector (the kernel checks its `55 AA` signature) |
| 100 | Boot record ('BBBR', kernel LBA, sector count) |
| 101–107 | `kernel.bbx` (3584 bytes) |
| 200 | `hello.bbx` |
| 210 | `hello2.bbx` |

The raw sectors are inside the FAT data area but are not reserved in the FAT. If files are copied onto the disk (`disk/` directory → `mcopy`), they may land on the same sectors.
