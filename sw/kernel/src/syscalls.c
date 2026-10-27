#include <stdint.h>
#include "include/block.h"
#include "include/kernel.h"
#include "include/devices.h"

// ============================================================================
// Syscall dispatch. Runs in KERNEL MODE, where the MMU bypasses translation,
// so every address used here is PHYSICAL.
//
// Two distinct sources of data:
//   * Syscall NUMBER  -> placed in the KERNEL's zero page ($32) by brk.s
//                        (extracted from the inline byte after BRK). Read it
//                        straight from kernel ZP, no translation.
//   * Syscall ARGS    -> written by the user into the USER's zero page while
//                        still in user mode. The user's ABI slots ($33.. by
//                        default, SYS_ABI_BASE) live in the physical page
//                        behind the user's virtual page 0 = (MMU_PPN0 << 10)
//                        | offset. They are NOT visible at the kernel's own $33..
//
// Pointer payloads (e.g. the puts string) are USER VIRTUAL addresses. They are
// translated by the POINTER'S OWN page, i.e. MMU_PPN[(va>>10)&31],
// not blindly through PPN0.
// ============================================================================

// Number lives in kernel ZP (brk.s wrote it there). Plain value, no xlate.
#define SYS_NUM       (*(volatile uint8_t*)0x32)

// ABI slot addresses within the USER's zero page. SYS_ABI_BASE comes from
// common.mk (cc65 -D); the offsets must match sw/prog/src/syslib.s.
#ifndef SYS_ABI_BASE
#error "SYS_ABI_BASE not defined: build through the Makefile (common.mk)"
#endif
#define OFF_RET       (SYS_ABI_BASE + 0x03)
#define OFF_ARG0_LO   (SYS_ABI_BASE + 0x04)
#define OFF_ARG0_HI   (SYS_ABI_BASE + 0x05)
#define OFF_ARG1_LO   (SYS_ABI_BASE + 0x06)
#define OFF_ARG1_HI   (SYS_ABI_BASE + 0x07)
#define OFF_ARG2_LO   (SYS_ABI_BASE + 0x08)
#define OFF_ARG2_HI   (SYS_ABI_BASE + 0x09)
#define OFF_A_REG     (SYS_ABI_BASE + 0x10)   // byte in/out slot

#define ENOSYS  0xFF

// Syscall numbers
enum {
  SYS_YIELD          = 0,  // handled entirely in yield.s; never reaches here
  SYS_EXIT           = 1,  // halts the machine for now (SEI + spin)
  SYS_PUTC           = 2,
  SYS_GETC           = 3,
  SYS_PUTS           = 4,
  SYS_BLOCK_READ     = 5,
  SYS_BLOCK_WRITE    = 6,
  SYS_EXEC           = 7,  // reserved, not implemented (returns ENOSYS)
  SYS_GETC_NB        = 8,
  SYS_OPEN_FAT       = 9,  // reserved, not implemented (returns ENOSYS)
  SYS_READ_FAT       = 10, // reserved, not implemented (returns ENOSYS)
  SYS_PROCESS_CREATE = 11  // reserved, not implemented (returns ENOSYS)
};

// ---- address-space helpers --------------------------------------------------
// MMU_PPN0 is the base of the 32 contiguous PPN registers ($8080..$809F), so
// MMU_PPN0[v] is the physical page mapped to the user's virtual page v
// (1 KB pages: v = VA[14:10]).
// These registers still hold the *user's* mapping while we are in the handler.

// Physical address of a slot in the user's zero page (always virtual page 0).
static volatile uint8_t* u_zp(uint8_t off) {
  return (volatile uint8_t*)(((uint16_t)*MMU_PPN0 << MMU_PAGE_SHIFT) | off);
}

// Translate an arbitrary user VIRTUAL address to its physical address, using
// the page register selected by the address's own top bits.
// NOTE: only the start is translated. A buffer that crosses a 1 KB virtual
// page boundary is NOT physically contiguous -- see do_block_* below.
static uint8_t* u_ptr(uint16_t va) {
  uint8_t page = MMU_PPN0[(va >> MMU_PAGE_SHIFT) & (MMU_NPAGES - 1)];
  return (uint8_t*)(((uint16_t)page << MMU_PAGE_SHIFT) | (va & MMU_PAGE_MASK));
}

// Assemble a 16-bit user pointer from two user-ZP arg slots.
static uint16_t u_arg(uint8_t off_lo, uint8_t off_hi) {
  return (uint16_t)(*u_zp(off_lo)) | ((uint16_t)(*u_zp(off_hi)) << 8);
}

// ---- syscalls ---------------------------------------------------------------

static void do_exit(void) {
  // TODO: reclaim this process's pages and pick another in the scheduler.
  __asm__("sei");
  while (1);
}

static void do_putc(void) {
  uint8_t c = *u_zp(OFF_A_REG);   // char passed by value in the user's A_REG slot
  k_putc(c);
  k_gputc(c);
  *u_zp(OFF_RET) = 0;
}

static void do_getc(void) {
  while (!(*ACIA_STATUS & 0x01));   // bit0 = RX has data
  *u_zp(OFF_A_REG) = *ACIA_DATA;
  *u_zp(OFF_RET)   = 0;
}

static void do_puts(void) {
  uint16_t va = u_arg(OFF_ARG0_LO, OFF_ARG0_HI);   // user virtual string ptr
  k_print((char*)u_ptr(va));                        // translate to physical
  *u_zp(OFF_RET) = 0;
}

static void do_block_read(void) {
  uint32_t lba = u_arg(OFF_ARG0_LO, OFF_ARG0_HI);
  uint8_t* buf = u_ptr(u_arg(OFF_ARG1_LO, OFF_ARG1_HI));
  // WARNING: buf must not cross a 1 KB virtual-page boundary, or the tail of
  // the 512-byte transfer lands in the wrong physical page. Enforce alignment
  // in the user ABI, or make block_read translate per-page.
  *u_zp(OFF_RET) = block_read(lba, buf);
}

static void do_block_write(void) {
  uint32_t lba = u_arg(OFF_ARG0_LO, OFF_ARG0_HI);
  uint8_t* buf = u_ptr(u_arg(OFF_ARG1_LO, OFF_ARG1_HI));
  // Same page-crossing caveat as do_block_read.
  *u_zp(OFF_RET) = block_write(lba, buf);
}

static void do_getc_nb(void) {
  if (*ACIA_STATUS & 0x01) {
    *u_zp(OFF_A_REG) = *ACIA_DATA;
    *u_zp(OFF_RET)   = 0;
  } else {
    *u_zp(OFF_A_REG) = 0;
    *u_zp(OFF_RET)   = 1;            // 1 = no data available
  }
}

static void do_enosys(void) {
  *u_zp(OFF_RET) = ENOSYS;
}

void syscall_dispatch(void) {
  switch (SYS_NUM) {
    case SYS_EXIT:         do_exit();        break;
    case SYS_PUTC:         do_putc();        break;
    case SYS_GETC:         do_getc();        break;
    case SYS_PUTS:         do_puts();        break;
    case SYS_BLOCK_READ:   do_block_read();  break;
    case SYS_BLOCK_WRITE:  do_block_write(); break;
    case SYS_GETC_NB:      do_getc_nb();     break;
    case SYS_OPEN_FAT:
    case SYS_READ_FAT:     do_enosys();      break;
    default:               *u_zp(OFF_RET) = ENOSYS; break;
  }
}
