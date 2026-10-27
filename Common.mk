# Destination: ./common.mk  (project root — shared config, included by every makefile)
# Shared config. Each makefile sets ROOT to the project root before including.

BUILD_DIR  := $(ROOT)/build
DISK_DIR   := $(ROOT)/disk
TOOLS_DIR  := $(ROOT)/tools

IVERILOG   := iverilog
VVP        := vvp
CC65       := cc65
CA65       := ca65
LD65       := ld65
CC         := cc

# Syscall ABI block in every process's zero page (see docs/syscalls.md).
# This is the ONLY place its position and size are written down:
#   - syslib.s (user side) and syscalls.c (kernel side) define each slot as
#     SYS_ABI_BASE + offset,
#   - prog.cfg places cc65's own zero-page variables right after the block,
#   - ld65 / ca65 refuse to build if the result doesn't fit in zero page.
# Decimal on purpose: ca65/ld65 write hex as $30 but C needs 0x30.
# Changing either value means a `make clean`.
SYS_ABI_BASE := 48
SYS_ABI_SIZE := 17

ABI_DEFS_C   := -DSYS_ABI_BASE=$(SYS_ABI_BASE) -DSYS_ABI_SIZE=$(SYS_ABI_SIZE)
ABI_DEFS_AS  := -D SYS_ABI_BASE=$(SYS_ABI_BASE) -D SYS_ABI_SIZE=$(SYS_ABI_SIZE)
ABI_DEFS_LD  := -D __SYS_ABI_BASE__=$(SYS_ABI_BASE) -D __SYS_ABI_SIZE__=$(SYS_ABI_SIZE)

# -g only adds debug info to the object files (used to produce the ld65
# --dbgfile symbol files the debugger loads); the binaries are unchanged.
CC65_FLAGS := -Oir --cpu 65c02 -g $(ABI_DEFS_C)
CA65_FLAGS := --cpu 65c02 -g $(ABI_DEFS_AS)
# Used when linking user programs (prog.cfg reads the ABI symbols)
LD65_PROG_FLAGS := $(ABI_DEFS_LD)

DISK_SIZE_KB := 1440
BOOT_REC_LBA := 100
KERNEL_LBA   := 101
PROG_LBA  := 200
PROG2_LBA := 210
PROG3_LBA := 220

SIM_VVP      := $(BUILD_DIR)/sim.vvp
# Debugger build: the same RTL built with -DBBDBG, and the debugger VPI module
SIM_DBG_VVP  := $(BUILD_DIR)/sim_dbg.vvp
DBG_VPI      := $(BUILD_DIR)/bbdbg.vpi
GPU_BIN      := $(BUILD_DIR)/gpu
KERNEL_BBX   := $(BUILD_DIR)/kernel.bbx
BOOT_BIN     := $(BUILD_DIR)/bootrom.bin
BOOT_HEX     := $(BUILD_DIR)/bootrom.hex
BOOT_REC_BIN := $(BUILD_DIR)/bootrec.bin
PROG_BBX  := $(BUILD_DIR)/hello.bbx
PROG2_BBX := $(BUILD_DIR)/hello2.bbx
PROG3_BBX := $(BUILD_DIR)/disktest.bbx
DISK_IMG     := $(BUILD_DIR)/disk.img

# ld65 debug-info files (symbol tables for the debugger)
BOOT_DBG     := $(BUILD_DIR)/boot.dbg
KERNEL_DBG   := $(BUILD_DIR)/kernel.dbg
PROG_DBG     := $(BUILD_DIR)/hello.dbg
PROG2_DBG    := $(BUILD_DIR)/hello2.dbg
PROG3_DBG    := $(BUILD_DIR)/disktest.dbg
