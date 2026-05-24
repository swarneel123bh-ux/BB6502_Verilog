# ---- Paths ----
RTL_DIR    		:= rtl
CPU_DIR    		:= $(RTL_DIR)/verilog-65C02-microcode/generic
TB_FILE    		:= $(RTL_DIR)/tb.v
SW_DIR     		:= sw
BUILD_DIR  		:= build
DISK_DIR 			:= disk
DISK_IMG 			:= $(BUILD_DIR)/disk.img
DISK_SIZE_KB 	:= 1440

# ---- Toolchain ----
IVERILOG    := iverilog
VVP         := vvp
CC65        := cc65
CA65        := ca65
LD65        := ld65
CC          := cc
SDL_CFLAGS  := $(shell pkg-config --cflags sdl2 SDL2_ttf 2>/dev/null || echo "-I/opt/homebrew/include")
SDL_LDFLAGS := $(shell pkg-config --libs sdl2 SDL2_ttf 2>/dev/null || echo "-L/opt/homebrew/lib -lSDL2 -lSDL2_ttf")
GPU_BIN     := $(BUILD_DIR)/gpu

# ---- Files ----
CPU_SRCS    := $(wildcard $(CPU_DIR)/*.v)
RTL_SRCS    := $(CPU_SRCS) $(TB_FILE) $(RTL_DIR)/mmu6502.v

# C Sources and resulting objects
C_SRCS      := $(wildcard $(SW_DIR)/*.c)
C_OBJS      := $(patsubst $(SW_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SRCS))

# Assembly Sources and resulting objects
ASM_SRCS    := $(wildcard $(SW_DIR)/*.s)
ASM_OBJS    := $(patsubst $(SW_DIR)/%.s,$(BUILD_DIR)/%.o,$(ASM_SRCS))

# Combined objects for linking
ALL_OBJS    := $(ASM_OBJS) $(C_OBJS)

ROM_BIN     := $(BUILD_DIR)/rom.bin
ROM_HEX     := $(BUILD_DIR)/rom.hex
SIM_VVP     := $(BUILD_DIR)/sim.vvp
LINKER_CFG  := $(SW_DIR)/rom.cfg

TOP_MODULE  := tb

# ---- Flags ----
IVERILOG_FLAGS := -g2012 -Wall -I$(CPU_DIR)
CC65_FLAGS     := -Oir --cpu 65c02
CA65_FLAGS     := --cpu 65c02
LD65_FLAGS     := -C $(LINKER_CFG)

.PHONY: all clean gpu run

all: $(SIM_VVP) $(ROM_HEX) $(GPU_BIN) $(DISK_IMG)

run: $(SIM_VVP) $(ROM_HEX) $(GPU_BIN) $(DISK_IMG)

# Compile CPU + testbench into a vvp executable
$(SIM_VVP): $(RTL_SRCS) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s $(TOP_MODULE) -o $@ $(RTL_SRCS)

# --- C Build Pipeline ---

# 1. Compile C -> Assembly
$(BUILD_DIR)/%.s: $(SW_DIR)/%.c | $(BUILD_DIR)
	$(CC65) $(CC65_FLAGS) -o $@ $<

# 2. Assemble C-generated Assembly -> Object
$(BUILD_DIR)/%.o: $(BUILD_DIR)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

# --- Assembly Build Pipeline ---

# Assemble raw .s -> .o
$(BUILD_DIR)/%.o: $(SW_DIR)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

# --- Linker and Post-Processing ---

# Link all objects (C and Asm) -> raw binary
# Note: none.lib is included for cc65 runtime support (stack handling, etc)
$(ROM_BIN): $(ALL_OBJS) $(LINKER_CFG) | $(BUILD_DIR)
	$(LD65) $(LD65_FLAGS) -o $@ $(ALL_OBJS) none.lib

# Binary -> ASCII hex, one byte per line
$(ROM_HEX): $(ROM_BIN)
	hexdump -v -e '1/1 "%02x\n"' $< > $@

$(GPU_BIN): tools/gpu.c | $(BUILD_DIR)
	$(CC) -O2 -Wall $(SDL_CFLAGS) -o $@ $< $(SDL_LDFLAGS)

# Build a FAT16 image from the host-side disk/ directory.
# Uses mtools (mformat, mcopy) which work without root on macOS+Linux.
$(DISK_IMG): $(shell find $(DISK_DIR) -type f 2>/dev/null) | $(BUILD_DIR)
		@echo "Building disk image from $(DISK_DIR)/"
		@dd if=/dev/zero of=$@ bs=1024 count=$(DISK_SIZE_KB) status=none
		@mformat -i $@ -F ::
		@if [ -d $(DISK_DIR) ] && [ "$$(ls -A $(DISK_DIR) 2>/dev/null)" ]; then \
		  mcopy -i $@ -s $(DISK_DIR)/* ::; \
		fi

gpu: $(GPU_BIN)
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@mkfifo /tmp/bb6502_in  2>/dev/null || true
	$(GPU_BIN)

run: $(SIM_VVP) $(ROM_HEX) $(GPU_BIN)
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@mkfifo /tmp/bb6502_in  2>/dev/null || true
	@echo "Starting BB6502. Close the SDL window or press Ctrl-C to exit."
	@$(GPU_BIN) & GPU_PID=$$!; \
	 sleep 0.3; \
	 $(VVP) $(SIM_VVP) & VVP_PID=$$!; \
	 (sleep 0.5; echo "" > /tmp/bb6502_in) & \		# The sleeps make sure that the pipe is kept ope while simul starts up
	 trap "kill $$GPU_PID $$VVP_PID 2>/dev/null; exit 0" EXIT INT TERM; \
	 wait $$GPU_PID; \
	 kill $$VVP_PID 2>/dev/null; \
	 wait $$VVP_PID 2>/dev/null; true

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)

# ---- User programs rules ----
PROG_DIR := sw/prog
PROG_SRCS := $(PROG_DIR)/hello.c
PROG_CRT0 := $(PROG_DIR)/prog_crt0.s
PROG_CFG  := $(PROG_DIR)/prog.cfg
PROG_BBX  := $(BUILD_DIR)/hello.bbx

# Compile user-program .c through cc65 + ca65 to .o
$(BUILD_DIR)/prog_%.o: $(PROG_DIR)/%.c | $(BUILD_DIR)
	$(CC65) $(CC65_FLAGS) -o $(BUILD_DIR)/prog_$*.s $<
	$(CA65) $(CA65_FLAGS) -o $@ $(BUILD_DIR)/prog_$*.s

$(BUILD_DIR)/prog_crt0.o: $(PROG_CRT0) | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

$(PROG_BBX): $(BUILD_DIR)/prog_crt0.o $(BUILD_DIR)/prog_hello.o $(PROG_CFG)
	$(LD65) -C $(PROG_CFG) -o $@ $(BUILD_DIR)/prog_crt0.o $(BUILD_DIR)/prog_hello.o none.lib

# Add the program to the disk image at a known LBA
# Easiest way: just put it in the disk/ directory and let mtools place it,
# then read its LBA from the disk after mkfs. But for fixed-LBA loading,
# splice it directly into the image at byte offset = LBA * 512.

PROG_LBA := 100		# Only for the test, we need to remove this later
$(DISK_IMG): $(PROG_BBX)
	@echo "Building disk image..."
	@dd if=/dev/zero of=$@ bs=1024 count=$(DISK_SIZE_KB) status=none
	@mformat -i $@ -F ::
	@if [ -d $(DISK_DIR) ] && [ "$$(ls -A $(DISK_DIR) 2>/dev/null)" ]; then \
	  mcopy -i $@ -s $(DISK_DIR)/* ::; \
	fi
	@echo "Placing $(PROG_BBX) at LBA $(PROG_LBA)"
	@dd if=$(PROG_BBX) of=$@ bs=512 seek=$(PROG_LBA) conv=notrunc status=none
