// ============================================================================
// debugger.h — BB6502 ncurses debugger (types, 65C02 opcode table, API)
//
// The debugger is the project author's ncurses debugger from the old
// fake6502-based emulator (BB6502 repo, emulator/src/include/debugger.h).
// See debugger.c for the list of changes made to run it as a VPI module
// against the Verilog system. Changes in this header:
//   - command_t: added CMD_RESET.
//   - runmode_t: new; the simulator now drives the debugger (see debugger.c).
//   - signal_t:  removed; it described the old IXFLAGREG protocol.
//   - addrmode_t + optable: extended from NMOS 6502 to the full WDC 65C02
//     instruction set, since the kernel is compiled with --cpu 65c02.
//   - Added the simulation interface (implemented in bbdbg_vpi.c) and the
//     entry points the VPI glue calls.
// ============================================================================
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef HOST_OS_WINDOWS
  #include <ncurses/ncurses.h>
#else
  #include <ncurses.h>
#endif

// Enum to represent all possible commands
typedef enum {
  CMD_INVALIDCMD,      // Not a real command
  CMD_REMOVEBP,        // Remove a breakpoint
  CMD_BREAKPOINT,      // Add a new breakpoint
  CMD_CONTINUE,        // Continue execution of assembly from current PC
  CMD_DISASSEMBLE,     // Disassemble routine
  CMD_HELP,            // Display the help strings
  CMD_LISTBREAKPOINTS, // List all breakpoints currently set
  CMD_MEMORY,          // Display the 6502 memory within a given range
  CMD_REGISTERS,       // Display the 6502 register contents
  CMD_STEP,            // Step the 6502 a given number of steps
  CMD_QUIT,            // Quit the debugger
  CMD_LOADSRC,         // Load the 6502 assembly src from a given file
  CMD_LOADSYMS,        // Load the 6502 assembly's debug symbols from a given file
  CMD_RESET            // Reset the machine (pulse the testbench reset line)
} command_t;

// What the debugger does at the next instruction fetch
typedef enum {
  DBG_STOPPED,         // Stop and prompt for commands
  DBG_STEPPING,        // Print each instruction until dbgStepsLeft reaches 0
  DBG_RUNNING          // Run until a breakpoint, Ctrl-C or STP
} runmode_t;

// Breakpoint struct to track bps and if at bp
typedef struct Breakpoint {
  uint16_t address;
  bool hasSymbol;
  char *symbol;
} breakpoint_t;


// Window data structure
// Wraps ncurses window
typedef struct window_t {
  WINDOW *win, *winbg;        // ncurses windows for foreground and background
  int winw, winh, winx, winy; // window dimensions and coordinates
  int wincx,
      wincy; // window cursor coordinates, may not be used depending on purpose
} window_t;

// Addressing Modes
typedef enum {
    AM_IMP,   // Implied
    AM_ACC,   // Accumulator
    AM_IMM,   // #$nn
    AM_ZP,    // $nn
    AM_ZPX,   // $nn,X
    AM_ZPY,   // $nn,Y
    AM_ABS,   // $nnnn
    AM_ABSX,  // $nnnn,X
    AM_ABSY,  // $nnnn,Y
    AM_IND,   // ($nnnn)
    AM_INDX,  // ($nn,X)
    AM_INDY,  // ($nn),Y
    AM_REL,   // branch
    AM_ZPI,   // ($nn)        65C02
    AM_ABSXI, // ($nnnn,X)    65C02 (JMP only)
    AM_ZPREL  // $nn,target   65C02 BBRn/BBSn
} addrmode_t;


// Opcode Descriptor
typedef struct {
    const char *mnemonic;
    addrmode_t mode;
    uint8_t bytes;
} opcode_t;


// Opcode Table — WDC 65C02
// BRK is listed as 2 bytes because on BB6502 the byte after BRK is the
// syscall number (see sw/kernel/src/brk.s); it is shown as BRK #$nn.
static const opcode_t optable[256] = {
/* 00 */ {"BRK",AM_IMM,2},{"ORA",AM_INDX,2},{"NOP",AM_IMM,2},{"NOP",AM_IMP,1},
/* 04 */ {"TSB",AM_ZP,2},{"ORA",AM_ZP,2},{"ASL",AM_ZP,2},{"RMB0",AM_ZP,2},
/* 08 */ {"PHP",AM_IMP,1},{"ORA",AM_IMM,2},{"ASL",AM_ACC,1},{"NOP",AM_IMP,1},
/* 0C */ {"TSB",AM_ABS,3},{"ORA",AM_ABS,3},{"ASL",AM_ABS,3},{"BBR0",AM_ZPREL,3},

/* 10 */ {"BPL",AM_REL,2},{"ORA",AM_INDY,2},{"ORA",AM_ZPI,2},{"NOP",AM_IMP,1},
/* 14 */ {"TRB",AM_ZP,2},{"ORA",AM_ZPX,2},{"ASL",AM_ZPX,2},{"RMB1",AM_ZP,2},
/* 18 */ {"CLC",AM_IMP,1},{"ORA",AM_ABSY,3},{"INC",AM_ACC,1},{"NOP",AM_IMP,1},
/* 1C */ {"TRB",AM_ABS,3},{"ORA",AM_ABSX,3},{"ASL",AM_ABSX,3},{"BBR1",AM_ZPREL,3},

/* 20 */ {"JSR",AM_ABS,3},{"AND",AM_INDX,2},{"NOP",AM_IMM,2},{"NOP",AM_IMP,1},
/* 24 */ {"BIT",AM_ZP,2},{"AND",AM_ZP,2},{"ROL",AM_ZP,2},{"RMB2",AM_ZP,2},
/* 28 */ {"PLP",AM_IMP,1},{"AND",AM_IMM,2},{"ROL",AM_ACC,1},{"NOP",AM_IMP,1},
/* 2C */ {"BIT",AM_ABS,3},{"AND",AM_ABS,3},{"ROL",AM_ABS,3},{"BBR2",AM_ZPREL,3},

/* 30 */ {"BMI",AM_REL,2},{"AND",AM_INDY,2},{"AND",AM_ZPI,2},{"NOP",AM_IMP,1},
/* 34 */ {"BIT",AM_ZPX,2},{"AND",AM_ZPX,2},{"ROL",AM_ZPX,2},{"RMB3",AM_ZP,2},
/* 38 */ {"SEC",AM_IMP,1},{"AND",AM_ABSY,3},{"DEC",AM_ACC,1},{"NOP",AM_IMP,1},
/* 3C */ {"BIT",AM_ABSX,3},{"AND",AM_ABSX,3},{"ROL",AM_ABSX,3},{"BBR3",AM_ZPREL,3},

/* 40 */ {"RTI",AM_IMP,1},{"EOR",AM_INDX,2},{"NOP",AM_IMM,2},{"NOP",AM_IMP,1},
/* 44 */ {"NOP",AM_ZP,2},{"EOR",AM_ZP,2},{"LSR",AM_ZP,2},{"RMB4",AM_ZP,2},
/* 48 */ {"PHA",AM_IMP,1},{"EOR",AM_IMM,2},{"LSR",AM_ACC,1},{"NOP",AM_IMP,1},
/* 4C */ {"JMP",AM_ABS,3},{"EOR",AM_ABS,3},{"LSR",AM_ABS,3},{"BBR4",AM_ZPREL,3},

/* 50 */ {"BVC",AM_REL,2},{"EOR",AM_INDY,2},{"EOR",AM_ZPI,2},{"NOP",AM_IMP,1},
/* 54 */ {"NOP",AM_ZPX,2},{"EOR",AM_ZPX,2},{"LSR",AM_ZPX,2},{"RMB5",AM_ZP,2},
/* 58 */ {"CLI",AM_IMP,1},{"EOR",AM_ABSY,3},{"PHY",AM_IMP,1},{"NOP",AM_IMP,1},
/* 5C */ {"NOP",AM_ABS,3},{"EOR",AM_ABSX,3},{"LSR",AM_ABSX,3},{"BBR5",AM_ZPREL,3},

/* 60 */ {"RTS",AM_IMP,1},{"ADC",AM_INDX,2},{"NOP",AM_IMM,2},{"NOP",AM_IMP,1},
/* 64 */ {"STZ",AM_ZP,2},{"ADC",AM_ZP,2},{"ROR",AM_ZP,2},{"RMB6",AM_ZP,2},
/* 68 */ {"PLA",AM_IMP,1},{"ADC",AM_IMM,2},{"ROR",AM_ACC,1},{"NOP",AM_IMP,1},
/* 6C */ {"JMP",AM_IND,3},{"ADC",AM_ABS,3},{"ROR",AM_ABS,3},{"BBR6",AM_ZPREL,3},

/* 70 */ {"BVS",AM_REL,2},{"ADC",AM_INDY,2},{"ADC",AM_ZPI,2},{"NOP",AM_IMP,1},
/* 74 */ {"STZ",AM_ZPX,2},{"ADC",AM_ZPX,2},{"ROR",AM_ZPX,2},{"RMB7",AM_ZP,2},
/* 78 */ {"SEI",AM_IMP,1},{"ADC",AM_ABSY,3},{"PLY",AM_IMP,1},{"NOP",AM_IMP,1},
/* 7C */ {"JMP",AM_ABSXI,3},{"ADC",AM_ABSX,3},{"ROR",AM_ABSX,3},{"BBR7",AM_ZPREL,3},

/* 80 */ {"BRA",AM_REL,2},{"STA",AM_INDX,2},{"NOP",AM_IMM,2},{"NOP",AM_IMP,1},
/* 84 */ {"STY",AM_ZP,2},{"STA",AM_ZP,2},{"STX",AM_ZP,2},{"SMB0",AM_ZP,2},
/* 88 */ {"DEY",AM_IMP,1},{"BIT",AM_IMM,2},{"TXA",AM_IMP,1},{"NOP",AM_IMP,1},
/* 8C */ {"STY",AM_ABS,3},{"STA",AM_ABS,3},{"STX",AM_ABS,3},{"BBS0",AM_ZPREL,3},

/* 90 */ {"BCC",AM_REL,2},{"STA",AM_INDY,2},{"STA",AM_ZPI,2},{"NOP",AM_IMP,1},
/* 94 */ {"STY",AM_ZPX,2},{"STA",AM_ZPX,2},{"STX",AM_ZPY,2},{"SMB1",AM_ZP,2},
/* 98 */ {"TYA",AM_IMP,1},{"STA",AM_ABSY,3},{"TXS",AM_IMP,1},{"NOP",AM_IMP,1},
/* 9C */ {"STZ",AM_ABS,3},{"STA",AM_ABSX,3},{"STZ",AM_ABSX,3},{"BBS1",AM_ZPREL,3},

/* A0 */ {"LDY",AM_IMM,2},{"LDA",AM_INDX,2},{"LDX",AM_IMM,2},{"NOP",AM_IMP,1},
/* A4 */ {"LDY",AM_ZP,2},{"LDA",AM_ZP,2},{"LDX",AM_ZP,2},{"SMB2",AM_ZP,2},
/* A8 */ {"TAY",AM_IMP,1},{"LDA",AM_IMM,2},{"TAX",AM_IMP,1},{"NOP",AM_IMP,1},
/* AC */ {"LDY",AM_ABS,3},{"LDA",AM_ABS,3},{"LDX",AM_ABS,3},{"BBS2",AM_ZPREL,3},

/* B0 */ {"BCS",AM_REL,2},{"LDA",AM_INDY,2},{"LDA",AM_ZPI,2},{"NOP",AM_IMP,1},
/* B4 */ {"LDY",AM_ZPX,2},{"LDA",AM_ZPX,2},{"LDX",AM_ZPY,2},{"SMB3",AM_ZP,2},
/* B8 */ {"CLV",AM_IMP,1},{"LDA",AM_ABSY,3},{"TSX",AM_IMP,1},{"NOP",AM_IMP,1},
/* BC */ {"LDY",AM_ABSX,3},{"LDA",AM_ABSX,3},{"LDX",AM_ABSY,3},{"BBS3",AM_ZPREL,3},

/* C0 */ {"CPY",AM_IMM,2},{"CMP",AM_INDX,2},{"NOP",AM_IMM,2},{"NOP",AM_IMP,1},
/* C4 */ {"CPY",AM_ZP,2},{"CMP",AM_ZP,2},{"DEC",AM_ZP,2},{"SMB4",AM_ZP,2},
/* C8 */ {"INY",AM_IMP,1},{"CMP",AM_IMM,2},{"DEX",AM_IMP,1},{"WAI",AM_IMP,1},
/* CC */ {"CPY",AM_ABS,3},{"CMP",AM_ABS,3},{"DEC",AM_ABS,3},{"BBS4",AM_ZPREL,3},

/* D0 */ {"BNE",AM_REL,2},{"CMP",AM_INDY,2},{"CMP",AM_ZPI,2},{"NOP",AM_IMP,1},
/* D4 */ {"NOP",AM_ZPX,2},{"CMP",AM_ZPX,2},{"DEC",AM_ZPX,2},{"SMB5",AM_ZP,2},
/* D8 */ {"CLD",AM_IMP,1},{"CMP",AM_ABSY,3},{"PHX",AM_IMP,1},{"STP",AM_IMP,1},
/* DC */ {"NOP",AM_ABS,3},{"CMP",AM_ABSX,3},{"DEC",AM_ABSX,3},{"BBS5",AM_ZPREL,3},

/* E0 */ {"CPX",AM_IMM,2},{"SBC",AM_INDX,2},{"NOP",AM_IMM,2},{"NOP",AM_IMP,1},
/* E4 */ {"CPX",AM_ZP,2},{"SBC",AM_ZP,2},{"INC",AM_ZP,2},{"SMB6",AM_ZP,2},
/* E8 */ {"INX",AM_IMP,1},{"SBC",AM_IMM,2},{"NOP",AM_IMP,1},{"NOP",AM_IMP,1},
/* EC */ {"CPX",AM_ABS,3},{"SBC",AM_ABS,3},{"INC",AM_ABS,3},{"BBS6",AM_ZPREL,3},

/* F0 */ {"BEQ",AM_REL,2},{"SBC",AM_INDY,2},{"SBC",AM_ZPI,2},{"NOP",AM_IMP,1},
/* F4 */ {"NOP",AM_ZPX,2},{"SBC",AM_ZPX,2},{"INC",AM_ZPX,2},{"SMB7",AM_ZP,2},
/* F8 */ {"SED",AM_IMP,1},{"SBC",AM_ABSY,3},{"PLX",AM_IMP,1},{"NOP",AM_IMP,1},
/* FC */ {"NOP",AM_ABS,3},{"SBC",AM_ABSX,3},{"INC",AM_ABSX,3},{"BBS7",AM_ZPREL,3},
};


// Debug symbol — loaded from an ld65 --dbgfile file
#define MAX_SYMBOL_LENGTH 32
typedef struct {
  char     symbolname[MAX_SYMBOL_LENGTH];  // null-terminated name
  uint16_t addr;                           // resolved address
} dbg_symbol_t;


// ─── Simulation interface (implemented in bbdbg_vpi.c) ───────────────────────
// This replaces the old dbgMEM6502 array and the fake6502 globals: all machine
// state is read live from the Verilog model.

// CPU registers as seen at the current instruction boundary
typedef struct {
  uint8_t a, x, y, sp, p;
} sim_regs_t;

// Read a byte the way the CPU would see it at `addr` (MMU-translated RAM
// below $8000, boot ROM from $8100). Returns false for the I/O window
// $8000-$80FF, because reading a device register can have side effects.
extern bool simReadMem(uint16_t addr, uint8_t *out);
extern void simGetRegs(sim_regs_t *regs);
extern bool simMmuIsKernel(void);           // MMU kernel (no-translation) mode
extern uint8_t simMmuPpn(int vpage);        // physical page for virtual page 0-31
#define SIM_MMU_NPAGES 32                   // 1 KB pages: VPN = VA[14:10]
extern void simRequestReset(void);          // pulse the testbench reset line
extern void simFinish(void);                // end the simulation ($finish)


// ─── Debugger entry points (called from bbdbg_vpi.c) ─────────────────────────
// Set up the UI and load symbol files; called once before time 0.
extern bool dbgInit(int nsymfiles, char **symfiles, const char *srcfile);
extern void dbgCleanup(void);
// Called once per instruction, just before the instruction at `pc` (opcode
// `opcode`) executes. Simulation time is frozen until this returns.
extern void dbgOnFetch(uint16_t pc, uint8_t opcode);
// A byte the CPU wrote to the ACIA data register ($8000)
extern void dbgOnTx(uint8_t c);
// The MMU raised a fault (it becomes an NMI)
extern void dbgOnFault(uint16_t addr, int we, uint32_t paddr);
