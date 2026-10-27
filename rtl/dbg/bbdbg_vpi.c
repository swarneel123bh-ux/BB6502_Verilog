// ============================================================================
// bbdbg_vpi.c — VPI glue between the Verilog testbench and the debugger
//
// Built into build/bbdbg.vpi and loaded by vvp:
//     vvp -M build -m bbdbg build/sim_dbg.vvp +dbg_sym=build/kernel.dbg ...
//
// It does two jobs:
//   1. Registers the system tasks that rtl/tb.v calls when built with -DBBDBG:
//        $bbdbg_fetch(pc, opcode)   once per instruction  -> dbgOnFetch()
//        $bbdbg_tx(byte)            ACIA TX write ($8000) -> dbgOnTx()
//        $bbdbg_fault(ab, we, pa)   MMU fault             -> dbgOnFault()
//   2. Implements the sim* interface from debugger.h by reading the model's
//      signals through VPI handles (looked up once by hierarchical name).
//
// Plusargs (after the .vvp file on the vvp command line):
//   +dbg_sym=<file>   ld65 --dbgfile output to load symbols from (repeatable)
//   +dbg_src=<file>   source file for the source pane (not implemented yet)
// ============================================================================
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <vpi_user.h>

#include "debugger.h"

#define MAX_SYM_FILES 16
#define RAM_WORDS     32768   // tb.ram  [0:32767]   physical RAM
#define ROM_WORDS     32512   // tb.rom  [0:32511]   CPU $8100-$FFFF
#define ROM_BASE      0x8100
#define PAGE_SHIFT    10      // MMU page size = 1 KB (rtl/mmu6502.v)
#define PAGE_MASK     0x03FF

// ─── Handles into the model (see rtl/tb.v, rtl/mmu6502.v, Arlet's cpu.v) ─────
static vpiHandle hRam;        // tb.ram                  physical RAM array
static vpiHandle hRom;        // tb.rom                  boot ROM array
static vpiHandle hRegs;       // tb.dut.regfile.regs     [0]=X [1]=Y [2]=A [3]=S
static vpiHandle hP;          // tb.dut.P                NV1BDIZC flags
static vpiHandle hMmuKernel;  // tb.mmu.kernel           1 = no translation
static vpiHandle hMmuPpn;     // tb.mmu.ppn              page table [0:31]
static vpiHandle hResetReq;   // tb.dbg_reset_req        debugger reset request

// Word handles are created on first use and kept (icarus hands out a new
// object per vpi_handle_by_index call).
static vpiHandle *ramWord, *romWord, regWord[4], ppnWord[SIM_MMU_NPAGES];

// Argument handles of the (single) call site of each task, cached
static vpiHandle fetchArgs[2], txArg, faultArgs[3];

static int nSymFiles;
static char *symFiles[MAX_SYM_FILES];
static char *srcFile;

static int readInt(vpiHandle h) {
  s_vpi_value v;
  v.format = vpiIntVal;
  vpi_get_value(h, &v);
  return v.value.integer; // x/z read as 0
}

static vpiHandle wordOf(vpiHandle array, vpiHandle *cache, int idx) {
  if (!cache[idx])
    cache[idx] = vpi_handle_by_index(array, idx);
  return cache[idx];
}

static vpiHandle lookup(const char *name, bool *ok) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)name, NULL);
  if (!h) {
    vpi_printf("[bbdbg] signal %s not found (was tb.v built with -DBBDBG?)\n",
               name);
    *ok = false;
  }
  return h;
}

// ─── sim* interface ──────────────────────────────────────────────────────────

bool simMmuIsKernel(void) { return readInt(hMmuKernel) & 1; }

uint8_t simMmuPpn(int vpage) {
  return (uint8_t)readInt(wordOf(hMmuPpn, ppnWord, vpage & (SIM_MMU_NPAGES - 1)));
}

// Same decode as the testbench's read mux: RAM goes through the MMU
// (identity in kernel mode, ppn[VA[14:10]] in user mode), ROM is direct.
bool simReadMem(uint16_t addr, uint8_t *out) {
  if (addr < 0x8000) {
    uint32_t paddr;
    if (simMmuIsKernel())
      paddr = addr;
    else
      paddr = ((uint32_t)simMmuPpn((addr >> PAGE_SHIFT) & (SIM_MMU_NPAGES - 1)) << PAGE_SHIFT)
              | (addr & PAGE_MASK);
    *out = (uint8_t)readInt(wordOf(hRam, ramWord, paddr & (RAM_WORDS - 1)));
    return true;
  }
  if (addr >= ROM_BASE) {
    *out = (uint8_t)readInt(wordOf(hRom, romWord, addr - ROM_BASE));
    return true;
  }
  return false; // $8000-$80FF I/O window
}

void simGetRegs(sim_regs_t *r) {
  r->x = (uint8_t)readInt(wordOf(hRegs, regWord, 0));
  r->y = (uint8_t)readInt(wordOf(hRegs, regWord, 1));
  r->a = (uint8_t)readInt(wordOf(hRegs, regWord, 2));
  r->sp = (uint8_t)readInt(wordOf(hRegs, regWord, 3));
  r->p = (uint8_t)readInt(hP);
}

void simRequestReset(void) {
  s_vpi_value v;
  v.format = vpiIntVal;
  v.value.integer = 1;
  vpi_put_value(hResetReq, &v, NULL, vpiNoDelay);
}

void simFinish(void) { vpi_control(vpiFinish, 0); }

// ─── System tasks ────────────────────────────────────────────────────────────

// Fill `out` with the first n argument handles of the current task call.
static void cacheArgs(vpiHandle *out, int n) {
  if (out[0])
    return;
  vpiHandle call = vpi_handle(vpiSysTfCall, NULL);
  vpiHandle it = vpi_iterate(vpiArgument, call);
  for (int i = 0; i < n && it; i++)
    out[i] = vpi_scan(it);
  if (it && out[n - 1])
    vpi_free_object(it); // iterator not exhausted
}

static PLI_INT32 fetchCalltf(PLI_BYTE8 *user) {
  (void)user;
  cacheArgs(fetchArgs, 2);
  dbgOnFetch((uint16_t)readInt(fetchArgs[0]), (uint8_t)readInt(fetchArgs[1]));
  return 0;
}

static PLI_INT32 txCalltf(PLI_BYTE8 *user) {
  (void)user;
  cacheArgs(&txArg, 1);
  dbgOnTx((uint8_t)readInt(txArg));
  return 0;
}

static PLI_INT32 faultCalltf(PLI_BYTE8 *user) {
  (void)user;
  cacheArgs(faultArgs, 3);
  dbgOnFault((uint16_t)readInt(faultArgs[0]), readInt(faultArgs[1]),
             (uint32_t)readInt(faultArgs[2]));
  return 0;
}

// ─── Simulation start / end ──────────────────────────────────────────────────

static void parsePlusargs(void) {
  s_vpi_vlog_info info;
  if (!vpi_get_vlog_info(&info))
    return;
  for (int i = 0; i < info.argc; i++) {
    const char *a = info.argv[i];
    if (!strncmp(a, "+dbg_sym=", 9) && nSymFiles < MAX_SYM_FILES)
      symFiles[nSymFiles++] = (char *)a + 9;
    else if (!strncmp(a, "+dbg_src=", 9))
      srcFile = (char *)a + 9;
  }
}

static PLI_INT32 startOfSim(p_cb_data cb) {
  (void)cb;
  bool ok = true;
  hRam = lookup("tb.ram", &ok);
  hRom = lookup("tb.rom", &ok);
  hRegs = lookup("tb.dut.regfile.regs", &ok);
  hP = lookup("tb.dut.P", &ok);
  hMmuKernel = lookup("tb.mmu.kernel", &ok);
  hMmuPpn = lookup("tb.mmu.ppn", &ok);
  hResetReq = lookup("tb.dbg_reset_req", &ok);
  ramWord = calloc(RAM_WORDS, sizeof(vpiHandle));
  romWord = calloc(ROM_WORDS, sizeof(vpiHandle));
  if (!ok || !ramWord || !romWord) {
    vpi_control(vpiFinish, 1);
    return 0;
  }

  parsePlusargs();
  if (!dbgInit(nSymFiles, symFiles, srcFile)) {
    vpi_printf("[bbdbg] debugger UI failed to start\n");
    vpi_control(vpiFinish, 1);
  }
  return 0;
}

static PLI_INT32 endOfSim(p_cb_data cb) {
  (void)cb;
  dbgCleanup();
  return 0;
}

static void registerTask(const char *name, PLI_INT32 (*calltf)(PLI_BYTE8 *)) {
  s_vpi_systf_data tf;
  memset(&tf, 0, sizeof(tf));
  tf.type = vpiSysTask;
  tf.tfname = name;
  tf.calltf = calltf;
  vpi_register_systf(&tf);
}

static void registerCallback(PLI_INT32 reason, PLI_INT32 (*fn)(p_cb_data)) {
  s_cb_data cb;
  memset(&cb, 0, sizeof(cb));
  cb.reason = reason;
  cb.cb_rtn = fn;
  vpi_register_cb(&cb);
}

static void bbdbgRegister(void) {
  registerTask("$bbdbg_fetch", fetchCalltf);
  registerTask("$bbdbg_tx", txCalltf);
  registerTask("$bbdbg_fault", faultCalltf);
  registerCallback(cbStartOfSimulation, startOfSim);
  registerCallback(cbEndOfSimulation, endOfSim);
}

// vvp calls every function in this table when it loads the module
void (*vlog_startup_routines[])(void) = {bbdbgRegister, 0};
