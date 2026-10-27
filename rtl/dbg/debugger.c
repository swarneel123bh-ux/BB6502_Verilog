// ============================================================================
// debugger.c — BB6502 ncurses debugger, running as a VPI module inside vvp
//
// The debugger itself — command set and aliases, the three-pane ncurses UI,
// breakpoints, the disassembler, memory/register views and the ld65 debug
// symbol loader — is the project author's debugger from the old fake6502-based
// emulator (BB6502 repo, emulator/src/include/debugger.c, last changed
// 2026-04-20). It was copied here so that it can drive the Verilog system.
//
// Changes made to run it against the Verilog system (2026-10):
//   * Control flow inverted. The old debugger owned the CPU and called
//     step6502(). Now the Verilog simulation owns time: the testbench calls
//     $bbdbg_fetch once per instruction, which lands in dbgOnFetch(). If the
//     debugger wants to stop (breakpoint, step count, Ctrl-C, start-up) it runs
//     its command loop *inside* that call, so simulation time is frozen until
//     the user resumes. dbgMainLoop/dbgRunProgCont/dbgStep6502 became the
//     runmode_t state machine (DBG_STOPPED / DBG_STEPPING / DBG_RUNNING).
//   * Memory and registers come from the Verilog model through the sim*
//     functions in bbdbg_vpi.c (MMU-translated RAM, boot ROM, Arlet's register
//     file). The private dbgMEM6502 array, read6502/write6502, ROM loading,
//     IXFLAGREG/UART/floppy servicing, dbgReset and command-line parsing were
//     removed (arguments arrive as vvp plusargs, see bbdbg_vpi.c).
//   * The I/O window $8000-$80FF is shown as ".." in memory dumps.
//   * Terminal pane: shows what the CPU writes to the ACIA ($bbdbg_tx); keys
//     typed into it are appended to /tmp/bb6502_in, exactly like tools/gpu.c
//     does, so they reach the ACIA RX path.
//   * ncurses runs on /dev/tty (newterm) because vvp's stdout is redirected to
//     a log file, and in raw() mode so Ctrl-C arrives as a key (0x03) instead
//     of SIGINT. The SIGINT handlers were removed (they called ncurses from a
//     signal handler, which is unsafe).
//   * New: `reset` command; STP ($DB) brings back the old "Program exited.
//     Restart/Exit?" prompt; `r` also shows decoded flags and the MMU state;
//     MMU faults are reported in the console; unknown commands get a message.
//   * Bugs fixed: dbgRmvBp never terminated (binary search on an unsorted list
//     with `mid` never updated) — now a linear search that really removes the
//     entry; the "Removed breakpoint" message was missing its printf argument;
//     CMD_REMOVEBP fell through without `break`; dbgReadHexU16 called exit()
//     on bad input, killing the whole session; the breakpoint-list growth check
//     used integer division; dbgReadDbgSyms could overflow the symbol table
//     when a second file was loaded; the "both addresses" branch of `m`
//     checked errno/end pointers incorrectly.
// ============================================================================
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
// Project includes
#include "debugger.h"

// Convenience Macros
#define dbgStrStartsWith(s1, s2)                                               \
  dbg_strStartsWith(s1, strlen(s1), s2, strlen(s2))
#define dbgStrIsAllCaps(s) dbg_strIsAllCaps(s, strlen(s))

// While running, the terminal pane is polled for keys (and Ctrl-C) once every
// this many instructions. Polling on every instruction slows the sim down.
#define DBG_POLL_INTERVAL 512
// Keyboard input file read by the testbench's ACIA RX logic (see rtl/tb.v)
#define DBG_RX_PATH "/tmp/bb6502_in"
#define DBG_KEY_CTRL_C 3

// DECLARATIONS
// Internal functions
static bool dbgShouldStop(uint8_t opcode);
static void dbgCommandLoop(void);
static void dbgEchoStep(void);
static bool dbgHandleStp(void);
static void dbgPollTerminal(void);
static void dbgSendKey(int k);
static uint8_t dbgRead6502(uint16_t address);
static void dbgDisplayHelp(void);
static void dbgDisasmInstr(char **cmdtoks, size_t cmdtoksiz);
static void dbgAddBp(char **cmdtoks, size_t cmdtoksiz);
static void dbgRunDbgCont(void);
static void dbgBackIntoDebugger(void);
static void dbgListBps(void);
static void dbgPrintMemRange(char *cmdtoks[], size_t cmdtoklen);
static void dbgPrintRegisters(void);
static void dbgStep6502(char *cmdtoks[], size_t cmdtoksize);
static void dbgResetMachine(void);
static bool dbgCheckIfAtBp(uint16_t pc, int instrlen, int *bpnum);
static bool dbg_strStartsWith(const char *s1, size_t s1len, const char *s2,
                              size_t s2len);
static bool dbg_strIsAllCaps(const char *s, size_t slen);
static bool dbgReadHexU16(uint16_t *out);
static void dbgShowMem(uint16_t startaddr, uint16_t endaddr);
static void dbgSetBp(uint16_t bp, char symbol[MAX_SYMBOL_LENGTH]);
static bool dbgRmvBp(uint16_t bp);
static void dbgReadDbgSyms(const char *fname);
static int dbgStrToInt(const char *s, int *out);
static int dbgGetCmdTokens(char *cmdString, char *tokenArray[],
                           size_t tokenArraySize);
static command_t dbgParseCommand(const char *cmd);
static bool dbgInitDisplay(void);
static char dbgConsoleGetchar(void);
static void dbgConsoleEcho(const char *fmt, ...);
static void dbgConsoleGetCmd(char *buf, size_t bufsiz);
static void dbgTerminalPutchar(char c);
static int dbgTerminalGetchar(void);
static int dbgDisasmInstrFromPc(uint16_t pc, uint8_t (*read)(uint16_t),
                                char *out);
static void dbgRemoveBreakpoint(char **cmdtoks, size_t cmdtoksiz);

// Variables
static bool dbgInitialised, dbgQuitting, dbgStepFirst, dbgTermDirty,
    dbgInterrupted;
static runmode_t dbgMode;
static int dbgStepsLeft;
static uint32_t dbgFetchCount;
static uint16_t dbgPc; // address of the instruction about to execute
static char dbgCmdBuf[100], *dbgSrcFileName;
static int dbgMainWinMaxLines, dbgMainWinMaxCols, dbgBpListSize, dbgNofBps,
    dbgNofSyms, dbgSymCapacity;
static window_t dbgDbgWin, dbgTermWin, dbgSrcWin;
static breakpoint_t *dbgBpList;
static dbg_symbol_t *dbgSymbols;
static SCREEN *dbgScreen;
static FILE *dbgTtyIn, *dbgTtyOut;
static int dbgRxFd = -1;

// DEFINITIONS:-

// Byte reader handed to the disassembler. The I/O window reads as $FF.
static uint8_t dbgRead6502(uint16_t address) {
  uint8_t v;
  return simReadMem(address, &v) ? v : 0xFF;
}

bool dbgInit(int nsymfiles, char **symfiles, const char *srcfile) {
  memset(dbgCmdBuf, 0, sizeof(dbgCmdBuf));
  dbgSrcFileName = (char *)srcfile;
  if (!dbgInitDisplay())
    return false;

  for (int i = 0; i < nsymfiles; i++) {
    dbgConsoleEcho("Loading debug symbols from %s\n", symfiles[i]);
    dbgReadDbgSyms(symfiles[i]);
  }
  dbgConsoleEcho("Loaded %d symbols total\n", dbgNofSyms);
  if (dbgSrcFileName)
    dbgConsoleEcho("Source view is not implemented yet (%s)\n",
                   dbgSrcFileName);
  dbgConsoleEcho("Stopped before the first instruction. Type h for help.\n");

  dbgMode = DBG_STOPPED; // stop at the very first fetch
  dbgQuitting = false;
  dbgInitialised = true;
  return true;
}

void dbgCleanup(void) {
  if (!dbgInitialised)
    return;
  for (int i = 0; i < dbgNofBps; i++) {
    if (dbgBpList[i].hasSymbol) {
      free(dbgBpList[i].symbol);
    }
  }
  free(dbgBpList);
  free(dbgSymbols);
  endwin();
  delscreen(dbgScreen);
  fclose(dbgTtyIn);
  fclose(dbgTtyOut);
  if (dbgRxFd >= 0)
    close(dbgRxFd);
  dbgInitialised = false;
  return;
}

// Called by the testbench (via bbdbg_vpi.c) right before the instruction at
// `pc` executes. Returning lets the simulation run on; stopping means running
// the command loop here until the user resumes.
void dbgOnFetch(uint16_t pc, uint8_t opcode) {
  if (!dbgInitialised || dbgQuitting)
    return;
  dbgPc = pc;
  dbgFetchCount++;

  if (!dbgShouldStop(opcode))
    return;

  dbgCommandLoop();

  // Resuming: the instruction at dbgPc runs next. With `s`, it is the first
  // stepped instruction, so show it now.
  if (dbgMode == DBG_STEPPING && dbgStepsLeft > 0)
    dbgEchoStep();
}

// Decide, at an instruction boundary, whether to hand control to the user.
static bool dbgShouldStop(uint8_t opcode) {
  int bpnum = -1;

  // STP halts a 65C02: treat it like the old "program exited" signal
  if (opcode == 0xDB && dbgHandleStp())
    return false;

  switch (dbgMode) {
  case DBG_STOPPED:
    return true;

  case DBG_RUNNING:
    if ((dbgFetchCount % DBG_POLL_INTERVAL) == 0)
      dbgPollTerminal();
    if (dbgInterrupted) {
      dbgInterrupted = false;
      dbgBackIntoDebugger();
      dbgConsoleEcho("\tInterrupted (Ctrl-C)\n");
      return true;
    }
    if (dbgCheckIfAtBp(dbgPc, 0, &bpnum)) {
      char buf[32];
      memset(buf, 0, sizeof(buf));
      dbgDisasmInstrFromPc(dbgPc, dbgRead6502, buf);
      dbgBackIntoDebugger();
      dbgConsoleEcho("\tBreakpoint [%d]:%s at addr %04hx: %s\n", bpnum,
                     (dbgBpList[bpnum].hasSymbol) ? dbgBpList[bpnum].symbol
                                                  : "",
                     dbgBpList[bpnum].address, buf);
      return true;
    }
    return false;

  case DBG_STEPPING:
    if (dbgStepsLeft <= 0) {
      dbgMode = DBG_STOPPED;
      return true;
    }
    {
      char line[64];
      memset(line, 0, sizeof(line));
      int instrlen = dbgDisasmInstrFromPc(dbgPc, dbgRead6502, line);
      if (dbgCheckIfAtBp(dbgPc, instrlen, &bpnum)) {
        dbgConsoleEcho("\tAt Breakpoint [%d] %s: %04hx   %s\n", bpnum,
                       (dbgBpList[bpnum].hasSymbol) ? dbgBpList[bpnum].symbol
                                                    : "",
                       dbgPc, line);
        dbgMode = DBG_STOPPED;
        return true;
      }
    }
    dbgEchoStep();
    return false;
  }
  return true;
}

// Prompt and run commands until one of them resumes the simulation.
static void dbgCommandLoop(void) {
  // Show where we are
  char line[64];
  memset(line, 0, sizeof(line));
  dbgDisasmInstrFromPc(dbgPc, dbgRead6502, line);
  dbgConsoleEcho("\t%04hx\t%s\n", dbgPc, line);
  wrefresh(dbgTermWin.win);

  while (dbgMode == DBG_STOPPED) {

    dbgConsoleGetCmd(dbgCmdBuf, sizeof(dbgCmdBuf));

    if (dbgCmdBuf[0] == '\n' || strlen(dbgCmdBuf) == 0)
      continue;
    size_t cmdTokArrSiz = 10;
    char *cmdtoks[cmdTokArrSiz];
    int cmdtoklen = dbgGetCmdTokens(dbgCmdBuf, cmdtoks, cmdTokArrSiz);
    if (cmdtoklen == 0)
      continue;

    switch (dbgParseCommand(cmdtoks[0])) {
    case CMD_BREAKPOINT:
      dbgAddBp(cmdtoks, cmdtoklen);
      break;

    case CMD_CONTINUE:
      dbgRunDbgCont();
      break;

    case CMD_DISASSEMBLE:
      dbgDisasmInstr(cmdtoks, cmdtoklen);
      break;

    case CMD_HELP:
      dbgDisplayHelp();
      break;

    case CMD_LISTBREAKPOINTS:
      dbgListBps();
      break;

    case CMD_MEMORY:
      dbgPrintMemRange(cmdtoks, cmdtoklen);
      break;

    case CMD_REGISTERS:
      dbgPrintRegisters();
      break;

    case CMD_STEP:
      dbgStep6502(cmdtoks, cmdtoklen);
      break;

    case CMD_QUIT:
      dbgConsoleEcho("\tEnding simulation\n");
      dbgQuitting = true;
      dbgMode = DBG_RUNNING; // leave the loop; the sim finishes
      simFinish();
      break;

    case CMD_REMOVEBP:
      dbgRemoveBreakpoint(cmdtoks, cmdtoklen);
      break;

    case CMD_RESET:
      dbgResetMachine();
      break;

    case CMD_LOADSRC:
      dbgConsoleEcho("\tSource view is not implemented yet\n");
      break;

    default:
      dbgConsoleEcho("\tUnknown command '%s' (h for help)\n", cmdtoks[0]);
      break;
    }
  }

  return;
}

// Print the instruction about to run as one step of an `s` command.
static void dbgEchoStep(void) {
  char line[64];
  memset(line, 0, sizeof(line));
  dbgDisasmInstrFromPc(dbgPc, dbgRead6502, line);

  int bpnum = -1;
  if (dbgStepFirst && dbgCheckIfAtBp(dbgPc, 0, &bpnum))
    dbgConsoleEcho("\tStepping through breakpoint...\n");
  dbgStepFirst = false;

  dbgConsoleEcho("\t%04hx\t%s\n", dbgPc, line);
  wrefresh(dbgTermWin.win);
  dbgStepsLeft--;
}

// STP ($DB) about to execute. Returns true if handled (the sim should go on).
static bool dbgHandleStp(void) {
  dbgBackIntoDebugger();
  dbgConsoleEcho("\n\tProgram exited (STP at %04hx). Restart/Exit? [r/E] :",
                 dbgPc);
  int c = dbgConsoleGetchar();
  dbgConsoleEcho("\n");
  if (c == 'r') {
    dbgResetMachine();
  } else {
    dbgQuitting = true;
    dbgMode = DBG_RUNNING;
    simFinish();
  }
  return true;
}

// Pulse the testbench reset and stop at the first instruction after it.
static void dbgResetMachine(void) {
  dbgConsoleEcho("\tResetting; will stop at the first instruction\n");
  simRequestReset();
  dbgMode = DBG_STEPPING;
  dbgStepsLeft = 0;
}

// While running: forward typed keys to the 6502, notice Ctrl-C, flush output.
static void dbgPollTerminal(void) {
  int k;
  while ((k = dbgTerminalGetchar()) != ERR) {
    if (k == DBG_KEY_CTRL_C) {
      dbgInterrupted = true;
      break;
    }
    dbgSendKey(k);
  }
  if (dbgTermDirty) {
    wrefresh(dbgTermWin.win);
    dbgTermDirty = false;
  }
}

// Append one key to the ACIA input file, translated the way tools/gpu.c does.
static void dbgSendKey(int k) {
  unsigned char c;
  if (k == '\n' || k == KEY_ENTER)
    c = '\r';
  else if (k == KEY_BACKSPACE || k == 127)
    c = 0x08;
  else if (k >= 0 && k < 128)
    c = (unsigned char)k;
  else
    return; // other ncurses KEY_* codes have no ASCII equivalent

  if (dbgRxFd < 0) // opened lazily: a FIFO needs the testbench's reader first
    dbgRxFd = open(DBG_RX_PATH, O_WRONLY | O_APPEND | O_NONBLOCK);
  if (dbgRxFd >= 0) {
    ssize_t r = write(dbgRxFd, &c, 1);
    (void)r;
  }
}

void dbgOnTx(uint8_t c) {
  if (!dbgInitialised)
    return;
  dbgTerminalPutchar((char)c);
  dbgTermDirty = true;
  if (dbgMode != DBG_RUNNING) { // while running, dbgPollTerminal refreshes
    wrefresh(dbgTermWin.win);
    dbgTermDirty = false;
  }
}

void dbgOnFault(uint16_t addr, int we, uint32_t paddr) {
  if (!dbgInitialised)
    return;
  dbgConsoleEcho("\t[mmu] FAULT  AB=%04x  WE=%d  paddr=%05x  (pc %04hx)\n",
                 addr, we, paddr, dbgPc);
}

static bool dbgReadHexU16(uint16_t *out) {
  char buf[32];
  memset(buf, 0, sizeof(buf));
  char *end;
  unsigned long value = 0;

  dbgConsoleGetCmd(buf, sizeof(buf));

  if (strlen(buf) == 0 || buf[0] == '\n' || buf[0] == 0) {
    dbgConsoleEcho("\tInput error\n");
    return false;
  }

  errno = 0;
  value = strtoul(buf, &end, 0);

  if (errno != 0 || end == buf) {
    dbgConsoleEcho("Invalid hex number\n");
    return false;
  }

  if (value > 0xFFFF) {
    dbgConsoleEcho("Value out of 16-bit range\n");
    return false;
  }

  *out = (uint16_t)value;
  return true;
}

static void dbgShowMem(uint16_t startaddr, uint16_t endaddr) {
  uint16_t addr = startaddr;
  while (1) {
    dbgConsoleEcho("%04X: ", addr);
    for (uint16_t offset = 0; offset < 16; offset++) {
      uint16_t cur = addr + offset;
      if (cur < addr || cur > endaddr)
        break;
      uint8_t v;
      if (simReadMem(cur, &v))
        dbgConsoleEcho("%02X ", v);
      else
        dbgConsoleEcho(".. "); // I/O window: not read (side effects)
    }
    dbgConsoleEcho("\n");
    if (endaddr < 16 || addr > endaddr - 16)
      break;
    addr += 16;
  }
  return;
}

static void dbgDisplayHelp(void) {
  dbgConsoleEcho("Help : -\n");
  dbgConsoleEcho(
      "b [./addr/symbol]: Create a breakpoint at [curr instr/addr/symbol]\n");
  dbgConsoleEcho("rb <addr/symbol>: Remove a breakpoint\n");
  dbgConsoleEcho("c: Continue the program from current state (Ctrl-C in the "
                 "terminal pane stops it)\n");
  dbgConsoleEcho("d [n]: Disassemble next 5/[n] instructions\n");
  dbgConsoleEcho("h: Display this help\n");
  dbgConsoleEcho("l: List all breakpoints\n");
  dbgConsoleEcho(
      "m [start] [end]: Display memory contents from a start location to an "
      "end location\n");
  dbgConsoleEcho("r: Display the register contents, MMU mode and page table\n");
  dbgConsoleEcho("s [n]: Step the program with one/[n] instruction\n");
  dbgConsoleEcho("reset: Reset the machine and stop at the first instruction\n");
  dbgConsoleEcho("q: Quit (ends the simulation)\n");
  dbgConsoleEcho("\n");
  return;
}

static void dbgDisasmInstr(char **cmdtoks, size_t cmdtoksiz) {
  int nofLines = 5;
  if (cmdtoksiz < 2) {
    nofLines = 5;
  } else if (!dbgStrToInt(cmdtoks[1], &nofLines)) {
    dbgConsoleEcho("cmd parsing err... %s %s\n", cmdtoks[0], cmdtoks[1]);
    return;
  }

  uint16_t pc_ = dbgPc;
  int instrlen;

  for (int i = 0; i < nofLines; i++) {
    char line[64];
    memset(line, 0, sizeof(line));
    instrlen = dbgDisasmInstrFromPc(pc_, dbgRead6502, line);
    dbgConsoleEcho("\t%04hx\t%s\n", pc_, line);
    pc_ += (uint16_t)instrlen;
  }

  return;
}

static void dbgAddBp(char **cmdtoks, size_t cmdtoksiz) {
  // No symbol/addr, set at curret pc
  if (cmdtoksiz < 2) {
    dbgConsoleEcho("  Setting new breakpoint at 0x%04hx\n", dbgPc);
    dbgSetBp(dbgPc, NULL); // If no addr/symbol given set at current addr
    return;
  }

  // Check whether symbol/addr is given
  if (dbgStrStartsWith("0x", cmdtoks[1])) { // Addr given
    char *end;
    uint16_t bp = strtoul(cmdtoks[1], &end, 0);
    dbgConsoleEcho("\tSetting new breakpoint at 0x%04hx\n", bp);
    dbgSetBp(bp, NULL);
    return;
  }

  // Symbol given
  for (int i = 0; i < dbgNofSyms; i++) {
    if (strcmp(cmdtoks[1], dbgSymbols[i].symbolname) == 0) {
      dbgConsoleEcho("\tSetting new breakpoint at name=%s, addr=0x%04hx\n",
                     dbgSymbols[i].symbolname, dbgSymbols[i].addr);
      dbgSetBp(dbgSymbols[i].addr, dbgSymbols[i].symbolname);
      return;
    }
  }

  dbgConsoleEcho("\tsymbol=%s not found!\n", cmdtoks[1]);
  return;
}

static void dbgRunDbgCont(void) {
  noecho();
  dbgInterrupted = false;
  dbgConsoleEcho("\n\tGoing into continuous execution\n");
  dbgMode = DBG_RUNNING;
}

// Common bookkeeping when continuous execution stops for any reason
static void dbgBackIntoDebugger(void) {
  if (dbgMode == DBG_RUNNING) {
    echo();
    if (dbgTermDirty) {
      wrefresh(dbgTermWin.win);
      dbgTermDirty = false;
    }
    dbgConsoleEcho("\n\tBack into debugger\n");
  }
  dbgMode = DBG_STOPPED;
}

static void dbgListBps(void) {

  if (dbgNofBps <= 0) {
    dbgConsoleEcho("\tNo breakpoints set\n");
    return;
  }

  for (int i = 0; i < dbgNofBps; i++) {
    char line[64];
    memset(line, 0, sizeof(line));
    dbgDisasmInstrFromPc(dbgBpList[i].address, dbgRead6502, line);
    if (dbgBpList[i].hasSymbol) {
      dbgConsoleEcho("\t%s:\t0x%04hx\t%s\n", dbgBpList[i].symbol,
                     dbgBpList[i].address, line);
    } else {
      dbgConsoleEcho("\t\t0x%04hx\t%s\n", dbgBpList[i].address, line);
    }
  }

  return;
}

static void dbgPrintMemRange(char *cmdtoks[], size_t cmdtoklen) {

  uint16_t startAddr, endAddr;

  // Both addrs not given
  if (cmdtoklen < 2) {
    dbgConsoleEcho("Give the starting address in hex [0x...]: ");
    if (!dbgReadHexU16(&startAddr))
      return;
    dbgConsoleEcho("Give the ending address in hex [0x...]: ");
    if (!dbgReadHexU16(&endAddr))
      return;
    if (endAddr < startAddr) {
      dbgConsoleEcho("Invalid input %04hx\n", endAddr);
      return;
    }
    dbgShowMem(startAddr, endAddr);
    return;
  }

  // Start addr given but stop addr not given
  if (cmdtoklen == 2) {
    char *end_;
    errno = 0;
    startAddr = strtoul(cmdtoks[1], &end_, 0);
    if (errno != 0 || end_ == cmdtoks[1]) {
      dbgConsoleEcho("Invalid hex number\n");
      return;
    }
    dbgConsoleEcho("Give the ending address in hex [0x...]: ");
    if (!dbgReadHexU16(&endAddr))
      return;
    if (endAddr < startAddr) {
      dbgConsoleEcho("Invalid input %04hx\n", endAddr);
      return;
    }
    dbgShowMem(startAddr, endAddr);
    return;
  }

  // Both addresses given
  char *end_, *end__;
  errno = 0;
  startAddr = strtoul(cmdtoks[1], &end_, 0);
  if (errno != 0 || end_ == cmdtoks[1]) {
    dbgConsoleEcho("Invalid hex number\n");
    return;
  }
  errno = 0;
  endAddr = strtoul(cmdtoks[2], &end__, 0);
  if (errno != 0 || end__ == cmdtoks[2]) {
    dbgConsoleEcho("Invalid hex number\n");
    return;
  }
  if (endAddr < startAddr) {
    dbgConsoleEcho("Invalid input %04hx\n", endAddr);
    return;
  }
  dbgShowMem(startAddr, endAddr);
  return;
}

static void dbgPrintRegisters(void) {
  sim_regs_t r;
  simGetRegs(&r);
  dbgConsoleEcho("PC=%04hx SP=%02hx A=%02hx X=%02hx Y=%02hx status=%02hx\n",
                 dbgPc, r.sp, r.a, r.x, r.y, r.p);

  // NV-BDIZC, upper case = set
  const char *names = "NV-BDIZC";
  char flags[9];
  for (int i = 0; i < 8; i++)
    flags[i] = (r.p & (0x80 >> i)) ? names[i] : '.';
  flags[8] = '\0';
  dbgConsoleEcho("flags=%s  MMU=%s\n", flags,
                 simMmuIsKernel() ? "kernel" : "user");
  // Page table, 1 KB pages: entry n maps virtual $nn00 (n << 10)
  dbgConsoleEcho("PPN");
  for (int i = 0; i < SIM_MMU_NPAGES; i++) {
    if ((i & 7) == 0)
      dbgConsoleEcho("%s[%2d..%2d]", i ? "  " : " ", i, i + 7);
    dbgConsoleEcho(" %2u", simMmuPpn(i));
  }
  dbgConsoleEcho("\n");
  return;
}

static void dbgStep6502(char *cmdtoks[], size_t cmdtoksize) {
  int nsteps = 1;

  if (cmdtoksize < 2) {
    nsteps = 1;
  } else {
    if (!dbgStrToInt(cmdtoks[1], &nsteps) || nsteps < 1) {
      dbgConsoleEcho("cmd parsing err... %s %s\n", cmdtoks[0], cmdtoks[1]);
      return;
    }
  }

  dbgStepsLeft = nsteps;
  dbgStepFirst = true;
  dbgMode = DBG_STEPPING;
}

static bool dbgCheckIfAtBp(uint16_t pc, int instrlen, int *bpnum) {
  uint16_t instrStartAddr = pc;
  uint16_t instrEndAddr = pc + instrlen;

  for (int i = 0; i < dbgNofBps; i++) {
    if ((instrStartAddr <= dbgBpList[i].address) &&
        (dbgBpList[i].address <= instrEndAddr)) {
      *bpnum = i;
      return true;
    }
  }
  *bpnum = -1;
  return false;
}

static bool dbg_strStartsWith(const char *s1, size_t s1len, const char *s2,
                              size_t s2len) {
  if (s1len > s2len)
    return false;

  for (size_t i = 0; i < s1len; i++) {
    if (s1[i] != s2[i])
      return false;
  }

  return true;
}

static bool dbg_strIsAllCaps(const char *s, size_t slen) {
  for (size_t i = 0; i < slen; i++) {
    if (isdigit((unsigned char)s[i]))
      continue;

    if (isalpha((unsigned char)s[i]) && !(s[i] >= 'A' && s[i] <= 'Z'))
      return 0;
  }

  return 1;
}

static void dbgSetBp(uint16_t addr, char symbol[MAX_SYMBOL_LENGTH]) {
  if (dbgBpListSize <= 0) {
    dbgBpListSize = 10;
    dbgBpList = (breakpoint_t *)malloc(sizeof(breakpoint_t) * dbgBpListSize);
    memset(dbgBpList, 0x0000, sizeof(breakpoint_t) * dbgBpListSize);
  }

  // Grow when full (the old check divided two ints, so it was always 0 or 1)
  if (dbgNofBps >= dbgBpListSize) {
    dbgBpListSize *= 2;
    breakpoint_t *tmp =
        realloc(dbgBpList, dbgBpListSize * sizeof(breakpoint_t));
    if (!tmp) {
      dbgConsoleEcho("setBreakpoint: out of memory, breakpoint not set\n");
      dbgBpListSize /= 2;
      return;
    }
    dbgBpList = tmp;
  }

  dbgBpList[dbgNofBps].address = addr;

  // Check if a valid symbol is given
  if (!symbol) {
    dbgBpList[dbgNofBps].symbol = NULL;
    dbgBpList[dbgNofBps].hasSymbol = false;
    dbgNofBps++;
    return;
  }

  // Write symbol if valid
  dbgBpList[dbgNofBps].symbol = (char *)calloc(MAX_SYMBOL_LENGTH, sizeof(char));
  strncpy(dbgBpList[dbgNofBps].symbol, symbol, MAX_SYMBOL_LENGTH - 1);
  dbgBpList[dbgNofBps].hasSymbol = true;
  dbgNofBps++;
  return;
}

// Remove every breakpoint at `bp`. Returns false if there was none.
// (The list is unsorted, so this is a linear search.)
static bool dbgRmvBp(uint16_t bp) {
  bool found = false;
  int i = 0;
  while (i < dbgNofBps) {
    if (dbgBpList[i].address != bp) {
      i++;
      continue;
    }
    if (dbgBpList[i].hasSymbol)
      free(dbgBpList[i].symbol);
    memmove(&dbgBpList[i], &dbgBpList[i + 1],
            (size_t)(dbgNofBps - i - 1) * sizeof(breakpoint_t));
    dbgNofBps--;
    found = true;
  }
  return found;
}

static void dbgReadDbgSyms(const char *fname) {
  // Parses an ld65 debug file (generated with --dbgfile) and APPENDs all
  // code labels into the global dbgSymbols table.
  // No .export directives required in assembly source.
  //
  // ld65 uses a tab between the record type and fields, e.g.:
  //   sym\tid=N,name="symname",...,val=0xXXXX,...,type=lab
  // We extract name and val from every sym line where type=lab.
  if (!fname)
    return;

  FILE *f = fopen(fname, "r");
  if (!f) {
    dbgConsoleEcho("symload: Cannot open \"%s\": %s\n", fname,
                   strerror(errno));
    return;
  }

  if (dbgSymbols == NULL) {
    dbgSymCapacity = 64;
    dbgSymbols = malloc(dbgSymCapacity * sizeof(dbg_symbol_t));
    if (!dbgSymbols) {
      fclose(f);
      return;
    }
  }

  char line[512];
  while (fgets(line, sizeof(line), f)) {
    // ld65 separates record type from fields with a tab
    if (strncmp(line, "sym", 3) != 0 || (line[3] != '\t' && line[3] != ' '))
      continue;
    // Only load code labels (type=lab), skip equ/import etc.
    if (strstr(line, "type=lab") == NULL)
      continue;

    // Extract name="..."
    char symname[MAX_SYMBOL_LENGTH];
    char *nameptr = strstr(line, "name=\"");
    if (!nameptr)
      continue;
    nameptr += 6; // skip: name="
    int ni = 0;
    while (*nameptr && *nameptr != '"' && ni < MAX_SYMBOL_LENGTH - 1)
      symname[ni++] = *nameptr++;
    symname[ni] = '\0';
    if (ni == 0)
      continue;

    // Extract val=0xXXXX
    char *valptr = strstr(line, "val=0x");
    if (!valptr)
      continue;
    unsigned int addr;
    if (sscanf(valptr, "val=0x%x", &addr) != 1)
      continue;

    // Skip all-caps hardware EQUs (UARTINREG, IXFLAGREG, etc.)
    if (dbgStrIsAllCaps(symname))
      continue;

    // Grow array if needed (capacity is tracked across files)
    if (dbgNofSyms >= dbgSymCapacity) {
      dbg_symbol_t *tmp =
          realloc(dbgSymbols, dbgSymCapacity * 2 * sizeof(dbg_symbol_t));
      if (!tmp)
        break;
      dbgSymbols = tmp;
      dbgSymCapacity *= 2;
    }

    memset(&dbgSymbols[dbgNofSyms], 0, sizeof(dbg_symbol_t));
    strncpy(dbgSymbols[dbgNofSyms].symbolname, symname, MAX_SYMBOL_LENGTH - 1);
    dbgSymbols[dbgNofSyms].addr = (uint16_t)addr;
    dbgNofSyms++;
  }

  fclose(f);
}

static int dbgStrToInt(const char *s, int *out) {
  char *end;
  long val;

  errno = 0;
  val = strtol(s, &end, 10);

  if (end == s)
    return 0;

  if ((errno == ERANGE) || val > INT_MAX || val < INT_MIN)
    return 0;

  if (*end != '\0')
    return 0;

  *out = (int)val;
  return 1;
}

static int dbgGetCmdTokens(char *cmdString, char *tokenArray[],
                           size_t tokenArraySize) {
  size_t count = 0;
  char *token;

  if (!cmdString || !tokenArray || tokenArraySize == 0)
    return 0;

  token = strtok(cmdString, " \t\n");

  while (token != NULL && count < tokenArraySize - 1) {
    tokenArray[count++] = token;
    token = strtok(NULL, " \t\n");
  }

  tokenArray[count] = NULL;
  return count;
}

static command_t dbgParseCommand(const char *cmd) {
  if (!strcmp(cmd, "b"))
    return CMD_BREAKPOINT;
  if (!strcmp(cmd, "bp"))
    return CMD_BREAKPOINT;
  if (!strcmp(cmd, "break"))
    return CMD_BREAKPOINT;
  if (!strcmp(cmd, "breakpoint"))
    return CMD_BREAKPOINT;

  if (!strcmp(cmd, "c"))
    return CMD_CONTINUE;
  if (!strcmp(cmd, "cont"))
    return CMD_CONTINUE;
  if (!strcmp(cmd, "continue"))
    return CMD_CONTINUE;

  if (!strcmp(cmd, "d"))
    return CMD_DISASSEMBLE;
  if (!strcmp(cmd, "dis"))
    return CMD_DISASSEMBLE;
  if (!strcmp(cmd, "disas"))
    return CMD_DISASSEMBLE;
  if (!strcmp(cmd, "disassemble"))
    return CMD_DISASSEMBLE;

  if (!strcmp(cmd, "h"))
    return CMD_HELP;
  if (!strcmp(cmd, "help"))
    return CMD_HELP;

  if (!strcmp(cmd, "l"))
    return CMD_LISTBREAKPOINTS;
  if (!strcmp(cmd, "ls"))
    return CMD_LISTBREAKPOINTS;
  if (!strcmp(cmd, "list"))
    return CMD_LISTBREAKPOINTS;
  if (!strcmp(cmd, "lbp"))
    return CMD_LISTBREAKPOINTS;
  if (!strcmp(cmd, "listbp"))
    return CMD_LISTBREAKPOINTS;

  if (!strcmp(cmd, "ld"))
    return CMD_LOADSRC;
  if (!strcmp(cmd, "lds"))
    return CMD_LOADSRC;
  if (!strcmp(cmd, "load"))
    return CMD_LOADSRC;
  if (!strcmp(cmd, "ldsrc"))
    return CMD_LOADSRC;

  if (!strcmp(cmd, "m"))
    return CMD_MEMORY;
  if (!strcmp(cmd, "mem"))
    return CMD_MEMORY;
  if (!strcmp(cmd, "memory"))
    return CMD_MEMORY;

  if (!strcmp(cmd, "r"))
    return CMD_REGISTERS;
  if (!strcmp(cmd, "reg"))
    return CMD_REGISTERS;
  if (!strcmp(cmd, "regis"))
    return CMD_REGISTERS;
  if (!strcmp(cmd, "register"))
    return CMD_REGISTERS;
  if (!strcmp(cmd, "registers"))
    return CMD_REGISTERS;

  if (!strcmp(cmd, "rb"))
    return CMD_REMOVEBP;
  if (!strcmp(cmd, "rbp"))
    return CMD_REMOVEBP;
  if (!strcmp(cmd, "rmb"))
    return CMD_REMOVEBP;
  if (!strcmp(cmd, "rmbp"))
    return CMD_REMOVEBP;
  if (!strcmp(cmd, "remb"))
    return CMD_REMOVEBP;
  if (!strcmp(cmd, "rembp"))
    return CMD_REMOVEBP;
  if (!strcmp(cmd, "remove"))
    return CMD_REMOVEBP;
  if (!strcmp(cmd, "removebp"))
    return CMD_REMOVEBP;

  if (!strcmp(cmd, "reset"))
    return CMD_RESET;
  if (!strcmp(cmd, "rst"))
    return CMD_RESET;

  if (!strcmp(cmd, "s"))
    return CMD_STEP;
  if (!strcmp(cmd, "step"))
    return CMD_STEP;

  if (!strcmp(cmd, "q"))
    return CMD_QUIT;
  if (!strcmp(cmd, "quit"))
    return CMD_QUIT;
  if (!strcmp(cmd, "exit"))
    return CMD_QUIT;

  return CMD_INVALIDCMD;
}

// Layout (unchanged): terminal pane top-left, source pane top-right,
// debugger console across the bottom half.
static bool dbgInitDisplay(void) {
  // vvp's stdout/stderr go to a log file, so talk to the terminal directly
  dbgTtyOut = fopen("/dev/tty", "w");
  dbgTtyIn = fopen("/dev/tty", "r");
  if (!dbgTtyOut || !dbgTtyIn) {
    fprintf(stderr, "bbdbg: cannot open /dev/tty: %s\n", strerror(errno));
    return false;
  }
  dbgScreen = newterm(NULL, dbgTtyOut, dbgTtyIn);
  if (!dbgScreen) {
    fprintf(stderr, "bbdbg: newterm failed (is TERM set?)\n");
    return false;
  }
  set_term(dbgScreen);
  keypad(stdscr, TRUE);
  raw(); // Ctrl-C arrives as a key, not as SIGINT
  nl();
  refresh();
  getmaxyx(stdscr, dbgMainWinMaxLines, dbgMainWinMaxCols);
  dbgDbgWin.winw = dbgMainWinMaxCols - 2;
  dbgDbgWin.winh = dbgMainWinMaxLines - (dbgMainWinMaxLines / 2) - 3;
  dbgDbgWin.winx = 1;
  dbgDbgWin.winy = (dbgMainWinMaxLines / 2) + 2;
  dbgDbgWin.winbg = newwin(dbgDbgWin.winh + 2, dbgDbgWin.winw + 2,
                           dbgDbgWin.winy - 1, dbgDbgWin.winx - 1);
  dbgDbgWin.win =
      newwin(dbgDbgWin.winh, dbgDbgWin.winw, dbgDbgWin.winy, dbgDbgWin.winx);
  box(dbgDbgWin.winbg, 0, 0);
  scrollok(dbgDbgWin.win, TRUE);
  keypad(dbgDbgWin.win, TRUE);
  wrefresh(dbgDbgWin.winbg);
  wrefresh(dbgDbgWin.win);
  dbgTermWin.winw = dbgMainWinMaxCols - (dbgMainWinMaxCols / 2) - 2;
  dbgTermWin.winh = dbgMainWinMaxLines - (dbgMainWinMaxLines / 2) - 2;
  dbgTermWin.winx = 1;
  dbgTermWin.winy = 1;
  dbgTermWin.winbg = newwin(dbgTermWin.winh + 2, dbgTermWin.winw + 2,
                            dbgTermWin.winy - 1, dbgTermWin.winx - 1);
  dbgTermWin.win = newwin(dbgTermWin.winh, dbgTermWin.winw, dbgTermWin.winy,
                          dbgTermWin.winx);
  box(dbgTermWin.winbg, 0, 0);
  scrollok(dbgTermWin.win, TRUE);
  nodelay(dbgTermWin.win, TRUE);
  keypad(dbgTermWin.win, TRUE);
  wrefresh(dbgTermWin.winbg);
  wrefresh(dbgTermWin.win);
  dbgSrcWin.winw = dbgMainWinMaxCols - (dbgMainWinMaxCols / 2) - 2;
  dbgSrcWin.winh = dbgMainWinMaxLines - (dbgMainWinMaxLines / 2) - 2;
  dbgSrcWin.winx = dbgTermWin.winx + dbgTermWin.winw + 2;
  dbgSrcWin.winy = 1;
  dbgSrcWin.winbg = newwin(dbgSrcWin.winh + 2, dbgSrcWin.winw + 2,
                           dbgSrcWin.winy - 1, dbgSrcWin.winx - 1);
  dbgSrcWin.win =
      newwin(dbgSrcWin.winh, dbgSrcWin.winw, dbgSrcWin.winy, dbgSrcWin.winx);
  box(dbgSrcWin.winbg, 0, 0);
  scrollok(dbgSrcWin.win, TRUE);
  keypad(dbgSrcWin.win, TRUE);
  wrefresh(dbgSrcWin.winbg);
  wrefresh(dbgSrcWin.win);
  return true;
}

static char dbgConsoleGetchar(void) { return wgetch(dbgDbgWin.win); }

static void dbgConsoleEcho(const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  int y = getcury(dbgDbgWin.win);
  int x = getcurx(dbgDbgWin.win);
  wmove(dbgDbgWin.win, y, x);
  vw_printw(dbgDbgWin.win, fmt, args);
  va_end(args);
  wrefresh(dbgDbgWin.win);
}

static void dbgConsoleGetCmd(char *buf, size_t bufsiz) {
  dbgConsoleEcho(">>");
  wgetnstr(dbgDbgWin.win, buf, (int)bufsiz - 1);
  wrefresh(dbgDbgWin.win);
  return;
}

// CR is dropped so the kernel's "\r\n" line endings give one new line
static void dbgTerminalPutchar(char c) {
  if (c == '\r')
    return;
  waddch(dbgTermWin.win, (unsigned char)c);
  return;
}

static int dbgTerminalGetchar(void) { return (int)wgetch(dbgTermWin.win); }

static int dbgDisasmInstrFromPc(uint16_t pc, uint8_t (*read)(uint16_t),
                                char *out) {
  uint8_t opcode = read(pc);
  const opcode_t *op = &optable[opcode];

  uint8_t b1 = read(pc + 1);
  uint8_t b2 = read(pc + 2);
  uint16_t addr = (uint16_t)(b1 | (b2 << 8));

  switch (op->mode) {
  case AM_IMP:
    sprintf(out, "%s", op->mnemonic);
    break;
  case AM_ACC:
    sprintf(out, "%s A", op->mnemonic);
    break;
  case AM_IMM:
    sprintf(out, "%s #$%02X", op->mnemonic, b1);
    break;
  case AM_ZP:
    sprintf(out, "%s $%02X", op->mnemonic, b1);
    break;
  case AM_ZPX:
    sprintf(out, "%s $%02X,X", op->mnemonic, b1);
    break;
  case AM_ZPY:
    sprintf(out, "%s $%02X,Y", op->mnemonic, b1);
    break;
  case AM_ABS:
    sprintf(out, "%s $%04X", op->mnemonic, addr);
    break;
  case AM_ABSX:
    sprintf(out, "%s $%04X,X", op->mnemonic, addr);
    break;
  case AM_ABSY:
    sprintf(out, "%s $%04X,Y", op->mnemonic, addr);
    break;
  case AM_IND:
    sprintf(out, "%s ($%04X)", op->mnemonic, addr);
    break;
  case AM_INDX:
    sprintf(out, "%s ($%02X,X)", op->mnemonic, b1);
    break;
  case AM_INDY:
    sprintf(out, "%s ($%02X),Y", op->mnemonic, b1);
    break;
  case AM_REL: {
    int8_t off = (int8_t)b1;
    uint16_t target = pc + 2 + off;
    sprintf(out, "%s $%04X", op->mnemonic, target);
    break;
  }
  case AM_ZPI:
    sprintf(out, "%s ($%02X)", op->mnemonic, b1);
    break;
  case AM_ABSXI:
    sprintf(out, "%s ($%04X,X)", op->mnemonic, addr);
    break;
  case AM_ZPREL: {
    int8_t off = (int8_t)b2;
    uint16_t target = pc + 3 + off;
    sprintf(out, "%s $%02X,$%04X", op->mnemonic, b1, target);
    break;
  }
  }

  return op->bytes;
}

static void dbgRemoveBreakpoint(char **cmdtoks, size_t cmdtoksiz) {
  if (cmdtoksiz < 2) {
    dbgConsoleEcho("\tusage: rb(or alternate command) <symbol/0x(address)>\n");
    return;
  }

  // Check whether symbol/addr is given
  if (dbgStrStartsWith("0x", cmdtoks[1])) { // Addr given
    char *end;
    uint16_t bp = strtoul(cmdtoks[1], &end, 0);
    if (dbgRmvBp(bp))
      dbgConsoleEcho("\tRemoved breakpoint at addr=0x%04hx\n", bp);
    else
      dbgConsoleEcho("\tNo breakpoint at addr=0x%04hx\n", bp);
    return;
  }

  // Symbol given
  for (int i = 0; i < dbgNofSyms; i++) {
    if (strcmp(cmdtoks[1], dbgSymbols[i].symbolname) == 0) {
      if (dbgRmvBp(dbgSymbols[i].addr))
        dbgConsoleEcho("\tRemoved breakpoint at name=%s, addr=0x%04hx\n",
                       dbgSymbols[i].symbolname, dbgSymbols[i].addr);
      else
        dbgConsoleEcho("\tNo breakpoint at name=%s, addr=0x%04hx\n",
                       dbgSymbols[i].symbolname, dbgSymbols[i].addr);
      return;
    }
  }

  dbgConsoleEcho("\tsymbol=%s not found!\n", cmdtoks[1]);
  return;
}
