#include <stdint.h>

#define ACIA_DATA    (*(volatile uint8_t*)0x8000)
#define ACIA_STATUS  (*(volatile uint8_t*)0x8001)
#define GPU_DATA     (*(volatile uint8_t*)0x8002)
#define GPU_STATUS   (*(volatile uint8_t*)0x8003)

// Calling the hardware directly should be a kernel task
// Its allowed here only because i am testing the loader
// Otherwise it must be done through syscalls
static void p_putc(char c) {
  while (!(ACIA_STATUS & 0x01));
  ACIA_DATA = c;
  while (!(GPU_STATUS & 0x01));
  GPU_DATA = c;
}

static void p_print(const char* s) {
  while (*s) p_putc(*s++);
}

int main(void) {
	int i;

	for (i = 0; i < 10; ++i) {
		p_print("Hello from user program!\r\n");
	}

	p_print("Bye Bye\n");
	return 0;
}
