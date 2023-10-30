# Build options can be changed by modifying the makefile or by building with 'make SETTING=value'.
# It is also possible to override the settings in Defaults in a file called .make_options as 'SETTING=value'.

-include .make_options

MAKEFLAGS += --no-builtin-rules

SHELL = /bin/bash
.SHELLFLAGS = -o pipefail -c

#### Defaults ####

# TODO
# If non-zero, passes -v to compiler
COMPILER_VERBOSE ?= 0
# If non-zero touching an assembly file will rebuild any file that depends on it
DEP_ASM ?= 1
# If non-zero touching an included file will rebuild any file that depends on it
DEP_INCLUDE ?= 1

# Set prefix to mips binutils binaries (mips-linux-gnu-ld => 'mips-linux-gnu-') - Change at your own risk!
# In nearly all cases, not having 'mips-linux-gnu-*' binaries on the PATH is indicative of missing dependencies
MIPS_BINUTILS_PREFIX ?= mips-linux-gnu-


VERSION ?= us

TARGET               := SCUS_945.71


### Output ###

BUILD_DIR := build
EXE       := $(BUILD_DIR)/$(VERSION)/$(TARGET)
ELF       := $(BUILD_DIR)/$(VERSION)/$(TARGET).elf
LD_MAP    := $(BUILD_DIR)/$(VERSION)/$(TARGET).map
LD_SCRIPT := linker_scripts/$(VERSION)/$(TARGET).ld


#### Setup ####

MAKE = make
CPPFLAGS += -fno-dollars-in-identifiers -P
LDFLAGS  := --no-check-sections --accept-unknown-input-arch --emit-relocs

#### Tools ####
ifneq ($(shell type $(MIPS_BINUTILS_PREFIX)ld >/dev/null 2>/dev/null; echo $$?), 0)
$(error Please install or build $(MIPS_BINUTILS_PREFIX))
endif

# CC              :=

AS              := $(MIPS_BINUTILS_PREFIX)as
LD              := $(MIPS_BINUTILS_PREFIX)ld
OBJCOPY         := $(MIPS_BINUTILS_PREFIX)objcopy
OBJDUMP         := $(MIPS_BINUTILS_PREFIX)objdump
GCC             := $(MIPS_BINUTILS_PREFIX)gcc
CPP             := $(MIPS_BINUTILS_PREFIX)cpp
STRIP           := $(MIPS_BINUTILS_PREFIX)strip
ICONV           := iconv

SPLAT             ?= tools/splat/split.py
SPLAT_YAML        ?= $(TARGET).$(VERSION).yaml


IINC       := -Iinclude -Ibin/$(VERSION) -I$(BUILD_DIR)/bin/$(VERSION) -I.


# WARNINGS        :=
ASFLAGS         := -march=r3000 -mtune=r3000 -no-pad-sections -32 -G0
# COMMON_DEFINES  := -D_MIPS_SZLONG=32 -D__USE_ISOC99
# GBI_DEFINES     := -DF3DEX_GBI_2
# RELEASE_DEFINES := -DNDEBUG -D_FINALROM
# AS_DEFINES      := -DMIPSEB -D_LANGUAGE_ASSEMBLY -D_ULTRA64
# C_DEFINES       := -D_LANGUAGE_C
ENDIAN          := -EL


# Use relocations names in the dump
OBJDUMP_FLAGS := --disassemble --reloc --disassemble-zeroes -Mno-aliases

ifneq ($(OBJDUMP_BUILD), 0)
	OBJDUMP_CMD = $(OBJDUMP) $(OBJDUMP_FLAGS) $@ > $(@:.o=.dump.s)
	OBJCOPY_BIN = $(OBJCOPY) -O binary $@ $@.bin
else
	OBJDUMP_CMD = @:
	OBJCOPY_BIN = @:
endif

ifneq ($(COMPILER_VERBOSE), 0)
	COMP_VERBOSE_FLAG := -v
else
	COMP_VERBOSE_FLAG :=
endif



#### Files ####

$(shell mkdir -p asm bin linker_scripts/$(VERSION)/auto)

SRC_DIRS      := $(shell find src -type d)
ASM_DIRS      := $(shell find asm/$(VERSION) -type d -not -path "asm/$(VERSION)/nonmatchings/*" -not -path "asm/$(VERSION)/lib/*")
BIN_DIRS      := $(shell find bin/$(VERSION) -type d)

C_FILES       := $(foreach dir,$(SRC_DIRS),$(wildcard $(dir)/*.c))
S_FILES       := $(foreach dir,$(ASM_DIRS) $(SRC_DIRS),$(wildcard $(dir)/*.s))
BIN_FILES     := $(foreach dir,$(BIN_DIRS),$(wildcard $(dir)/*.bin))

O_FILES       := $(foreach f,$(C_FILES:.c=.o),$(BUILD_DIR)/$f) \
                 $(foreach f,$(S_FILES:.s=.o),$(BUILD_DIR)/$f) \
                 $(foreach f,$(BIN_FILES:.bin=.o),$(BUILD_DIR)/$f)

SEGMENTS_SCRIPTS := $(wildcard linker_scripts/$(VERSION)/partial/*.ld)
SEGMENTS_D       := $(SEGMENTS_SCRIPTS:.ld=.d)
SEGMENTS         := $(foreach f, $(SEGMENTS_SCRIPTS:.ld=), $(notdir $f))
SEGMENTS_O       := $(foreach f, $(SEGMENTS), $(BUILD_DIR)/segments/$(VERSION)/$f.o)


# Automatic dependency files
DEP_FILES := $(LD_SCRIPT:.ld=.d) $(SEGMENTS_D)

ifneq ($(DEP_ASM), 0)
	DEP_FILES += $(O_FILES:.o=.asmproc.d)
endif

ifneq ($(DEP_INCLUDE), 0)
	DEP_FILES += $(O_FILES:.o=.d)
endif

# create build directories
$(shell mkdir -p $(BUILD_DIR)/linker_scripts/$(VERSION) $(BUILD_DIR)/$(VERSION) $(BUILD_DIR)/linker_scripts/$(VERSION)/auto $(BUILD_DIR)/segments/$(VERSION) $(foreach dir,$(SRC_DIRS) $(ASM_DIRS) $(BIN_DIRS),$(BUILD_DIR)/$(dir)))

# directory flags

# per-file flags


#### Main Targets ###

all: $(EXE)
ifneq ($(COMPARE),0)
	@md5sum $(EXE)
	@md5sum -c $(TARGET).$(VERSION).md5
endif

clean:
	$(RM) -r $(BUILD_DIR)/asm $(BUILD_DIR)/bin $(BUILD_DIR)/src $(EXE) $(ELF)

distclean: clean
	$(RM) -r $(BUILD_DIR) asm/ bin/ .splat/
	$(RM) -r linker_scripts/$(VERSION)/auto $(LD_SCRIPT)
#	$(MAKE) -C tools distclean

extract:
	$(RM) -r asm/$(VERSION) bin/$(VERSION) linker_scripts/$(VERSION)/partial $(LD_SCRIPT) $(LD_SCRIPT:.ld=.d)
	$(SPLAT) $(SPLAT_YAML)

diff-init: all
	$(RM) -rf expected/
	mkdir -p expected/
	cp -r $(BUILD_DIR) expected/$(BUILD_DIR)

init:
	$(MAKE) distclean
#	$(MAKE) setup
	$(MAKE) extract
#	$(MAKE) lib
	$(MAKE) all
	$(MAKE) diff-init

.PHONY: all clean distclean extract diff-init init
.DEFAULT_GOAL := all
# Prevent removing intermediate files
.SECONDARY:


#### Various Recipes ####

$(EXE): $(ELF)
	$(OBJCOPY) -O binary $< $@

$(ELF): $(O_FILES) $(SEGMENTS_O) $(LD_SCRIPT) $(BUILD_DIR)/linker_scripts/$(VERSION)/undefined_syms.ld
	$(LD) $(ENDIAN) $(LDFLAGS) -T $(LD_SCRIPT) \
	    -T $(BUILD_DIR)/linker_scripts/$(VERSION)/undefined_syms.ld -T linker_scripts/$(VERSION)/auto/undefined_funcs_auto.ld -T linker_scripts/$(VERSION)/auto/undefined_syms_auto.ld \
		-Map $(LD_MAP) -o $@



$(BUILD_DIR)/%.ld: %.ld
	$(CPP) $(CPPFLAGS) $(BUILD_DEFINES) $(IINC) $(COMP_VERBOSE_FLAG) $< > $@


$(BUILD_DIR)/%.o: %.bin
	$(OBJCOPY) -I binary -O elf32-little $< $@

$(BUILD_DIR)/%.o: %.s
	$(AS) $(ASFLAGS) $(ENDIAN) $(IINC) -I $(dir $*) -o $@  $<
	$(OBJDUMP_CMD)



-include $(DEP_FILES)

# Print target for debugging
print-% : ; $(info $* is a $(flavor $*) variable set to [$($*)]) @true
