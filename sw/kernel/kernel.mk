# Destination: sw/kernel/kernel.mk  (OS: kernel.bbx + bootrom.hex + bootrec.bin)
ROOT := ../..
include $(ROOT)/common.mk

BOOT_DIR    := ../boot

KERNEL_SRC  := ./src
KERNEL_CFG  := kernel.cfg
KERNEL_OBJS := $(BUILD_DIR)/crt0.o \
               $(BUILD_DIR)/block.o \
               $(BUILD_DIR)/memcpy512.o \
               $(BUILD_DIR)/main.o \
               $(BUILD_DIR)/brk.o \
               $(BUILD_DIR)/syscalls.o \
               $(BUILD_DIR)/exec.o

BOOT_CFG    := $(BOOT_DIR)/boot.cfg
BOOT_OBJS   := $(BUILD_DIR)/boot.o

# Kernel size in 512-byte sectors, rounded up (macOS/Linux stat).
KERNEL_SIZE_FN = $(shell echo $$(( ($$(stat -f%z $(KERNEL_BBX) 2>/dev/null || stat -c%s $(KERNEL_BBX)) + 511) / 512 )))

.PHONY: all clean

all: $(KERNEL_BBX) $(BOOT_HEX) $(BOOT_REC_BIN)

$(BUILD_DIR)/%.s: $(KERNEL_SRC)/%.c | $(BUILD_DIR)
	$(CC65) $(CC65_FLAGS) -o $@ $<
$(BUILD_DIR)/%.o: $(BUILD_DIR)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<
$(BUILD_DIR)/%.o: $(KERNEL_SRC)/%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

$(KERNEL_BBX): $(KERNEL_OBJS) $(KERNEL_CFG)
	$(LD65) -C $(KERNEL_CFG) -o $@ $(KERNEL_OBJS) none.lib

$(BUILD_DIR)/boot.o: $(BOOT_DIR)/boot.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<
$(BOOT_BIN): $(BOOT_OBJS) $(BOOT_CFG)
	$(LD65) -C $(BOOT_CFG) -o $@ $(BOOT_OBJS)
$(BOOT_HEX): $(BOOT_BIN)
	hexdump -v -e '1/1 "%02x\n"' $< > $@

$(BOOT_REC_BIN): $(KERNEL_BBX) $(TOOLS_DIR)/mkbootrec.py | $(BUILD_DIR)
	python3 $(TOOLS_DIR)/mkbootrec.py $(KERNEL_LBA) $(KERNEL_SIZE_FN) $@

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -f $(KERNEL_OBJS) $(KERNEL_BBX) $(BOOT_OBJS) $(BOOT_BIN) $(BOOT_HEX) $(BOOT_REC_BIN)
