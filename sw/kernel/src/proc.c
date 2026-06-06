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

// Load a BBX into the process's private pages, fabricate its first
// rti frame, fill the PCB, register it. Does NOT run it.
// base = first physical page; ppn[k] = base + k.
uint8_t spawn_bbx(uint32_t lba, uint16_t nblocks, uint8_t base) {
  PROCESS *p;
  uint16_t load, entry, b;
  uint8_t i;
  volatile uint8_t *f;

  if (nprocs >= 4) {
    k_print("spawn: too many procs\r\n");
    return 1;
  }
  p = &plist[nprocs];

  // record the process's page table
  // Test process should fit in a single page
  // so identity map everything else
  p->mmu_ppn_table[0] = base;
  for (i = 1; i < 8; i++) {
    p->mmu_ppn_table[i] = base + i;
    PPN[i] = base + i;
  }

  // first sector: validate + grab entry
  if (block_read(lba, block_buf)) {
    k_print("spawn: read fail\r\n");
    return 1;
  }
  if (block_buf[0] != 0x42 || block_buf[1] != 0x58) {
    k_print("spawn: bad BBX magic\r\n");
    return 2;
  }
  load = block_buf[2] | (block_buf[3] << 8);
  entry = block_buf[4] | (block_buf[5] << 8);
  memcpy512(((void*)load), block_buf);

  // remaining sectors (program must fit in pages 1..7 = 28KB)
  for (b = 1; b < nblocks; b++) {
    if (block_read(lba + b, block_buf)) {
      k_print("spawn: read fail\r\n");
      return 1;
    }
    memcpy512((void*)(load + (uint16_t)(b << 9)), block_buf);
  }

  // fabricate first rti frame on the process's stack page.
  // point ppn[1] at the stack page (base); $11FA == stack $01FA in that page.
  PPN[1] = base;
  f = (volatile uint8_t*)(0x11FA);
  f[0] = 0;                       // Y   (pulled by yield_rti, don't-care)
  f[1] = 0;                       // X
  f[2] = 0;                       // A
  f[3] = 0x20;                    // status: I clear, bit5 set
  f[4] = (uint8_t)entry;          // PCL
  f[5] = (uint8_t)(entry >> 8);   // PCH

  // restore boot identity for pages 1..7 (kernel only uses page 0 anyway)
  for (i = 1; i < 8; i++) {
    PPN[i] = i;
  }

  p->state     = PROC_STATE_WAITING;
  p->exit_code = 0;
  p->lba       = (uint8_t)lba;
  p->nblocks   = (uint8_t)nblocks;
  p->SP        = 0xF9;            // points below the 6-byte frame
  p->name[0]   = 0;
  nprocs++;
  return 0;
}
