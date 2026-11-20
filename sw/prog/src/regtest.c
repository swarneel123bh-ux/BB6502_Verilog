// ==========================================================================
// regtest.c — checks that A, X and Y survive sys_yield and timer preemption.
//
// Each round loads A=$A5, X=$5A, Y=$3C, then either:
//   yield round:    calls sys_yield, then stores A, X, Y;
//   preempt round:  runs a DEC-based delay (no register use, no calls), then
//                   stores A, X, Y. A timer switch can land inside the delay.
// The loads, the call or delay, and the stores are in asm, so C code cannot
// disturb the registers in between.
//
// This program is NOT built with -Oir: cc65's optimizer drops the register
// loads that come before the jsr in the yield round (see sw/prog/prog.mk).
//
// Every 100 rounds it prints one line with the counts and any failures.
// To run it instead of hello2, spawn it in sw/kernel/src/main.c
// (see the comment there).
// ==========================================================================
#include "include/syslib.h"

uint8_t regA, regX, regY;   // written by the asm (global, so _name in asm)
uint8_t dly;                // delay counter: DEC on memory keeps A, X, Y
uint16_t rounds, yield_rounds, preempt_rounds;
uint16_t fails_yield, fails_preempt;
uint8_t lastA, lastX, lastY;

static void put_dec(uint16_t v) {
	uint8_t buf[5];
	uint8_t n = 0, i;
	do { buf[n++] = (uint8_t)('0' + v % 10); v /= 10; } while (v);
	for (i = n; i > 0; i--) sys_putc(buf[i - 1]);
}

static void report(void) {
	sys_puts("\r\nregtest: rounds=");
	put_dec(rounds);
	sys_puts(" yield=");
	put_dec(yield_rounds);
	sys_puts(" preempt=");
	put_dec(preempt_rounds);
	sys_puts(" fail_yield=");
	put_dec(fails_yield);
	sys_puts(" fail_preempt=");
	put_dec(fails_preempt);
	if (fails_yield || fails_preempt) {
		sys_puts(" LAST A/X/Y=");
		put_dec(lastA); sys_putc('/');
		put_dec(lastX); sys_putc('/');
		put_dec(lastY);
	}
	sys_puts("\r\n");
}

int main(void) {
	while (1) {
		if (rounds & 1) {
			// --- yield round: one asm statement per instruction ---
			__asm__("lda #$a5");
			__asm__("ldx #$5a");
			__asm__("ldy #$3c");
			__asm__("jsr _sys_yield");
			__asm__("sta _regA");
			__asm__("stx _regX");
			__asm__("sty _regY");
			yield_rounds++;
			if (regA != 0xA5 || regX != 0x5A || regY != 0x3C) {
				fails_yield++;
				lastA = regA; lastX = regX; lastY = regY;
			}
		} else {
			// --- preempt round: a delay with no calls, then the stores ---
			__asm__(
				"lda #$ff\n"
				"sta _dly\n"
				"lda #$a5\n"
				"ldx #$5a\n"
				"ldy #$3c\n"
				"rtdly:\n"
				"dec _dly\n"
				"bne rtdly\n"
				"sta _regA\n"
				"stx _regX\n"
				"sty _regY\n");
			preempt_rounds++;
			if (regA != 0xA5 || regX != 0x5A || regY != 0x3C) {
				fails_preempt++;
				lastA = regA; lastX = regX; lastY = regY;
			}
		}
		rounds++;
		if (rounds % 100 == 0) report();
	}
	return 0;
}
