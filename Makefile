# =============================================================================
#  BB6502 simulator + kernel build
# =============================================================================

# -----------------------------------------------------------------------------
#  Paths
# -----------------------------------------------------------------------------
RTL_DIR        := rtl
CPU_DIR        := $(RTL_DIR)/verilog-65C02-microcode/generic
TB_FILE        := $(RTL_DIR)/tb.v

SW_DIR         := sw
PROG_DIR       := $(SW_DIR)/prog
BOOT_DIR       := $(SW_DIR)/boot

BUILD_DIR      := build
DISK_DIR       := disk

# -----------------------------------------------------------------------------
#  Toolchain
# -----------------------------------------------------------------------------
IVERILOG       := iverilog
VVP            := vvp
CC65           := cc65
CA65           := ca65
LD65           := ld65
CC             := cc

SDL_CFLAGS     := $(shell pkg-config --cflags sdl2 SDL2_ttf 2>/dev/null || echo "-I/opt/homebrew/include")
SDL_LDFLAGS    := $(shell pkg-config --libs   sdl2 SDL2_ttf 2>/dev/null || echo "-L/opt/homebrew/lib -lSDL2 -lSDL2_ttf")

# -----------------------------------------------------------------------------
#  Flags
# -----------------------------------------------------------------------------
TOP_MODULE     := tb
IVERILOG_FLAGS := -g2012 -Wall -I$(CPU_DIR)
CC65_FLAGS     := -Oir --cpu 65c02
CA65_FLAGS     := --cpu 65c02

# -----------------------------------------------------------------------------
#  Disk layout
# -----------------------------------------------------------------------------
DISK_IMG       := $(BUILD_DIR)/disk.img
DISK_SIZE_KB   := 1440
BOOT_REC_LBA   := 100
KERNEL_LBA     := 101
# PROG_LBA       := 100              # NOTE: redefined to 200 later in the file
PROG_LBA       := 200              # current effective value

# -----------------------------------------------------------------------------
#  Simulation outputs
# -----------------------------------------------------------------------------
SIM_VVP        := $(BUILD_DIR)/sim.vvp
GPU_BIN        := $(BUILD_DIR)/gpu

# -----------------------------------------------------------------------------
#  Build products: kernel (legacy ROM path)
# -----------------------------------------------------------------------------
# LINKER_CFG     := $(SW_DIR)/rom.cfg
# ROM_BIN        := $(BUILD_DIR)/rom.bin
# ROM_HEX        := $(BUILD_DIR)/rom.hex
# LD65_FLAGS     := -C $(LINKER_CFG)

# -----------------------------------------------------------------------------
#  Build products: kernel (new BBX path)
# -----------------------------------------------------------------------------
KERNEL_CFG     := $(SW_DIR)/kernel.cfg
KERNEL_OBJS := $(BUILD_DIR)/crt0.o \
               $(BUILD_DIR)/block.o \
               $(BUILD_DIR)/main.o
KERNEL_BBX     := $(BUILD_DIR)/kernel.bbx

# -----------------------------------------------------------------------------
#  Build products: bootloader
# -----------------------------------------------------------------------------
BOOT_CFG       := $(BOOT_DIR)/boot.cfg
BOOT_OBJS      := $(BUILD_DIR)/boot.o
BOOT_BIN       := $(BUILD_DIR)/bootrom.bin
BOOT_HEX       := $(BUILD_DIR)/bootrom.hex

# -----------------------------------------------------------------------------
#  Build products: user programs
# -----------------------------------------------------------------------------
PROG_SRCS      := $(PROG_DIR)/hello.c
PROG_CRT0      := $(PROG_DIR)/prog_crt0.s
PROG_CFG       := $(PROG_DIR)/prog.cfg
PROG_BBX       := $(BUILD_DIR)/hello.bbx

# -----------------------------------------------------------------------------
#  Build products: boot record
# -----------------------------------------------------------------------------
BOOT_REC_BIN   := $(BUILD_DIR)/bootrec.bin

# Compute kernel size in 512-byte sectors (round up). macOS/Linux compatible.
KERNEL_SIZE_FN  = $(shell echo $$(( ($$(stat -f%z $(KERNEL_BBX) 2>/dev/null || stat -c%s $(KERNEL_BBX)) + 511) / 512 )))

# -----------------------------------------------------------------------------
#  Source discovery
# -----------------------------------------------------------------------------
CPU_SRCS       := $(wildcard $(CPU_DIR)/*.v)
RTL_SRCS       := $(CPU_SRCS) $(TB_FILE) $(RTL_DIR)/mmu6502.v

C_SRCS         := $(wildcard $(SW_DIR)/*.c)
C_OBJS         := $(patsubst $(SW_DIR)/%.c,$(BUILD_DIR)/%.o,$(C_SRCS))

ASM_SRCS       := $(wildcard $(SW_DIR)/*.s)
ASM_OBJS       := $(patsubst $(SW_DIR)/%.s,$(BUILD_DIR)/%.o,$(ASM_SRCS))

ALL_OBJS       := $(ASM_OBJS) $(C_OBJS)


# =============================================================================
#  Top-level targets
# =============================================================================
.PHONY: all clean gpu run

# NOTE: $(BOOT_HEX) here expands to empty because BOOT_HEX isn't defined yet
#       when this line is parsed. See "problems found" above.
all: $(SIM_VVP) $(BOOT_HEX) $(GPU_BIN) $(DISK_IMG)
run: $(SIM_VVP) $(BOOT_HEX) $(GPU_BIN) $(DISK_IMG)


# =============================================================================
#  Verilog simulation
# =============================================================================
$(SIM_VVP): $(RTL_SRCS) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s $(TOP_MODULE) -o $@ $(RTL_SRCS)


# =============================================================================
#  C build pipeline (kernel sources in $(SW_DIR))
# =============================================================================

# C -> assembly
$(BUILD_DIR)/%.s: $(SW_DIR)/%.c | $(BUILD_DIR)
	$(CC65) $(CC65_FLAGS) -o $@ $<

# generated assembly -> object
$(BUILD_DIR)/%.o: $(BUILD_DIR)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

# raw .s -> object
$(BUILD_DIR)/%.o: $(SW_DIR)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<


# =============================================================================
#  Legacy ROM-format kernel build
# =============================================================================
#$(ROM_BIN): $(ALL_OBJS) $(LINKER_CFG) | $(BUILD_DIR)
#	$(LD65) $(LD65_FLAGS) -o $@ $(ALL_OBJS) none.lib

#$(ROM_HEX): $(ROM_BIN)
#	hexdump -v -e '1/1 "%02x\n"' $< > $@


# =============================================================================
#  BBX-format kernel build
# =============================================================================
# NOTE: $(KERNEL_OBJS) is undefined. See "problems found" above.
$(KERNEL_BBX): $(KERNEL_OBJS) $(KERNEL_CFG)
	$(LD65) -C $(KERNEL_CFG) -o $@ $(KERNEL_OBJS) none.lib


# =============================================================================
#  Bootloader build
# =============================================================================
# NOTE: $< is missing from this recipe. See "problems found" above.
$(BUILD_DIR)/boot.o: $(BOOT_DIR)/boot.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

$(BOOT_BIN): $(BOOT_OBJS) $(BOOT_CFG)
	$(LD65) -C $(BOOT_CFG) -o $@ $(BOOT_OBJS)

$(BOOT_HEX): $(BOOT_BIN)
	hexdump -v -e '1/1 "%02x\n"' $< > $@


# =============================================================================
#  User-program build (separate from kernel; lives in $(PROG_DIR))
# =============================================================================
$(BUILD_DIR)/prog_%.o: $(PROG_DIR)/%.c | $(BUILD_DIR)
	$(CC65) $(CC65_FLAGS) -o $(BUILD_DIR)/prog_$*.s $<
	$(CA65) $(CA65_FLAGS) -o $@ $(BUILD_DIR)/prog_$*.s

$(BUILD_DIR)/prog_crt0.o: $(PROG_CRT0) | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

$(PROG_BBX): $(BUILD_DIR)/prog_crt0.o $(BUILD_DIR)/prog_hello.o $(PROG_CFG)
	$(LD65) -C $(PROG_CFG) -o $@ \
	    $(BUILD_DIR)/prog_crt0.o $(BUILD_DIR)/prog_hello.o none.lib


# =============================================================================
#  Boot record generation
# =============================================================================
$(BOOT_REC_BIN): $(KERNEL_BBX) tools/mkbootrec.py | $(BUILD_DIR)
	python3 tools/mkbootrec.py $(KERNEL_LBA) $(KERNEL_SIZE_FN) $@


# =============================================================================
#  GPU coprocessor (host-side SDL window)
# =============================================================================
$(GPU_BIN): tools/gpu.c | $(BUILD_DIR)
	$(CC) -O2 -Wall $(SDL_CFLAGS) -o $@ $< $(SDL_LDFLAGS)


# =============================================================================
#  Disk image
# =============================================================================
# NOTE: Three $(DISK_IMG) rules exist below. Only the LAST one's recipe runs.
#       See "problems found" above.

# --- Rule 1 (dead): basic FAT16 from $(DISK_DIR) ---
#$(DISK_IMG): $(shell find $(DISK_DIR) -type f 2>/dev/null) | $(BUILD_DIR)
#	@echo "Building disk image from $(DISK_DIR)/"
#	@dd if=/dev/zero of=$@ bs=1024 count=$(DISK_SIZE_KB) status=none
#	@mformat -i $@ -F ::
#	@if [ -d $(DISK_DIR) ] && [ "$$(ls -A $(DISK_DIR) 2>/dev/null)" ]; then \
#	  mcopy -i $@ -s $(DISK_DIR)/* ::; \
#	fi
#
## --- Rule 2 (dead): FAT16 + prog ---
#$(DISK_IMG): $(PROG_BBX)
#	@echo "Building disk image..."
#	@dd if=/dev/zero of=$@ bs=1024 count=$(DISK_SIZE_KB) status=none
#	@mformat -i $@ -F ::
#	@if [ -d $(DISK_DIR) ] && [ "$$(ls -A $(DISK_DIR) 2>/dev/null)" ]; then \
#	  mcopy -i $@ -s $(DISK_DIR)/* ::; \
#	fi
#	@echo "Placing $(PROG_BBX) at LBA $(PROG_LBA)"
#	@dd if=$(PROG_BBX) of=$@ bs=512 seek=$(PROG_LBA) conv=notrunc status=none

# --- Rule 3 (active): FAT16 + boot record + kernel + prog ---
$(DISK_IMG): $(KERNEL_BBX) $(PROG_BBX) $(BOOT_REC_BIN) $(shell find $(DISK_DIR) -type f 2>/dev/null) | $(BUILD_DIR)
	@echo "Building disk image..."
	@dd if=/dev/zero of=$@ bs=1024 count=$(DISK_SIZE_KB) status=none
	@mformat -i $@ -F ::
	@if [ -d $(DISK_DIR) ] && [ "$$(ls -A $(DISK_DIR) 2>/dev/null)" ]; then \
	  mcopy -i $@ -s $(DISK_DIR)/* ::; \
	fi
	@echo "  Boot record    -> LBA $(BOOT_REC_LBA)"
	@dd if=$(BOOT_REC_BIN) of=$@ bs=512 seek=$(BOOT_REC_LBA) conv=notrunc status=none
	@echo "  Kernel BBX     -> LBA $(KERNEL_LBA)"
	@dd if=$(KERNEL_BBX) of=$@ bs=512 seek=$(KERNEL_LBA) conv=notrunc status=none
	@echo "  Hello program  -> LBA $(PROG_LBA)"
	@dd if=$(PROG_BBX) of=$@ bs=512 seek=$(PROG_LBA) conv=notrunc status=none


# =============================================================================
#  Run / GPU launch targets
# =============================================================================
gpu: $(GPU_BIN)
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@mkfifo /tmp/bb6502_in  2>/dev/null || true
	$(GPU_BIN)

# NOTE: This is the second 'run:' definition. The first (in 'all:' block above)
#       lists $(BOOT_HEX) but has no recipe. This one's recipe wins.
#       Also note: the inline '# comment' inside the recipe is on a line that
#       has '\' before it but with whitespace in between — not a line
#       continuation. See "problems found" above.
run: $(SIM_VVP) $(BOOT_HEX) $(GPU_BIN) $(DISK_IMG)
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@mkfifo /tmp/bb6502_in  2>/dev/null || true
	@echo "Starting BB6502. Close the SDL window or press Ctrl-C to exit."
	@$(GPU_BIN) & GPU_PID=$$!; \
	 sleep 0.3; \
	 $(VVP) $(SIM_VVP) & VVP_PID=$$!; \
	 (sleep 0.5; echo "" > /tmp/bb6502_in) & \
	 trap "kill $$GPU_PID $$VVP_PID 2>/dev/null; exit 0" EXIT INT TERM; \
	 wait $$GPU_PID; \
	 kill $$VVP_PID 2>/dev/null; \
	 wait $$VVP_PID 2>/dev/null; true


# =============================================================================
#  Housekeeping
# =============================================================================
$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
