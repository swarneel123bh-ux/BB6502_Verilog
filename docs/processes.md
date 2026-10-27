# Processes and cooperative multitasking

Source: `sw/kernel/src/proc.c`, `yield.s`, `include/proc.h`.

## Process table

`PROCESS plist[4]`, 64 bytes per entry, in the kernel's high page at `$7000`:

| Offset | Field |
|---|---|
| 0 | `state`: 0 exited, 1 waiting, 2 running |
| 1 | `exit_code` |
| 2 | `lba`: where it was loaded from |
| 3 | `nblocks` |
| 4–12 | `name[9]` (unused so far) |
| 13 | `SP`: saved hardware stack pointer |
| 14–45 | `mmu_ppn_table[32]`: saved page table (one entry per 1 KB virtual page) |
| 46–63 | Padding |

`yield.s` uses the offsets 0, 13 and 14 directly, and indexes the table with `plist_idx << 6`. If you change the struct, change both. `proc.h` has a compile-time check that the size stays 64 bytes.

## Loading: `spawn_bbx(lba, nblocks, base)`

1. Builds the page table. `base` names a 4 KB block of RAM, as before 1 KB pages, so virtual 1 KB page i gets the matching quarter of block `(base + (i >> 2)) & 7`: `ppn[i] = (((base + (i >> 2)) & 7) << 2) | (i & 3)`.
2. Reads sector `lba` and checks the `BX` magic. Takes the entry point from header bytes 4–5.
3. Copies `nblocks` sectors to virtual `$1000 + 512·b`. It does this by **physical** address, `(ppn[va >> 10] << 10) | (va & $3FF)`, because the kernel runs untranslated.
4. Builds an RTI frame on the new process's stack page (physical `(ppn[0] << 10) + $01FD`): status `$20` (I clear), then PCL and PCH of the entry point. It sets `SP = $FC`.
5. Marks the process `WAITING`.

## Starting: `sched_start()`

Selects `plist[0]` and sets all 32 `u_bits` and `w_bits` (4 bytes of `$FF` each). It loads that process's SP and page table, then `JMP ($FFF8)`. `ret_user_mode` switches to user mode and does `RTI`, which pops the frame `spawn_bbx` built, so the process starts at its entry point.

## Switching: `sys_yield()` → `do_yield`

```
process A: PHA PHX PHY ; BRK #0           (A/X/Y + RTI frame now on A's stack)
kernel:    brk_handler sees syscall 0 → do_yield
           plist[A]: state = WAITING, SP = S, ppn[0..31] = MMU page table
           schedule_process()              next WAITING after plist_idx, round robin
           plist[B]: state = RUNNING, S = SP, MMU page table = ppn[0..31]
           JMP ($FFF8) → user mode → RTI   (pops B's frame from *B's* stack page)
process B: PLY PLX PLA ; RTS              (back in B's sys_yield stub)
```

Only SP and the page table are saved in the table. Everything else (A, X, Y, flags, PC) lives on the process's own stack page, which is mapped back in when the page table is restored.

This is **cooperative**: a process that never calls `sys_yield` keeps the CPU forever. There is no timer interrupt yet.

## Limitations

- At most 4 processes. `spawn_bbx` refuses more.
- `sys_exit` halts the whole machine. Exited processes are never reclaimed.
- No isolation. `base + k` wraps around, and every user page is accessible and writable (see [memory-map.md](memory-map.md#physical-ram-32-kb--32-pages-of-1-kb)).
- The kernel decides what to load in `main.c`, by fixed sector number. There is no shell and no loading by file name yet.
