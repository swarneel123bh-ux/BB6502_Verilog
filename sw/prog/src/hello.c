// ==========================================================================
// hello.c — demo process 1: prints a counter and yields, forever
// ==========================================================================
#include "include/syslib.h"

int main(void) {
	int i = 0;
	while (1) {
		sys_puts("Proc1:");
		sys_putc(i + '0');
		sys_puts("\r\n");
		i ++;
		sys_yield();
	}
  sys_exit(0);
  return 0;
}
