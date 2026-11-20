# Destination: rtl/rtl.mk  (sim + gpu for `make run`; debugger for `make run-dbg`)
# Everything in the RTL is built with Verilator. No iverilog, no VPI.
ROOT := ..
include $(ROOT)/common.mk

RTL_DIR        := .
CPU_DIR        := $(RTL_DIR)/verilog-65C02-microcode/generic
TB_FILE        := $(RTL_DIR)/tb.v

TOP_MODULE     := tb

SDL_CFLAGS     := $(shell pkg-config --cflags sdl2 SDL2_ttf 2>/dev/null || echo "-I/opt/homebrew/include")
SDL_LDFLAGS    := $(shell pkg-config --libs   sdl2 SDL2_ttf 2>/dev/null || echo "-L/opt/homebrew/lib -lSDL2 -lSDL2_ttf")

CPU_SRCS       := $(wildcard $(CPU_DIR)/*.v)
RTL_SRCS       := $(CPU_SRCS) $(TB_FILE) $(RTL_DIR)/mmu6502.v $(RTL_DIR)/timer6502.v
ABS_RTL_SRCS   := $(abspath $(RTL_SRCS))
ABS_BUILD      := $(abspath $(BUILD_DIR))

# Simulator: the testbench model plus tools/fastsim/main.cpp, paced to the wall clock
SIM_MAIN       := $(abspath $(TOOLS_DIR)/fastsim/main.cpp)

# Debugger: the testbench model plus rtl/dbg/dbg_main.cpp and debugger.c (ncurses)
DBG_CSRCS      := $(RTL_DIR)/dbg/debugger.c
DBG_MAIN       := $(RTL_DIR)/dbg/dbg_main.cpp
DBG_HDRS       := $(RTL_DIR)/dbg/debugger.h
ABS_DBG_DIR    := $(abspath $(RTL_DIR)/dbg)

.PHONY: all sim gpu dbg clean

all: sim gpu
sim: $(SIM_BIN)
gpu: $(GPU_BIN)
dbg: $(DBG_BIN)

$(SIM_BIN): $(SIM_MAIN) $(RTL_SRCS)
	@mkdir -p $(ABS_BUILD)/sim/obj
	$(VERILATOR) --cc --exe --build --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
		--top-module $(TOP_MODULE) $(SIM_MAIN) $(ABS_RTL_SRCS) \
		-Mdir $(ABS_BUILD)/sim/obj

# The debugger's C part (ncurses UI, disassembler, symbols), compiled as plain C
$(DBG_OBJ): $(DBG_CSRCS) $(DBG_HDRS) | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CC) -c -O2 -Wall -I$(ABS_DBG_DIR) -o $@ $(DBG_CSRCS)

# The debugger binary (public signals so dbg_main.cpp can read the model)
$(DBG_BIN): $(DBG_MAIN) $(DBG_OBJ) $(RTL_SRCS) $(DBG_HDRS)
	@mkdir -p $(ABS_BUILD)/dbgsim/obj
	$(VERILATOR) --cc --exe --build --timing --public-flat-rw -O3 \
		-Wno-fatal -Wno-lint -Wno-style --top-module $(TOP_MODULE) \
		-CFLAGS "-I$(ABS_DBG_DIR)" -LDFLAGS "$(abspath $(DBG_OBJ)) -lncurses" \
		$(abspath $(DBG_MAIN)) $(ABS_RTL_SRCS) \
		-Mdir $(ABS_BUILD)/dbgsim/obj

$(GPU_BIN): $(TOOLS_DIR)/gpu.c | $(BUILD_DIR)
	$(CC) -O2 -Wall $(SDL_CFLAGS) -o $@ $< $(SDL_LDFLAGS)

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -f $(GPU_BIN)
	rm -rf $(ABS_BUILD)/sim $(ABS_BUILD)/dbgsim $(DBG_OBJ)
