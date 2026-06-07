#include <stdint.h>
#include "include/proc.h"
#include "include/kernel.h"
#include "include/block.h"
#include "include/fastmem.h"

uint8_t nprocs;
uint8_t plist_idx;
PROCESS plist[4];                 // 4 is enough for the test; 128B BSS (was 256)
uint8_t block_buf[512];           // shared disk buffer (was two separate 512B bufs)

static volatile uint8_t *const PPN = (uint8_t*)0x80F0;   // ppn[0..7] = $80F0..$80F7
#define MMU_U_BITS (*(volatile uint8_t*)0x80F9)
#define MMU_W_BITS (*(volatile uint8_t*)0x80F8)

void schedule_process(void) {
  uint8_t i, idx;
  for (i = 1; i <= nprocs; i++) {
    idx = (plist_idx + i) % nprocs;
    if (plist[idx].state == PROC_STATE_WAITING) {
      plist_idx = idx;
      return;
    }
  }
}

uint8_t spawn_bbx(uint32_t lba, uint16_t nblocks, uint8_t base) {
  PROCESS *p;
  uint16_t b, entry, virt_addr;
  uint8_t i, page_offset;
  volatile uint8_t *f;

  if (nprocs >= 4) {
    k_print("spawn: too many procs\r\n");
    return 1;
  }
  p = &plist[nprocs];

  // 1. Populate the process page table entries (Safe in normal space)
  for (i = 0; i < 8; i++) {
  	p->mmu_ppn_table[i] = base + i;
  }

  // 2. Read first sector while MMU is completely normal
  if (block_read(lba, block_buf)) {
    k_print("spawn: read fail\r\n");
    return 1;
  }
  if (block_buf[0] != 0x42 || block_buf[1] != 0x58) {
    k_print("spawn: bad BBX magic\r\n");
    return 2;
  }
  entry = block_buf[4] | (block_buf[5] << 8);

  // 3. Copy each block to child-virtual ($1000 + b*512) via the Bank 1 window.
  //    User BBX loads at virtual $1000 (page 1) per prog.cfg.
  //    block_buf already holds block 0 from above; re-read for b > 0.
  for (b = 0; b < nblocks; b++) {
    if (b != 0) {
      if (block_read(lba + b, block_buf)) {
        k_print("spawn: read fail\r\n");
        return 1;
      }
    }
    virt_addr   = 0x1000 + (b << 9);          // b * 512 within the user image
    page_offset = (uint8_t)(virt_addr >> 12); // virtual page 1..7
    PPN[1] = base + page_offset;
    memcpy512((void*)(0x1000 + (virt_addr & 0x0FFF)), block_buf);
    PPN[1] = 1; // RESTORE IMMEDIATELY
  }

  // 4. Fabricate the RTI frame on the child's STACK page.
  // The stack ($0100-$01FF) is virtual page 0 -> physical page 'base'.
  // Map 'base' to our Bank 1 window, stamp the frame at $11FA, and restore.
  PPN[1] = base;
  f = (volatile uint8_t*)(0x11FA);
  f[0] = 0;        // Y
  f[1] = 0;        // X
  f[2] = 0;        // A
  f[3] = 0x20;     // Status: I clear, bit5 set
  f[4] = (uint8_t)entry;
  f[5] = (uint8_t)(entry >> 8);
  PPN[1] = 1; // RESTORE IMMEDIATELY

  // 6. Complete PCB configuration safely in a completely stable MMU state
  p->state     = PROC_STATE_WAITING;
  p->exit_code = 0;
  p->lba       = (uint8_t)lba;
  p->nblocks   = (uint8_t)nblocks;
  p->SP        = 0xF9;
  p->name[0]   = 0;

  nprocs++;
  return 0;
}
