# Timers

The timer block (`rtl/timer6502.v`) has four independent channels. Each channel raises a sticky pending flag once per programmed period. Any pending flag that is enabled drives the CPU's IRQ line. The software side is in `sw/kernel/src/brk.s` (the IRQ path and the handlers) and `sw/kernel/src/main.c` (setup).

## Registers

Base address `$8010`. The block is 14 bytes, `$8010`–`$801D`.

| Address | Offset | Name | Access | Meaning |
|---|---|---|---|---|
| `$8010` | 0 | `TIMER_CTL` | R/W | Bits 0–3: mode per channel, `1` = Hz, `0` = ms. Bits 4–7: IRQ enable per channel, `1` = enabled. |
| `$8011` | 1 | `TIMER_ST` | R/W1C | Bits 0–3: pending flag per channel. Write `1` to clear that channel's flag. Bit 4: BUSY, read-only, set while the Hz divider is running. |
| `$8012`–`$8014` | 2–4 | `TIMER_CONF00`–`02` | R/W | Channel 0 config: 24-bit value, byte 0 (LSB) at `$8012`, byte 2 at `$8014`. |
| `$8015`–`$8017` | 5–7 | `TIMER_CONF10`–`12` | R/W | Channel 1 config. |
| `$8018`–`$801A` | 8–10 | `TIMER_CONF20`–`22` | R/W | Channel 2 config. |
| `$801B`–`$801D` | 11–13 | `TIMER_CONF30`–`32` | R/W | Channel 3 config. |

Writing the config does not clear pending flags. Byte 2 is the last byte of a config write, and writing it starts the Hz divider for a Hz channel, so write byte 0 and byte 1 first.

## Periods

The clock constant is `CLK_HZ = 1_000_000` (set in `rtl/tb.v`, matching the 1 MHz simulated clock).

- **ms mode:** the period is `conf` milliseconds. Up to 16,777 seconds (`2^24 − 1` ms).
- **Hz mode:** the period is `CLK_HZ / conf` clocks, so the rate is `conf` times per second. The divider takes about 25 clocks, and the new period is used once it finishes.
- **`conf = 0`:** the channel is off.

`CLK_HZ` must be a multiple of 1000 for exact millisecond periods, and below `2^24` for the Hz divider.

## Interrupts

- The IRQ line is level-sensitive: it stays asserted while any enabled pending flag is set. The CPU keeps taking the interrupt until the flag is cleared.
- Each handler clears its own flag by writing its bit to `TIMER_ST`, then counts the interrupt.
- The IRQ path (`brk.s`, `irq_path`) reads `TIMER_ST` and dispatches to the lowest set bit's handler. One handler runs per interrupt. A flag that is still set after the handler returns causes another interrupt straight away.
- The handlers count interrupts in the zero-page counters `ZP_TIMER_INT_COUNT0`–`3` (`$60`, `$62`, `$64`, `$67`). Those counters must be zeroed at boot; `main.c` does it.

## Setup from C

`sw/kernel/src/main.c` has the setup macros:

- `TIMER_SET_MS(ch, ms)` runs channel `ch` every `ms` milliseconds. It clears that channel's mode bit and writes the config.
- `TIMER_SET_HZ(ch, hz)` runs channel `ch` `hz` times per second. It sets the channel's mode bit, clamps `hz` to `TIMER_MAX_HZ`, and writes the config.
- `TIMER_IRQ_ENABLE_ALL` (`0xF0`) enables the IRQ for all four channels. Write it to `TIMER_CTL` before setting the modes.

```c
*TIMER_CTL = TIMER_IRQ_ENABLE_ALL;   // every channel may interrupt
TIMER_SET_MS(0, 100);                // every 100 ms
TIMER_SET_MS(1, 1000);               // every 1 s
TIMER_SET_MS(2, 10000);              // every 10 s
TIMER_SET_MS(3, 15000);              // every 15 s
```

The macros are the only supported way to set the timers. Writing `TIMER_CTL` with `0x07` (or any value with bits 4–7 clear) turns every timer interrupt off, and the counters will not move.

## The 100 Hz clamp

`TIMER_MAX_HZ` is 100. The reason is the interrupt path's cost. Servicing one interrupt means saving and restoring the page table, which takes about 1,100 clocks (about 1.1 ms of simulated time). A Hz timer that fires faster than that means the next interrupt is pending before the process runs again, so the process never makes progress.

The clamp is only for Hz channels. ms channels are not limited by it. Anything at 1 kHz or above with a 1,100-clock path is at risk of this starvation.

## Not done yet

- **Only timer 0 reschedules.** Timer 0 is the preemption tick: its interrupt switches to the next process (see [processes.md](processes.md)). Timers 1–3 clear their flag and return to the same process.
- **Starvation is not fixed in general.** The clamp keeps the timers slow enough for the current interrupt path. Servicing every pending flag per interrupt, or shortening the save and restore, would remove the need for it.

## Debugging

- Read the counters with `m 0x0060 0x0067` while the CPU is in kernel mode. In user mode, `m` reads through the process's page table and shows the process's own memory. `r` shows `MMU=kernel` or `MMU=user`.
- To check that the timers are firing, set a breakpoint on `handle_timer0` (see `build/kernel.dbg`) and continue.
- Simulated time runs at 1 MHz, so a 10 s timer takes 10 s of simulated time. `make run` paces the simulation to the wall clock, so the same timer takes 10 s of real time there. `make run-fast` is much quicker, and `make run-dbg` runs as fast as the debugger allows.
