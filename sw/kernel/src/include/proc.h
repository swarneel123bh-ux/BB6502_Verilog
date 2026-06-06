#ifndef PROC_H
#define PROC_H

#include <stdint.h>

#define PROC_STATE_EXITED 	0
#define PROC_STATE_WAITING 	1
#define PROC_STATE_RUNNING 	2
// NEED TO ADD MORE STATES FOR MULTITASKING

#define PROC_NAME_MAX 8

typedef struct process_struct {
  uint8_t state, exit_code, lba, nblocks;
  char name[PROC_NAME_MAX+1];   // offsets 4..12
  uint8_t SP;                   // offset 13
  uint8_t mmu_ppn_table[8];     // offsets 14..21
  uint8_t _pad[10];             // pad to 32
} PROCESS;
// typedef char _proc_size_check[(sizeof(PROCESS) == 32) ? 1 : -1];
extern PROCESS plist[4];	// only 4 for now, later redefine to 8
extern uint8_t block_buf[512];
extern uint8_t plist_idx;
extern uint8_t nprocs;

void process_init(void);
void dispatch_current_process(void);
uint8_t spawn_bbx(uint32_t lba, uint16_t nblocks, uint8_t base);
void schedule_process(void);	// For now, unused
extern void sched_start(void);
// void process_set_current(uint8_t index);
// Assembly functions
//extern void process_save(PROCESS* p);
//extern void process_restore(PROCESS* p);

#endif
