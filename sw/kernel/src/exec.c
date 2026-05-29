#include <stdint.h>
#include "include/fastmem.h"
#include "include/kernel.h"
#include "include/exec.h"
#include "include/block.h"

// Loads a program and executes it
// Returns 0 on success, nonzero on error.
// 'lba' is the disk LBA where the BBX file begins.
// 'nblocks' is how many 512-byte blocks to read.
uint8_t exec_bbx(uint32_t lba, uint16_t nblocks) {
  static uint8_t sector[512];
  uint16_t load_addr;
  uint16_t entry;
  uint16_t b;

  // Read first sector to validate header
  k_print("R\n");
  if (block_read(lba, sector)) {
    k_print("exec: block_read failed\r\n");
    return 1;
  }
  k_print("D\n");

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
  memcpy512((void*)((uint8_t*)load_addr), (const void*)sector);

  // Copy remaining sectors
  for (b = 1; b < nblocks; b++) {
  	if (block_read(lba + b, sector)) {
      k_print("exec: read sector failed\r\n");
      return 1;
    }
    memcpy512((void*)((uint8_t*)load_addr + ((uint16_t)b << 9)), (const void*)sector);
  }

  k_print("Executing...\r\n");
  ((void (*)(void))entry)();
  k_print("Returned from program.\r\n");
  return 0;
}
