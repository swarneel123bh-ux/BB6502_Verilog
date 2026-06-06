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

  //k_print("Kernel Booting...\n");
  // Identity map pages for kernel
  *MMU_PPN0 = 0x00;
  *MMU_PPN1 = 0x01;
  *MMU_PPN2 = 0x02;
  *MMU_PPN3 = 0x03;
  *MMU_PPN4 = 0x04;
  *MMU_PPN5 = 0x05;
  *MMU_PPN6 = 0x06;
  *MMU_PPN7 = 0x07;
  // k_print("MMU Initialized. System Ready.\n");
  // k_print("BB6502 Block Driver Test\n");
  // k_print("Reading Boot Sector (LBA 0)\n");
  if (block_read(0, block_buf)) {
  	k_print("block_read ERROR");
   	while (1);	// Hang on Boot Sector Read fail
  }

  // Print first 16 bytes as hex
  // k_print("First 16 bytes: ");
  // for (i = 0; i < 16; i++) {
  //   k_puthex(block_buf[i]);
  //   k_print(" ");
  // }
  // k_print("\n");

  // FAT16 boot sectors have $55 $AA at offset 510-511
  // k_print("Sig bytes (510,511): ");
  // k_puthex(block_buf[510]);
  // k_print(" ");
  // k_puthex(block_buf[511]);
  // k_print("\n");

  if (block_buf[510] == 0x55 && block_buf[511] == 0xAA) {
  	k_print("FAT boot signature OK\r\n");
  } else {
  	k_print("FAT boot signature MISSING\r\n");
  }

  k_print("Spawining hello.c\r\n");
  spawn_bbx(200, 1, 1);    // hello
  k_print("PROCESS struct for hello.c : -\r\n");
  k_print("\r\nstate: "); 						k_puthex(plist[0].state);
  k_print("\r\nlba: "); 							k_puthex(plist[0].lba);
  k_print("\r\nnblocks: "); 					k_puthex(plist[0].nblocks);
  k_print("\r\nsp: "); 								k_puthex(plist[0].SP);
  k_print("\r\nmmu_ppn_table:-\r\n");
  for (i = 0; i < 8; ++i) {
 		k_puthex(plist[0].mmu_ppn_table[i]);
   	k_print("\r\n");
  }
  k_print("Spawining hello2.c\r\n");
  spawn_bbx(210, 1, 3);    // hello2
  k_print("PROCESS struct for hello2.c : -\r\n");
  k_print("\r\nstate: "); 						k_puthex(plist[1].state);
  k_print("\r\nlba: "); 							k_puthex(plist[1].lba);
  k_print("\r\nnblocks: "); 					k_puthex(plist[1].nblocks);
  k_print("\r\nsp: "); 								k_puthex(plist[1].SP);
  k_print("\r\nmmu_ppn_table:-\r\n");
  for (i = 0; i < 8; ++i) {
 		k_puthex(plist[1].mmu_ppn_table[i]);
   	k_print("\r\n");
  }

  k_print("Starting scheduler...\r\n");
  sched_start();           // never returns

 	k_print("Program returned, hanging\n");
  while(1);
  return 0;
}
