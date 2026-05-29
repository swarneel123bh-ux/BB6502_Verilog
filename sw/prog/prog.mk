# Destination: sw/prog/prog.mk  (user programs: hello.bbx + syslib)
ROOT := ../..
include $(ROOT)/common.mk

PROG_CFG   := prog.cfg
PROG_CRT0  := prog_crt0.s
PROG_OBJS  := $(BUILD_DIR)/prog_crt0.o \
              $(BUILD_DIR)/prog_hello.o \
              $(BUILD_DIR)/prog_syslib.o

.PHONY: all syslib clean

all: $(PROG_BBX)
syslib: $(BUILD_DIR)/prog_syslib.o

$(BUILD_DIR)/prog_%.s: %.c | $(BUILD_DIR)
	$(CC65) $(CC65_FLAGS) -o $@ $<
$(BUILD_DIR)/prog_%.o: $(BUILD_DIR)/prog_%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<
$(BUILD_DIR)/prog_syslib.o: syslib.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<
$(BUILD_DIR)/prog_crt0.o: $(PROG_CRT0) | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $<

$(PROG_BBX): $(PROG_OBJS) $(PROG_CFG)
	$(LD65) -C $(PROG_CFG) -o $@ $(PROG_OBJS) none.lib

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -f $(PROG_OBJS) $(PROG_BBX)
