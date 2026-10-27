# Processes and cooperative multitasking

Source: `sw/kernel/src/proc.c`, `yield.s`, `include/proc.h`.

## Process table

`PROCESS plist[4]`, 32 bytes per entry:

| Offset | Field |
|---|---|
| 0 | `state`: 0 exited, 1 waiting, 2 running |
| 1 | `exit_code` |
| 2 | `lba`: where it was loaded from |
| 3 | `nblocks` |
| 4–12 | `name[9]` (unused so far) |
| 13 | `SP`: saved hardware stack pointer |
| 14–21 | `mmu_ppn_table[8]`: saved page table |
| 22–31 | Padding |

`yield.s` uses the offsets 0, 13 and 14 directly. If you change the struct, change both.

## Loading: `spawn_bbx(lba, nblocks, base)`

1. Sets the page table to `ppn[i] = base + i`.
2. Reads sector `lba` and checks the `BX` magic. Takes the entry point from header bytes 4–5.
3. Copies `nblocks` sectors to virtual `$1000 + 512·b`. It does this by **physical** address, `((base + (va >> 12)) << 12) | (va & $FFF)`, because the kernel runs untranslated.
4. Builds an RTI frame on the new process's stack page (physical `base·$1000 + $01FD`): status `$20` (I clear), then PCL and PCH of the entry point. It sets `SP = $FC`.
5. Marks the process `WAITING`.

## Starting: `sched_start()`

Selects `plist[0]` and sets `u_bits = w_bits = $FF`. It loads that process's SP and page table, then `JMP ($FFF8)`. `ret_user_mode` switches to user mode and does `RTI`, which pops the frame `spawn_bbx` built, so the process starts at its entry point.

## Switching: `sys_yield()` → `do_yield`

```
process A: PHA PHX PHY ; BRK #0           (A/X/Y + RTI frame now on A's stack)
kernel:    brk_handler sees syscall 0 → do_yield
           plist[A]: state = WAITING, SP = S, ppn[] = MMU_PPN0..7
           schedule_process()              next WAITING after plist_idx, round robin
           plist[B]: state = RUNNING, S = SP, MMU_PPN0..7 = ppn[]
           JMP ($FFF8) → user mode → RTI   (pops B's frame from *B's* stack page)
process B: PLY PLX PLA ; RTS              (back in B's sys_yield stub)
```

Only SP and the page table are saved in the table. Everything else (A, X, Y, flags, PC) lives on the process's own stack page, which is mapped back in when the page table is restored.

This is **cooperative**: a process that never calls `sys_yield` keeps the CPU forever. There is no timer interrupt yet.

## Limitations

- At most 4 processes. `spawn_bbx` refuses more.
- `sys_exit` halts the whole machine. Exited processes are never reclaimed.
- No isolation. Page numbers wrap (3-bit PPN), and every user page is accessible and writable (see [memory-map.md](memory-map.md#physical-ram-32-kb--8-pages-of-4-kb)).
- The kernel decides what to load in `main.c`, by fixed sector number. There is no shell and no loading by file name yet.
