# Destination: ./Makefile  (project root — this is the file you run)
ROOT := .
include $(ROOT)/common.mk

.PHONY: all rtl kernel prog syslib run gpu clean

all: rtl kernel prog $(DISK_IMG)

rtl:
	$(MAKE) -C rtl -f rtl.mk

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

gpu:
	$(MAKE) -C rtl -f rtl.mk gpu
	@mkfifo /tmp/bb6502_gpu 2>/dev/null || true
	@mkfifo /tmp/bb6502_in  2>/dev/null || true
	$(GPU_BIN)

run: all
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

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)
