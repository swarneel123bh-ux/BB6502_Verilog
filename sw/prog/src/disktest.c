// ==========================================================================
// disktest.c — test process for sys_block_read
//
// Reads disk sector 0 (the FAT32 boot sector) and prints the call's return
// value and bytes 510/511, then PASS or FAIL. Expected:
//         disktest: ret=00 sig=55 AA PASS
// Afterwards it only yields, so the other processes keep running.
// ==========================================================================
#include "include/syslib.h"
#include <stdint.h>

// Must not cross a 1 KB virtual page: the kernel translates only the start
// address (check _buf in build/disktest.dbg; it sits just above $1000).
static uint8_t buf[512];

static void puthex(uint8_t b) {
	static const char hex[] = "0123456789ABCDEF";
	sys_putc(hex[b >> 4]);
	sys_putc(hex[b & 0x0F]);
}

int main(void) {
	uint8_t r = sys_block_read(0, buf);

	sys_puts("        disktest: ret=");
	puthex(r);
	sys_puts(" sig=");
	puthex(buf[510]);
	sys_putc(' ');
	puthex(buf[511]);
	if (r == 0 && buf[510] == 0x55 && buf[511] == 0xAA)
		sys_puts(" PASS\r\n");
	else
		sys_puts(" FAIL\r\n");

	while (1) {
		sys_yield();
	}
	return 0;
}
