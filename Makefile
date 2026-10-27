# Destination: ./Makefile  (project root — this is the file you run)
#
# Targets:
#   make            build everything: sim.vvp, gpu, boot ROM, kernel, programs,
#                   build/disk.img
#   make run        build, then start the SDL monitor (gpu) and the simulation
#   make debug      also build the debugger (sim_dbg.vvp + bbdbg.vpi)
#   make run-dbg    like run, but the simulation runs under the debugger in
#                   this terminal (see docs/debugger.md)
#   make clean      remove build/
# Sub-makefiles: rtl/rtl.mk, sw/kernel/kernel.mk, sw/prog/prog.mk; shared
# settings (tools, flags, disk LBAs, file names) are in common.mk.
ROOT := .
include $(ROOT)/common.mk

.PHONY: all rtl kernel prog syslib run gpu debug run-dbg clean

all: rtl kernel prog $(DISK_IMG)

rtl:
	$(MAKE) -C rtl -f rtl.mk

# Debugger build: everything `all` builds, plus sim_dbg.vvp and bbdbg.vpi
debug: all
	$(MAKE) -C rtl -f rtl.mk dbg

# Symbol files the debugger loads; add more with DBG_ARGS=+dbg_sym=<file>
DBG_SYMS := +dbg_sym=$(BOOT_DBG) +dbg_sym=$(KERNEL_DBG) +dbg_sym=$(PROG_DBG)
DBG_LOG  := $(BUILD_DIR)/sim_dbg.log

kernel:
	$(MAKE) -C sw/kernel -f kernel.mk

prog:
	$(MAKE) -C sw/prog -f prog.mk

syslib:
	$(MAKE) -C sw/prog -f prog.mk syslib

$(DISK_IMG): kernel prog $(shell find $(DISK_DIR) -type f 2>/dev/null) | $(BUILD_DIR)
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
	@echo "  Hello2 program -> LBA $(PROG2_LBA)"
	@dd if=$(PROG2_BBX) of=$@ bs=512 seek=$(PROG2_LBA) conv=notrunc status=none
	@echo "  Disk test      -> LBA $(PROG3_LBA)"
	@dd if=$(PROG3_BBX) of=$@ bs=512 seek=$(PROG3_LBA) conv=notrunc status=none

gpu:
	$(MAKE) -C rtl -f rtl.mk gpu
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@$(MAKE_INPUT_FILE)
	$(GPU_BIN)

# /tmp/bb6502_in must be a regular file, not a FIFO: tb.v polls it with
# $fseek + $fgetc, which returns EOF on an empty file but blocks the whole
# simulation on an empty FIFO. rm first in case an old FIFO is still there.
MAKE_INPUT_FILE = rm -f /tmp/bb6502_in && touch /tmp/bb6502_in

run: all
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@$(MAKE_INPUT_FILE)
	@echo "Starting BB6502. Close the SDL window or press Ctrl-C to exit."
	@$(GPU_BIN) & GPU_PID=$$!; \
	 sleep 0.3; \
	 $(VVP) $(SIM_VVP) & VVP_PID=$$!; \
	 trap "kill $$GPU_PID $$VVP_PID 2>/dev/null; exit 0" EXIT INT TERM; \
	 wait $$GPU_PID; \
	 kill $$VVP_PID 2>/dev/null; \
	 wait $$VVP_PID 2>/dev/null; true

# Same as `run`, but the simulation runs under the debugger in this terminal.
# vvp's own output goes to $(DBG_LOG); the debugger draws on /dev/tty.
run-dbg: debug
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@$(MAKE_INPUT_FILE)
	@$(GPU_BIN) & GPU_PID=$$!; \
	 sleep 0.3; \
	 trap "kill $$GPU_PID 2>/dev/null" EXIT INT TERM; \
	 $(VVP) -M $(BUILD_DIR) -m bbdbg $(SIM_DBG_VVP) $(DBG_SYMS) $(DBG_ARGS) > $(DBG_LOG) 2>&1; \
	 kill $$GPU_PID 2>/dev/null; \
	 echo "Simulation ended. vvp log: $(DBG_LOG)"; true

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
