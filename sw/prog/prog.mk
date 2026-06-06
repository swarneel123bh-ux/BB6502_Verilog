# Destination: sw/prog/prog.mk  (user programs: hello.bbx, hello2.bbx + syslib)
ROOT := ../..
include $(ROOT)/common.mk
PROG_SRC   := ./src
PROG_CFG   := prog.cfg
PROG_CRT0  := $(PROG_SRC)/prog_crt0.s
# objects every program shares
PROG_COMMON := $(BUILD_DIR)/prog_crt0.o \
               $(BUILD_DIR)/prog_syslib.o
# per-program object sets
HELLO_OBJS  := $(PROG_COMMON) $(BUILD_DIR)/prog_hello.o
HELLO2_OBJS := $(PROG_COMMON) $(BUILD_DIR)/prog_hello2.o
.PHONY: all syslib clean
all: $(PROG_BBX) $(PROG2_BBX)
syslib: $(BUILD_DIR)/prog_syslib.o
$(BUILD_DIR)/prog_%.s: $(PROG_SRC)/%.c | $(BUILD_DIR)
	$(CC65) $(CC65_FLAGS) -o $@ $
$(BUILD_DIR)/prog_%.o: $(BUILD_DIR)/prog_%.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $
$(BUILD_DIR)/prog_syslib.o: $(PROG_SRC)/syslib.s | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $
$(BUILD_DIR)/prog_crt0.o: $(PROG_CRT0) | $(BUILD_DIR)
	$(CA65) $(CA65_FLAGS) -o $@ $
$(PROG_BBX): $(HELLO_OBJS) $(PROG_CFG)
	$(LD65) -C $(PROG_CFG) -o $@ $(HELLO_OBJS) none.lib
$(PROG2_BBX): $(HELLO2_OBJS) $(PROG_CFG)
	$(LD65) -C $(PROG_CFG) -o $@ $(HELLO2_OBJS) none.lib
$(BUILD_DIR):
	mkdir -p $@
clean:
	rm -f $(PROG_COMMON) \
	      $(BUILD_DIR)/prog_hello.o $(BUILD_DIR)/prog_hello2.o \
	      $(PROG_BBX) $(PROG2_BBX)
