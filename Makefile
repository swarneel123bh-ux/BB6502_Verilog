# ---- Paths ----
RTL_DIR    := rtl
CPU_DIR    := $(RTL_DIR)/verilog-65C02-microcode/generic
TB_FILE    := $(RTL_DIR)/tb.v
SW_DIR     := sw
BUILD_DIR  := build

# ---- Toolchain ----
IVERILOG := iverilog
VVP      := vvp
CA65     := ca65
LD65     := ld65
CC       := cc
SDL_CFLAGS  := $(shell pkg-config --cflags sdl2 SDL2_ttf 2>/dev/null || echo "-I/opt/homebrew/include")
SDL_LDFLAGS := $(shell pkg-config --libs sdl2 SDL2_ttf 2>/dev/null || echo "-L/opt/homebrew/lib -lSDL2 -lSDL2_ttf")
GPU_BIN  := $(BUILD_DIR)/gpu


# ---- Files ----
CPU_SRCS    := $(wildcard $(CPU_DIR)/*.v)
RTL_SRCS    := $(CPU_SRCS) $(TB_FILE)

ASM_SRCS    := $(wildcard $(SW_DIR)/*.s)
ASM_OBJS    := $(patsubst $(SW_DIR)/%.s,$(BUILD_DIR)/%.o,$(ASM_SRCS))

ROM_BIN     := $(BUILD_DIR)/rom.bin
ROM_HEX     := $(BUILD_DIR)/rom.hex
SIM_VVP     := $(BUILD_DIR)/sim.vvp
LINKER_CFG  := $(SW_DIR)/rom.cfg

TOP_MODULE  := tb

# ---- Flags ----
IVERILOG_FLAGS := -g2012 -Wall -I$(CPU_DIR)
CA65_FLAGS     := --cpu 65c02
LD65_FLAGS     := -C $(LINKER_CFG)

.PHONY: all run clean

all: $(SIM_VVP) $(ROM_HEX) $(GPU_BIN)

# Compile CPU + testbench into a vvp executable
$(SIM_VVP): $(RTL_SRCS) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s $(TOP_MODULE) -o $@ $(RTL_SRCS)

# Assemble each .s -> .o
$(BUILD_DIR)/%.o: $(SW_DIR)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

# Link objects -> raw binary at ROM origin
$(ROM_BIN): $(ASM_OBJS) $(LINKER_CFG) | $(BUILD_DIR)
	$(LD65) $(LD65_FLAGS) -o $@ $(ASM_OBJS)

# Binary -> ASCII hex, one byte per line (consumed by $readmemh)
$(ROM_HEX): $(ROM_BIN)
	hexdump -v -e '1/1 "%02x\n"' $< > $@

$(GPU_BIN): tools/gpu.c | $(BUILD_DIR)
	$(CC) -O2 -Wall $(SDL_CFLAGS) -o $@ $< $(SDL_LDFLAGS)

.PHONY: gpu
gpu: $(GPU_BIN)
		@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
		$(GPU_BIN)

$(BUILD_DIR):
	mkdir -p $@

# Run with terminal in raw, non-blocking mode so the simulated ACIA
# sees keystrokes immediately. Restores tty settings on exit (Ctrl-C, $finish, crash).
run: $(SIM_VVP) $(ROM_HEX)
	@echo "Starting simulation. Feed input via: echo hello > /tmp/bb6502_in"
	@echo "Press Ctrl-C to exit."
	$(VVP) $(SIM_VVP)

clean:
	rm -rf $(BUILD_DIR)
