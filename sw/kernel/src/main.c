#include <stdint.h>
#include "include/kernel.h"
#include "include/block.h"
#include "include/proc.h"
#include "include/devices.h"

// _brk_handler
// Kernel must install this at $FFFE after boot
extern void brk_handler(void);	// <- in brk.s

int main(void) {
	uint8_t i;

	// Install the brk_handler
	*(uint8_t*)0xFE = (uint8_t)((uint16_t)brk_handler);				// LOW BYTE
	*(uint8_t*)0xFF = (uint8_t)((uint16_t)brk_handler >> 8);	// HIGH BYTE

  // Identity map pages for kernel
  for (i = 0; i < 8; ++i) {
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

  k_print("Loading hello.c\r\n");
  spawn_bbx(200, 1, 1);    // hello.c at lba 200
  k_print("Loading hello2.c\r\n");
  spawn_bbx(210, 1, 3);    // hello2.c at lba 210
  k_print("Staring scheduler...\r\n");
  sched_start();           // never returns
 	k_print("Program returned, hanging\n");
  while(1);
  return 0;
}
