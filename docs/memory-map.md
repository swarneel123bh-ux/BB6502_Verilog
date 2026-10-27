# Memory map

## CPU address space (what code sees)

| Range | What |
|---|---|
| `$0000-$7FFF` | **RAM, through the MMU**: 32 virtual pages of 1 KB (`VA[14:10]` = page number). Identity-mapped in kernel mode. |
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
| `$8080-$809F` | MMU page table `ppn[0..31]` |
| `$80A0-$80A3` | MMU user-access bits (32 bits) |
| `$80A4-$80A7` | MMU write-permission bits (32 bits) |
| `$80A8` | MMU mode (bit 0: 1 = kernel, 0 = user) |

## Physical RAM (32 KB = 32 pages of 1 KB)

| Physical pages | Range | Used by |
|---|---|---|
| 0–3 | `$0000-$0FFF` | **Kernel**: zero page (`$00-$1F` cc65, `$30-$55` fixed slots, `$FE/$FF` BRK handler pointer), stack `$0100`, kernel image `$0200-$0D18`. `$0D19-$0FFF` is currently free. |
| 4–11 | `$1000-$2FFF` | `hello` (base 1) |
| 12–19 | `$3000-$4FFF` | `hello2` (base 3) |
| 20–27 | `$5000-$6FFF` | `disktest` (base 5) |
| 28–31 | `$7000-$7FFF` | **Kernel high page** (`KHIGH` in `kernel.cfg`): process table `plist` at `$7000`, disk buffer `block_buf` at `$7100`, and the kernel's cc65 C stack growing down from `$7EFF` |

`spawn_bbx`'s `base` still names a 4 KB block, as before the MMU moved to 1 KB pages. The kernel maps the process's old 4 KB virtual page k (1 KB pages 4k..4k+3) to the four 1 KB physical pages of block `(base + k) & 7`, so every byte lands where it did with 4 KB pages. With base 1, virtual `$0000-$0FFF` → physical pages 4–7 and virtual `$1000-$1FFF` → 8–11. The `& 7` wraps around: with base 3, virtual `$5000-$7FFF` maps onto physical `$0000-$2FFF`. `sched_start` also sets every user-access and write bit, so **processes are not isolated** from each other or from the kernel yet. A page allocator is the next step.

One collision already happens:
- Each process's cc65 software stack starts at virtual `$7EFF`, which maps to the 4 KB block `base - 1`.
- For `hello` (base 1) that's the kernel's block: its C stack lands at physical `$0EFF`, in the free tail of the kernel's page 3.
- That's harmless now that `plist` and `block_buf` live in the high page, but it caps kernel growth at about `$0E00` until each process gets its own pages.

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
