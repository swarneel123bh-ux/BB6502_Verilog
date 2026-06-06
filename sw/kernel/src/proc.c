#include "include/proc.h"
#include "include/kernel.h"
#include <stdint.h>

uint8_t nprocs;						// Number of processes in system
uint8_t plist_idx;				// Index into the list
PROCESS plist[8];					// Will stay empty for now

void process_init(void) {
  if (nprocs >= 8) {
    k_print("[Kernel] Error: Too many processes\n");
    return;
  }
  plist[nprocs].state     = PROC_STATE_WAITING;
  plist[nprocs].exit_code = 0;
  plist[nprocs].name[0]   = 0;
  nprocs++;
}

// Currently round robin scheduler
// NOTE: On yield, the scheduler AUTOMATICALLY dispatches
// the next process as the brk_handler will jump to do_yield
// which reloads after scheduler runs
//
// NOTE: We WILL need to call dispatch process
// in case the process has terminated. But for now the dispatch
// process function need not be used.

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

//	if (plist[(++plist_idx) % nprocs].state == PROC_STATE_WAITING) {
//		next_process = plist[plist_idx % nprocs];
//	} else {
//		plist_idx = (plist_idx + 1) % nprocs;	// Skip if the process is NOT WAITING
//	}
//}

// Unimplemented as of now
void dispatch_current_process() {
	// process_save(&current_process);
	// schedule_process();
	// process_restore(&next_process);
}
