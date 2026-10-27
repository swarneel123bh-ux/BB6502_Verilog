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

# -g only adds debug info to the object files (used to produce the ld65
# --dbgfile symbol files the debugger loads); the binaries are unchanged.
CC65_FLAGS := -Oir --cpu 65c02 -g
CA65_FLAGS := --cpu 65c02 -g

DISK_SIZE_KB := 1440
BOOT_REC_LBA := 100
KERNEL_LBA   := 101
PROG_LBA  := 200
PROG2_LBA := 210

SIM_VVP      := $(BUILD_DIR)/sim.vvp
SIM_DBG_VVP  := $(BUILD_DIR)/sim_dbg.vvp   # same RTL built with -DBBDBG
DBG_VPI      := $(BUILD_DIR)/bbdbg.vpi     # debugger VPI module
GPU_BIN      := $(BUILD_DIR)/gpu
KERNEL_BBX   := $(BUILD_DIR)/kernel.bbx
BOOT_BIN     := $(BUILD_DIR)/bootrom.bin
BOOT_HEX     := $(BUILD_DIR)/bootrom.hex
BOOT_REC_BIN := $(BUILD_DIR)/bootrec.bin
PROG_BBX  := $(BUILD_DIR)/hello.bbx
PROG2_BBX := $(BUILD_DIR)/hello2.bbx
DISK_IMG     := $(BUILD_DIR)/disk.img

# ld65 debug-info files (symbol tables for the debugger)
BOOT_DBG     := $(BUILD_DIR)/boot.dbg
KERNEL_DBG   := $(BUILD_DIR)/kernel.dbg
PROG_DBG     := $(BUILD_DIR)/hello.dbg
PROG2_DBG    := $(BUILD_DIR)/hello2.dbg
