#include <stdint.h>
#include "include/block.h"
#include "include/exec.h"
#include "include/kernel.h"

// Syscall ABI in zero page
#define SYS_NUM_PTR   (*(volatile uint8_t*)0x30)
#define SYS_NUM				(*(volatile uint8_t*)0x32)
#define SYS_RET       (*(volatile uint8_t*)0x33)
#define SYS_ARG0_LO   (*(volatile uint8_t*)0x34)
#define SYS_ARG0_HI   (*(volatile uint8_t*)0x35)
#define SYS_ARG1_LO   (*(volatile uint8_t*)0x36)
#define SYS_ARG1_HI   (*(volatile uint8_t*)0x37)
#define SYS_ARG2_LO   (*(volatile uint8_t*)0x38)
#define SYS_ARG2_HI   (*(volatile uint8_t*)0x39)
#define SYS_A_REG     (*(volatile uint8_t*)0x40)   // for syscalls returning a byte

#define ACIA_DATA    (*(volatile uint8_t*)0x8000)
#define ACIA_STATUS  (*(volatile uint8_t*)0x8001)
#define GPU_DATA     (*(volatile uint8_t*)0x8002)
#define GPU_STATUS   (*(volatile uint8_t*)0x8003)

#define ENOSYS  0xFF

// Syscall numbers
enum {
  SYS_EXIT         = 1,
  SYS_PUTC         = 2,
  SYS_GETC         = 3,
  SYS_PUTS         = 4,
  SYS_BLOCK_READ   = 5,
  SYS_BLOCK_WRITE  = 6,
  SYS_EXEC         = 7,
  SYS_GETC_NB      = 8,
  SYS_OPEN_FAT     = 9,
  SYS_READ_FAT     = 10,
};

static void do_exit(void) {
  __asm__("sei");
  while (1);
}

static void do_putc(void) {
	k_putc(SYS_A_REG);
	k_gputc(SYS_A_REG);
  SYS_RET = 0;
}

// ?? UNIMPLEMENTED K_EQUIVALENT
static void do_getc(void) {
  while (!(ACIA_STATUS & 0x01));    // wait for RX ready (your ACIA: bit 0 = RX has data)
  SYS_A_REG = ACIA_DATA;
  SYS_RET = 0;
}

static void do_puts(void) {
	k_print((uint8_t*)(SYS_ARG0_LO | (SYS_ARG0_HI << 8)));
  SYS_RET = 0;
}

static void do_block_read(void) {
  uint32_t lba = SYS_ARG0_LO | (SYS_ARG0_HI << 8);
  uint8_t* buf = (uint8_t*)(SYS_ARG1_LO | (SYS_ARG1_HI << 8));
  SYS_RET = block_read(lba, buf);
}

static void do_block_write(void) {
  uint32_t lba = SYS_ARG0_LO | (SYS_ARG0_HI << 8);
  uint8_t* buf = (uint8_t*)(SYS_ARG1_LO | (SYS_ARG1_HI << 8));
  SYS_RET = block_write(lba, buf);
}

extern uint8_t exec_bbx(uint32_t lba, uint16_t nblocks);

static void do_exec(void) {
  uint32_t lba = SYS_ARG0_LO | (SYS_ARG0_HI << 8);
  uint16_t nblocks = SYS_ARG1_LO | (SYS_ARG1_HI << 8);
  SYS_RET = exec_bbx(lba, nblocks);
}

static void do_getc_nb(void) {
  if (ACIA_STATUS & 0x01) {
    SYS_A_REG = ACIA_DATA;
    SYS_RET = 0;
  } else {
    SYS_A_REG = 0;
    SYS_RET = 1;                   // 1 = no data available
  }
}

static void do_enosys(void) {
  SYS_RET = ENOSYS;
}

void syscall_dispatch(void) {
  switch (SYS_NUM) {
    case SYS_EXIT:         do_exit();        break;
    case SYS_PUTC:         do_putc();        break;
    case SYS_GETC:         do_getc();        break;
    case SYS_PUTS:         do_puts();        break;
    case SYS_BLOCK_READ:   do_block_read();  break;
    case SYS_BLOCK_WRITE:  do_block_write(); break;
    case SYS_EXEC:         do_exec();        break;
    case SYS_GETC_NB:      do_getc_nb();     break;
    case SYS_OPEN_FAT:
    case SYS_READ_FAT:     do_enosys();      break;
    default:               SYS_RET = ENOSYS; break;
  }
}
