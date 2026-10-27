// ==========================================================================
// proc.c — process table, round-robin scheduler, BBX loader
//
// plist[] holds up to 4 PROCESS entries (64 bytes each, layout shared
// with yield.s). spawn_bbx loads a program from disk, builds an RTI frame
// on its stack page and marks it WAITING. schedule_process picks the next
// WAITING process after plist_idx. The context switch itself is in yield.s.
//
// Memory (1 KB MMU pages, 32 per address space): `base` still names a
// 4 KB block of physical RAM, as before the MMU moved to 1 KB pages.
// spawn_bbx maps old 4 KB virtual page k to the four 1 KB physical pages
// of block (base + k) & 7, so every byte lands where it used to.
//
// Known limitation: `base + k` wraps (e.g. base 3 maps virtual $5000-$7FFF
// onto physical $0000-$2FFF, the kernel's), and sched_start opens every
// page to user mode. There is no isolation between processes or from the
// kernel yet; a page allocator is the next step.
// ==========================================================================
#include <stdint.h>
#include "include/proc.h"
#include "include/kernel.h"
#include "include/block.h"
#include "include/fastmem.h"
#include "include/devices.h"

uint8_t nprocs;
uint8_t plist_idx;
// The process table and the disk buffer live in the kernel's high page
// ($7000+, segment KHIBSS in kernel.cfg) to keep page 0 free for code.
#pragma bss-name (push, "KHIBSS")
PROCESS plist[4];                 // 4 x 64 B
uint8_t block_buf[512];           // shared disk buffer (was two separate 512B bufs)
#pragma bss-name (pop)

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

  // 1 KB virtual page i lies in old 4 KB page i >> 2; map it to the
  // matching quarter of physical 4 KB block (base + (i >> 2)) & 7.
  for (i = 0; i < MMU_NPAGES; i++) {
    p->mmu_ppn_table[i] = (uint8_t)((((base + (i >> 2)) & 7) << 2) | (i & 3));
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
    // Translate through the new page table. A 512-byte block never crosses
    // a 1 KB page here (virt_addr is 512-aligned), so one lookup is enough.
    phys = ((uint16_t)p->mmu_ppn_table[virt_addr >> MMU_PAGE_SHIFT] << MMU_PAGE_SHIFT)
           | (virt_addr & MMU_PAGE_MASK);
    memcpy512((void*)phys, block_buf);
  }

  // RTI frame on the child's stack page (virtual page 0, holding $0100-$01FF).
  // SP+1/+2/+3 = status/PCL/PCH for the resume rti; SP = $FC.
  f = (volatile uint8_t*)(((uint16_t)p->mmu_ppn_table[0] << MMU_PAGE_SHIFT) | 0x01FD);
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
