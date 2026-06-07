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
  uint16_t b, entry, virt_addr, phys;
  uint8_t i;
  volatile uint8_t *f;

  if (nprocs >= 4) {
    k_print("spawn: too many procs\r\n");
    return 1;
  }
  p = &plist[nprocs];

  for (i = 0; i < 8; i++) {
    p->mmu_ppn_table[i] = base + i;
  }

  if (block_read(lba, block_buf)) {
    k_print("spawn: read fail\r\n");
    return 1;
  }
  if (block_buf[0] != 0x42 || block_buf[1] != 0x58) {
    k_print("spawn: bad BBX magic\r\n");
    return 2;
  }
  entry = block_buf[4] | (block_buf[5] << 8);

  // No translation in kernel mode: write the child's pages by physical address.
  for (b = 0; b < nblocks; b++) {
    if (b != 0) {
      if (block_read(lba + b, block_buf)) {
        k_print("spawn: read fail\r\n");
        return 1;
      }
    }
    virt_addr = 0x1000 + (b << 9);
    phys = ((uint16_t)(base + (virt_addr >> 12)) << 12) | (virt_addr & 0x0FFF);
    memcpy512((void*)phys, block_buf);
  }

  // RTI frame on the child's stack page (vpage0 -> physical 'base').
  // SP+1/+2/+3 = status/PCL/PCH for the resume rti; SP = $FC.
  f = (volatile uint8_t*)(((uint16_t)base << 12) | 0x01FD);
  f[0] = 0x20;                    // status (bit5 set, I clear)
  f[1] = (uint8_t)entry;          // PCL
  f[2] = (uint8_t)(entry >> 8);   // PCH

  p->state     = PROC_STATE_WAITING;
  p->exit_code = 0;
  p->lba       = (uint8_t)lba;
  p->nblocks   = (uint8_t)nblocks;
  p->SP        = 0xFC;
  p->name[0]   = 0;

  nprocs++;
  return 0;
}
