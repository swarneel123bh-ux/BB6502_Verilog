#include "include/block.h"
#include <stdint.h>

// Register addresses
#define DISK_LBA0    (*(volatile uint8_t*)0x80E0)
#define DISK_LBA1    (*(volatile uint8_t*)0x80E1)
#define DISK_LBA2    (*(volatile uint8_t*)0x80E2)
#define DISK_LBA3    (*(volatile uint8_t*)0x80E3)
#define DISK_CMD     (*(volatile uint8_t*)0x80E4)
#define DISK_STATUS  (*(volatile uint8_t*)0x80E5)
#define DISK_DATA    (*(volatile uint8_t*)0x80E6)
#define DISK_DPTR    (*(volatile uint8_t*)0x80E7)

// Commands for the controller
#define CMD_READ     0x01
#define CMD_WRITE    0x02
#define STATUS_BUSY  0x01
#define STATUS_ERR   0x80

static void set_lba(uint32_t lba) {
  DISK_LBA0 = (uint8_t)(lba);
  DISK_LBA1 = (uint8_t)(lba >> 8);
  DISK_LBA2 = (uint8_t)(lba >> 16);
  DISK_LBA3 = (uint8_t)(lba >> 24);
}

#pragma bss-name(push, "ZEROPAGE")
static uint8_t* zp_ptr;
#pragma bss-name(pop)

uint8_t block_read(uint32_t lba, uint8_t* buf) {
  set_lba(lba);

  DISK_CMD = CMD_READ;
  while (DISK_STATUS & STATUS_BUSY);
  if (DISK_STATUS & STATUS_ERR)
    return 1;

  DISK_DPTR = 0;
  zp_ptr = buf;

  asm(
      "ldy #$00\n"
      "ldx #$02\n"

      "drain_pg:\n"

      "lda $80E6\n"
      "sta (_zp_ptr),y\n"

      "iny\n"
      "bne drain_pg\n"

      "inc _zp_ptr+1\n"

      "dex\n"
      "bne drain_pg\n"

      "dec _zp_ptr+1\n"
      "dec _zp_ptr+1\n"
  );

  return 0;
}

uint8_t block_write(uint32_t lba, const uint8_t* buf) {
	uint16_t i;

  DISK_DPTR = 0;
  for (i = 0; i < BLOCK_SIZE; i++)
    DISK_DATA = buf[i];
  set_lba(lba);
  DISK_CMD = CMD_WRITE;
  while (DISK_STATUS & STATUS_BUSY);
  if (DISK_STATUS & STATUS_ERR) return 1;
  return 0;
}
