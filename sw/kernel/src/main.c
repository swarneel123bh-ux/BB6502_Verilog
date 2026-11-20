// ==========================================================================
// main.c — kernel entry (called from crt0.s)
//
// Installs the BRK handler, identity-maps the MMU page table, checks the
// disk's FAT boot signature, loads the three demo programs as processes
// (spawn_bbx) and hands the CPU to the scheduler (sched_start), which
// never returns.
// ==========================================================================
#include <stdint.h>
#include "include/kernel.h"
#include "include/block.h"
#include "include/proc.h"
#include "include/devices.h"

#define ZP_IRQ_A	          ((volatile uint8_t*) 0x0040)				// Save-point for A when IRQ happens
#define ZP_IRQ_X	          ((volatile uint8_t*) 0x0041)				// Save-point for A when IRQ happens
#define ZP_IRQ_Y	          ((volatile uint8_t*) 0x0042)				// Save-point for A when IRQ happens
#define ZP_TIMER_INT_COUNT0 ((volatile uint8_t*) 0x0060) 				// How many interrupts have happend, i dont think its necessary to track this
#define ZP_TIMER_INT_COUNT1 ((volatile uint8_t*) 0x0062) 				// but i need to test the timers out too so im using this temporarily
#define ZP_TIMER_INT_COUNT2 ((volatile uint8_t*) 0x0064) 				// later on, the kernel defines how to handle, and brk.s simply points to that
#define ZP_TIMER_INT_COUNT3 ((volatile uint8_t*) 0x0067) 				// subroutine
#define ZP_PREEMPT_PENDING ((volatile uint8_t*) 0x0068)				// set by the timer-0 IRQ (brk.s), cleared when it is handled

// _brk_handler
// Kernel must install its address at $00FE/$00FF after boot: the IRQ/BRK
// vector ($FFFE, in ROM) points at brk_trampoline, which does JMP ($00FE).
extern void brk_handler(void);	// <- in brk.s

// Minimum timer period. Each interrupt takes ~1100 clocks to service (save and
// restore of the page table), so a Hz timer must not fire faster than that or the
// process never gets to run. 100 Hz = 10000 clocks, a 10x margin.
#define TIMER_MAX_HZ 100

// ---- Timer macros -------------------------------------------------------
// Channel n's 3 config bytes are at TIMER_CONF00 + 3*n (24-bit value).
// Byte 2 is written last: that write starts the Hz divider.
#define TIMER_CONF_BASE 0x8012
#define TIMER_CONF_WRITE(ch, v) do { \
	uint32_t _v = (uint32_t)(v); \
	volatile uint8_t *_c = (volatile uint8_t*)(TIMER_CONF_BASE + 3*(ch)); \
	_c[0] = (uint8_t)(_v & 0xFF); \
	_c[1] = (uint8_t)((_v >> 8) & 0xFF); \
	_c[2] = (uint8_t)((_v >> 16) & 0xFF); \
} while (0)

// Run channel ch at hz times per second (Hz mode), clamped to TIMER_MAX_HZ.
#define TIMER_SET_HZ(ch, hz) do { \
	uint32_t _h = ((uint32_t)(hz) > TIMER_MAX_HZ) ? TIMER_MAX_HZ : (uint32_t)(hz); \
	*TIMER_CTL |= (uint8_t)(1 << (ch)); \
	TIMER_CONF_WRITE(ch, _h); \
} while (0)

// Run channel ch every ms milliseconds (ms mode, up to 16777 s).
#define TIMER_SET_MS(ch, ms) do { \
	*TIMER_CTL &= (uint8_t)~(1 << (ch)); \
	TIMER_CONF_WRITE(ch, (ms)); \
} while (0)

// Timer IRQ enables are CTL bits 4..7 (one per channel). Keep them all on.
#define TIMER_IRQ_ENABLE_ALL 0xF0


int main(void) {
	uint8_t i;

	// Install the brk_handler
	*(uint8_t*)0xFE = (uint8_t)((uint16_t)brk_handler);				// LOW BYTE
	*(uint8_t*)0xFF = (uint8_t)((uint16_t)brk_handler >> 8);	// HIGH BYTE

  // Start from an identity page table (kernel mode doesn't translate at all;
  // this only gives the MMU sane contents until a process is loaded)
  for (i = 0; i < MMU_NPAGES; ++i) {
  	*(MMU_PPN0+i) = i;
  }

  // Boot Sector test
  if (block_read(0, block_buf)) {
  	k_print("block_read ERROR");
   	while (1);	// Hang on Boot Sector Read fail
  }

  if (block_buf[510] == 0x55 && block_buf[511] == 0xAA) {
  	k_print("FAT boot signature OK\r\n");
  } else {
  	k_print("FAT boot signature MISSING\r\n");
  }

  // Timer interrupts test
  *ZP_PREEMPT_PENDING = 0;
  *ZP_TIMER_INT_COUNT0 = 0;							// Set counters to 0
  *ZP_TIMER_INT_COUNT1 = 0;
  *ZP_TIMER_INT_COUNT2 = 0;
  *ZP_TIMER_INT_COUNT3 = 0;
  *TIMER_CTL = TIMER_IRQ_ENABLE_ALL;     // every channel may interrupt; modes set below
  TIMER_SET_MS(0, 100);        // timer 0: every 500 ms
  TIMER_SET_MS(1, 1000);       // timer 1: every 1 s
  TIMER_SET_MS(2, 10000);      // timer 2: every 10 s
  TIMER_SET_MS(3, 15000);      // timer 3: every 15 s

  // Cooperative multitasking test
  k_print("Loading hello.c\r\n");
  spawn_bbx(200, 1, 1);    // hello.c at lba 200
  // hello2.c (lba 210) is replaced by the register test (regtest.c, 3 sectors, lba 230).
  // regtest takes blocks 3-5 and disktest uses block 5, so the two overlap physically.
  // This runs correctly today, but processes are not isolated until the page allocator
  // lands (see sw/kernel/src/proc.c, "Known limitation"). Moving disktest to block 6
  // hung the boot; that is not explained yet.
  k_print("Loading regtest.c\r\n");
  spawn_bbx(230, 3, 3);    // regtest.c at lba 230
  k_print("Loading disktest.c\r\n");
  spawn_bbx(220, 1, 5);    // disktest.c at lba 220 (sys_block_read test)
  k_print("Staring scheduler...\r\n");
  sched_start();           // never returns
 	k_print("Program returned, hanging\n");
  while(1);
  return 0;

}
