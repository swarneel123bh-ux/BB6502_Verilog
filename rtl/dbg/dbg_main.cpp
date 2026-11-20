// ============================================================================
// dbg_main.cpp — the BB6502 debugger harness (Verilator)
//
// Builds into build/dbgsim/Vtb. It drives the Verilog system (rtl/tb.v) one
// half-clock at a time and calls the debugger (rtl/dbg/debugger.c) at the same
// points the debugger needs:
//   - negedge after a posedge that latched an instruction fetch -> dbgOnFetch
//   - posedge with an ACIA TX write                              -> dbgOnTx
//   - posedge with an MMU fault                                  -> dbgOnFault
// While the debugger is stopped, this loop is blocked, so simulated time is
// frozen while the debugger is stopped.
//
// The simulator interface (sim*) reads the model's signals directly through
// Verilator's public accessors (built with --public-flat-rw).
//
// Plusargs: +dbg_sym=<file> (repeatable), +dbg_src=<file>
// ============================================================================
#include <cstdint>
#include <cstdio>
#include <cstring>

#include "Vtb.h"
#include "Vtb___024root.h"
#include "verilated.h"

extern "C" {
#include "debugger.h"   // sim_regs_t, sim* and dbg* prototypes, ncurses
}

#define MAX_SYM_FILES 16

static Vtb *top;
static Vtb___024root *R;
static VerilatedContext *ctx;
static bool quitRequested = false;

// ─── sim* interface (declared in debugger.h) ─────────────────────────────────

extern "C" bool simMmuIsKernel(void) { return R->tb__DOT__mmu__DOT__kernel & 1; }

extern "C" uint8_t simMmuPpn(int vpage) {
  return (uint8_t)R->tb__DOT__mmu__DOT__ppn[vpage & (SIM_MMU_NPAGES - 1)];
}

// Same decode as the testbench's read mux: RAM goes through the MMU (identity
// in kernel mode, ppn[VA[14:10]] in user mode), the boot ROM is direct, and the
// $8000-$80FF I/O window is not read (device registers have side effects).
extern "C" bool simReadMem(uint16_t addr, uint8_t *out) {
  if (addr < 0x8000) {
    uint32_t paddr;
    if (simMmuIsKernel())
      paddr = addr;
    else
      paddr = ((uint32_t)simMmuPpn((addr >> 10) & (SIM_MMU_NPAGES - 1)) << 10) | (addr & 0x03FF);
    *out = R->tb__DOT__ram[paddr & 0x7FFF];
    return true;
  }
  if (addr >= 0x8100) {
    *out = R->tb__DOT__rom[addr - 0x8100];
    return true;
  }
  return false;
}

extern "C" void simGetRegs(sim_regs_t *r) {
  r->x = (uint8_t)R->tb__DOT__dut__DOT__regfile__DOT__regs[0];
  r->y = (uint8_t)R->tb__DOT__dut__DOT__regfile__DOT__regs[1];
  r->a = (uint8_t)R->tb__DOT__dut__DOT__regfile__DOT__regs[2];
  r->sp = (uint8_t)R->tb__DOT__dut__DOT__regfile__DOT__regs[3];
  r->p = (uint8_t)R->tb__DOT__dut__DOT__P;
}

extern "C" void simRequestReset(void) { R->tb__DOT__dbg_reset_req = 1; }

extern "C" void simFinish(void) { quitRequested = true; }

// ─── main loop ───────────────────────────────────────────────────────────────

int main(int argc, char **argv) {
  ctx = new VerilatedContext;
  ctx->commandArgs(argc, argv);

  int nsym = 0;
  char *syms[MAX_SYM_FILES];
  const char *src = nullptr;
  for (int i = 1; i < argc; i++) {
    if (!strncmp(argv[i], "+dbg_sym=", 9) && nsym < MAX_SYM_FILES)
      syms[nsym++] = argv[i] + 9;
    else if (!strncmp(argv[i], "+dbg_src=", 9))
      src = argv[i] + 9;
  }

  // The console is drawn on /dev/tty; stdout carries the ACIA text from $write.
  // Unbuffered, so the text is not lost if the debugger is killed.
  setvbuf(stdout, nullptr, _IONBF, 0);

  top = new Vtb(ctx);
  R = top->rootp;

  if (!dbgInit(nsym, syms, src)) {
    fprintf(stderr, "bbdbg: debugger UI failed to start\n");
    return 1;
  }

  // Time 0: runs the testbench's initial blocks (ROM and file loading, reset).
  top->eval();

  // One step = half a clock (500 ns at 1 MHz). Each step lands on a clock edge:
  // R->tb__DOT__clk is 1 right after a posedge and 0 right after a negedge.
  const uint64_t HALF_PERIOD_PS = 500000;
  while (!quitRequested && !ctx->gotFinish()) {
    ctx->timeInc(HALF_PERIOD_PS);
    top->eval();
    if (R->tb__DOT__clk) {
      if (R->tb__DOT__dbg_tx_strobe)
        dbgOnTx(R->tb__DOT__dbg_tx_byte);
      if (R->tb__DOT__dbg_fault_strobe)
        dbgOnFault(R->tb__DOT__dbg_fault_addr, R->tb__DOT__dbg_fault_we,
                   R->tb__DOT__dbg_fault_paddr);
    } else {
      // The fetch latched at the posedge that ended the opcode-fetch cycle
      if (R->tb__DOT__dbg_fetch)
        dbgOnFetch(R->tb__DOT__dbg_pc, R->tb__DOT__dbg_op);
    }
  }

  dbgCleanup();
  top->final();
  delete top;
  delete ctx;
  return 0;
}
