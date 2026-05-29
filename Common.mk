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

CC65_FLAGS := -Oir --cpu 65c02
CA65_FLAGS := --cpu 65c02

DISK_SIZE_KB := 1440
BOOT_REC_LBA := 100
KERNEL_LBA   := 101
PROG_LBA     := 200

SIM_VVP      := $(BUILD_DIR)/sim.vvp
GPU_BIN      := $(BUILD_DIR)/gpu
KERNEL_BBX   := $(BUILD_DIR)/kernel.bbx
BOOT_BIN     := $(BUILD_DIR)/bootrom.bin
BOOT_HEX     := $(BUILD_DIR)/bootrom.hex
BOOT_REC_BIN := $(BUILD_DIR)/bootrec.bin
PROG_BBX     := $(BUILD_DIR)/hello.bbx
DISK_IMG     := $(BUILD_DIR)/disk.img
