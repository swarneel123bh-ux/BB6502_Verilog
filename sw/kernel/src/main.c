#include <stdint.h>
#include "include/kernel.h"
#include "include/block.h"
#include "include/exec.h"
#include "include/devices.h"


void k_putc(char c) {
  while (!(*ACIA_STATUS & 0x01)); // Wait for ACIA TX ready
  *ACIA_DATA = c;
}

void k_gputc(char c) {
  while (!(*GPU_STATUS & 0x01)); // Wait for GPU TX ready
  *GPU_DATA = c;
}

void k_print(char* str) {
  while (*str) {
	 	k_putc(*str);
	  k_gputc(*str);
	  str++;
  }
}

void k_puthex(uint8_t b) {
	const char *alphabet = "0123456789ABCDEF";
	k_putc(alphabet[b >> 4]);			// High nibble
	k_gputc(alphabet[b >> 4]);		// High nibble
	k_putc(alphabet[b & 0x0F]); 	// Low nibble
	k_gputc(alphabet[b & 0x0F]); 	// Low nibble
}

static uint8_t block_buf[BLOCK_SIZE];


// _brk_handler
extern void brk_handler(void);

int main(void) {
	uint8_t i;

	// Install the brk_handler
	*(uint8_t*)0xFE = (uint8_t)((uint16_t)brk_handler);				// LOW BYTE
	*(uint8_t*)0xFF = (uint8_t)((uint16_t)brk_handler >> 8);	// HIGH BYTE

  k_print("Kernel Booting...\n");
  // Identity map Page 1 to PPN 1 via MMU
  *MMU_PPN1 = 0x01;
  k_print("MMU Initialized. System Ready.\n");
  k_print("BB6502 Block Driver Test\n");
  k_print("Reading Boot Sector (LBA 0)\n");
  if (block_read(0, block_buf)) {
  	k_print("ERROR");
   	while (1);	// Hang on Boot Sector Read fail
  }

  // Print first 16 bytes as hex
  k_print("First 16 bytes: ");
  for (i = 0; i < 16; i++) {
    k_puthex(block_buf[i]);
    k_print(" ");
  }
  k_print("\n");

  // FAT16 boot sectors have $55 $AA at offset 510-511
  k_print("Sig bytes (510,511): ");
  k_puthex(block_buf[510]);
  k_print(" ");
  k_puthex(block_buf[511]);
  k_print("\n");

  if (block_buf[510] == 0x55 && block_buf[511] == 0xAA) {
  	k_print("FAT boot signature OK\r\n");
  } else {
  	k_print("FAT boot signature MISSING\r\n");
  }

  // Try executing a program at LBA 200 (HELLO.BBX MUST BE THERE)
  k_print("Loading a program from LBA200\n");
  exec_bbx(200, 1);

 	k_print("Program returned, hanging\n");
  while(1);
  return 0;
}
