#include "syslib.h"
// #include "../kernel.h"

// TO TEST IF SYSCALL IS FAILING
// MUST NOT BE USED LIKE THIS

// Registers
#define ACIA_DATA   	((volatile unsigned char*)0x8000)
#define ACIA_STATUS 	((volatile unsigned char*)0x8001)
#define GPU_DATA    	((volatile unsigned char*)0x8002)
#define GPU_STATUS    ((volatile unsigned char*)0x8003)

// MMU Registers
#define MMU_PPN0     ((volatile unsigned char*)0x80F0)
#define MMU_PPN1     ((volatile unsigned char*)0x80F1)
#define MMU_W        ((volatile unsigned char*)0x80F8)
#define MMU_U        ((volatile unsigned char*)0x80F9)


int main(void) {

	while (!(*ACIA_STATUS & 0x01)); // Wait for ACIA TX ready
  *ACIA_DATA = 'k';

  while (!(*ACIA_STATUS & 0x01)); // Wait for ACIA TX ready
   *ACIA_DATA = '\n';

  while (!(*GPU_STATUS & 0x01)); // Wait for GPU TX ready
  *GPU_DATA = 'k';

  while (!(*GPU_STATUS & 0x01)); // Wait for GPU TX ready
  *GPU_DATA = '\n';

  sys_puts("Hello from user program (via syscalls)!\n");

  while (!(*ACIA_STATUS & 0x01)); // Wait for ACIA TX ready
   *ACIA_DATA = 'L';

  while (!(*GPU_STATUS & 0x01)); // Wait for GPU TX ready
   *GPU_DATA = 'L';

  sys_puts("Press any key to exit.\r\n");
  // (void)sys_getc();
  sys_puts("Bye.\r\n");
  sys_exit(0);
  return 0;
}
