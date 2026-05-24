#include <stdint.h>
#include "block.h"

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


static void k_putc(char c) {
  while (!(*ACIA_STATUS & 0x01)); // Wait for ACIA TX ready
  *ACIA_DATA = c;
}

static void k_gputc(char c) {
  while (!(*GPU_STATUS & 0x01)); // Wait for GPU TX ready
  *GPU_DATA = c;
}

static void k_print(char* str) {
  while (*str) {
	 	k_putc(*str);
	  k_gputc(*str);
	  str++;
  }
}

static void k_puthex(uint8_t b) {
	const char *alphabet = "0123456789ABCDEF";
	k_putc(alphabet[b >> 4]);			// High nibble
	k_gputc(alphabet[b >> 4]);		// High nibble
	k_putc(alphabet[b & 0x0F]); 	// Low nibble
	k_gputc(alphabet[b & 0x0F]); 	// Low nibble
}

static uint8_t block_buf[BLOCK_SIZE];

// Loads a program and executes it
// Returns 0 on success, nonzero on error.
// 'lba' is the disk LBA where the BBX file begins.
// 'nblocks' is how many 512-byte blocks to read.
static uint8_t exec_bbx(uint32_t lba, uint16_t nblocks) {
  static uint8_t sector[512];
  uint16_t load_addr;
  uint16_t entry;
  uint8_t* dest;
  uint16_t i;
  uint16_t b;

  // Read first sector to validate header
  if (block_read(lba, sector)) {
    k_print("exec: block_read failed\r\n");
    return 1;
  }
  if (sector[0] != 0x42 || sector[1] != 0x58) {
    k_print("exec: bad BBX magic\r\n");
    return 2;
  }
  load_addr = sector[2] | (sector[3] << 8);
  entry     = sector[4] | (sector[5] << 8);

  k_print("Loading at $");
  k_puthex((uint8_t)(load_addr >> 8));
  k_puthex((uint8_t)load_addr);
  k_print(", entry $");
  k_puthex((uint8_t)(entry >> 8));
  k_puthex((uint8_t)entry);
  k_print("\r\n");

  // Copy first sector's worth of program data (bytes past header) to load_addr.
  // BBX header is at the start of the file but is also part of the load image
  // because HDR sits at load_addr in the linker config — so copy the whole sector.
  dest = (uint8_t*)load_addr;
  for (i = 0; i < 512; i++) dest[i] = sector[i];

  // Copy remaining sectors
  for (b = 1; b < nblocks; b++) {
    if (block_read(lba + b, sector)) {
      k_print("exec: read sector failed\r\n");
      return 1;
    }
    for (i = 0; i < 512; i++)
      dest[b * 512 + i] = sector[i];
  }

  k_print("Executing...\r\n");
  // Call as a function pointer.
  ((void (*)(void))entry)();

  k_print("Returned from program.\r\n");
  return 0;
}

int main(void) {
	uint8_t i;

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
  exec_bbx(200, 1);   // up to 4 sectors = 2KB

 	k_print("Program returned, hanging\n");
  while(1);
  return 0;
}
