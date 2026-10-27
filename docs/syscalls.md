# Syscalls, BBX executables and the boot record

## Syscall ABI

A program calls the kernel by putting arguments in **its own zero page** and executing `BRK`, followed by one byte holding the syscall number. The user-side stubs are in `sw/prog/src/syslib.s`:

```asm
_sys_puts:
    sta SYS_ARG0_LO      ; $34  string pointer (cc65 passes it in A/X)
    stx SYS_ARG0_HI      ; $35
    pha                  ; save A/X/Y on the process stack:
    phx                  ; brk_handler can't, because the stack it sees
    phy                  ; belongs to the user
    brk
    .byte 4              ; syscall number
    ply                  ; execution resumes here after the kernel's RTI
    plx
    pla
    rts
```

### The ABI block

The slots live in a block in the program's zero page. Its position and size are set **once**, in `common.mk`: `SYS_ABI_BASE` (default 48 = `$30`) and `SYS_ABI_SIZE` (default 17, so `$30-$40`). Every tool gets those numbers from the Makefile:

| Who | Gets it as | Uses it for |
|---|---|---|
| `syslib.s` (user stubs) | `ca65 -D SYS_ABI_BASE=…` | `SYS_RET = SYS_ABI_BASE + 3`, … |
| `syscalls.c` (kernel) | `cc65 -DSYS_ABI_BASE=…` | `OFF_RET (SYS_ABI_BASE + 3)`, … |
| `prog.cfg` (linker) | `ld65 -D __SYS_ABI_BASE__=…` | Puts cc65's own zero-page variables right **after** the block, so they can never overlap it |

Slots, as offsets from `SYS_ABI_BASE`:

| Offset | Default address | Name | Use |
|---|---|---|---|
| +3 | `$33` | `SYS_RET` | Return code |
| +4/+5 | `$34/$35` | `ARG0` | First argument (lo/hi) |
| +6/+7 | `$36/$37` | `ARG1` | Second argument |
| +8/+9 | `$38/$39` | `ARG2` | Third argument |
| +$10 | `$40` | `SYS_A_REG` | Byte argument in / byte result out |

Offsets +0..+2 and +$0A..+$0F are currently unused on the user side.

**Adding a slot:**
1. Add it in `syslib.s` and with the same offset in `syscalls.c`.
2. If the block got longer, raise `SYS_ABI_SIZE`.
3. Run `make clean`.

The build checks itself:
- `syslib.s` asserts that `SYS_A_REG` lies inside the block and that the block fits in zero page.
- ld65 reports "overflows memory area 'ZP'" if cc65's variables no longer fit between the block and `$FF`.

Kernel side:
1. `BRK` vectors through `$FFFE` → `brk_trampoline` → `brk_handler` (`sw/kernel/src/brk.s`), already in kernel mode.
2. The handler finds the user's stack through `MMU_PPN0`, checks the B flag (BRK versus IRQ), and fetches the number byte (translating the user's PC to a physical address through the page table).
3. It stores the number in the kernel's `$32`. Syscall 0 goes to `do_yield`; anything else goes to `syscall_dispatch()` (`syscalls.c`).
4. Syscall code reads its arguments from the *user's* zero page through `u_zp()`. User pointers are translated with `u_ptr()`, using the page of the pointer's own address.
5. Return: `JMP ($FFF8)` → `ret_user_mode` → user mode → `RTI` to the instruction after the number byte.

## Syscall list

| # | Name | Arguments | Result |
|---|---|---|---|
| 0 | `sys_yield` | — | Switches to the next waiting process (see [processes.md](processes.md)) |
| 1 | `sys_exit(code)` | `$40` = code | **Halts the machine** (SEI + spin); there is no process exit yet |
| 2 | `sys_putc(c)` | `$40` = char | Printed on ACIA + GPU |
| 3 | `sys_getc()` | — | Waits for a key; returns it in `$40` / A |
| 4 | `sys_puts(s)` | `ARG0` = string | Printed on ACIA + GPU |
| 5 | `sys_block_read(lba, buf)` | `ARG0` = LBA, `ARG1` = buffer | `$33` = 0 OK / 1 error |
| 6 | `sys_block_write(lba, buf)` | `ARG0` = LBA, `ARG1` = buffer | `$33` = 0 OK / 1 error |
| 7 | `SYS_EXEC` | — | Reserved: `ENOSYS` ($FF) |
| 8 | `SYS_GETC_NB` | — | Kernel only, no user stub yet: `$40` = key, `$33` = 0, or `$33` = 1 if no key |
| 9–11 | `OPEN_FAT`, `READ_FAT`, `PROCESS_CREATE` | — | Reserved: `ENOSYS` |

Passing arguments from C: cc65's default `__fastcall__` convention puts the **last** argument in A/X and pushes the earlier ones onto cc65's software stack. The callee must remove them. So `sys_block_read(lba, buf)` stores A/X as `buf`, then calls `popax` to take `lba` off the stack. `sw/prog/src/disktest.c` tests this end to end: it reads sector 0 and checks for the `55 AA` signature.

Known problems:
- **Block buffers can't cross pages.** A block buffer must not cross a 4 KB virtual page, because only the start address is translated.

## BBX executable format

Both the kernel and user programs are `.bbx` files: a 6-byte header followed by the raw image. Each program's `crt0` file emits the header in an `HDR` segment that the linker config places first.

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | Magic `'B' 'X'` (`$42 $58`) |
| 2 | 2 | Load address (little-endian): `$0200` for the kernel, `$1000` for programs |
| 4 | 2 | Entry point (little-endian) |
| 6 | … | Code and data, linked to run at load address + 6 |

`tools/mkbbx.c` checks a header. Despite its name, it does not create one.

## Boot record (LBA 100)

Written by `tools/mkbootrec.py` and read by the boot ROM:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | Magic `'BBBR'` |
| 4 | 4 | Kernel LBA (little-endian) |
| 8 | 2 | Kernel size in sectors (little-endian) |
| 10 | 502 | Zero padding |
