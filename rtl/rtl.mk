# Destination: rtl/rtl.mk  (emulator: sim.vvp + gpu)
ROOT := ..
include $(ROOT)/common.mk

RTL_DIR        := .
CPU_DIR        := $(RTL_DIR)/verilog-65C02-microcode/generic
TB_FILE        := $(RTL_DIR)/tb.v

TOP_MODULE     := tb
IVERILOG_FLAGS := -g2012 -Wall -I$(CPU_DIR)

SDL_CFLAGS     := $(shell pkg-config --cflags sdl2 SDL2_ttf 2>/dev/null || echo "-I/opt/homebrew/include")
SDL_LDFLAGS    := $(shell pkg-config --libs   sdl2 SDL2_ttf 2>/dev/null || echo "-L/opt/homebrew/lib -lSDL2 -lSDL2_ttf")

CPU_SRCS       := $(wildcard $(CPU_DIR)/*.v)
RTL_SRCS       := $(CPU_SRCS) $(TB_FILE) $(RTL_DIR)/mmu6502.v

.PHONY: all sim gpu clean

all: sim gpu
sim: $(SIM_VVP)
gpu: $(GPU_BIN)

$(SIM_VVP): $(RTL_SRCS) | $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s $(TOP_MODULE) -o $@ $(RTL_SRCS)

$(GPU_BIN): $(TOOLS_DIR)/gpu.c | $(BUILD_DIR)
	$(CC) -O2 -Wall $(SDL_CFLAGS) -o $@ $< $(SDL_LDFLAGS)

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -f $(SIM_VVP) $(GPU_BIN)
