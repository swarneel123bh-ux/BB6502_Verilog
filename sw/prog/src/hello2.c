#include "include/syslib.h"

int main(void) {
	while (1) {
		sys_puts("Hello from process 2!\r\n");
		sys_yield();
	}
  sys_exit(0);
  return 0;
}
