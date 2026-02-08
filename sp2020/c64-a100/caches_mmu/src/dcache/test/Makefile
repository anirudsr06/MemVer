# ============================================================
# MVU Unit Test Makefile
# ============================================================

# ---- Tools -------------------------------------------------
BSC        ?= bsc
VERILATOR  ?= verilator
CXX        ?= g++

# ---- Top module --------------------------------------------
TOP_MODULE = mkTbMVURefactored
TOP_BSV    = tb_mvu_refactored.bsv

# ---- Output dirs -------------------------------------------
BUILD_DIR  = build_mvu
VERILOG_DIR= verilog_mvu
OBJ_DIR    = obj_dir_mvu

# ---- Include paths (reuse project structure) ---------------
BSV_PATHS = \
	. \
	../ \
	../../ \
	../../../../common_bsv \
	../../../../common_verilog/bsvwrappers \

BSV_PFLAGS = $(addprefix -p ,$(BSV_PATHS))
BSV_IFLAGS = -I ../../dcache/dcache.defines

# ---- Macro defines (copied from Makefile.inc, trimmed) -----
include ../testbench/Makefile.inc

DEFINES = $(BSC_DEFINES)

BSC_FLAGS = \
	-u -verilog \
	-elab \
	-check-assert \
	-opt-undetermined-vals \
	-remove-false-rules \
	-remove-empty-rules \
	-unspecified-to X \
	$(DEFINES) \
	$(BSV_PFLAGS) \
	$(BSV_IFLAGS) \
	-bdir $(BUILD_DIR) \
	-vdir $(VERILOG_DIR)

# ============================================================
# Targets
# ============================================================

all: sim

# ---- Compile BSV -> Verilog --------------------------------
compile:
	@mkdir -p $(BUILD_DIR) $(VERILOG_DIR)
	$(BSC) $(BSC_FLAGS) \
	    -g $(TOP_MODULE) \
	    $(TOP_BSV)

# ---- Verilator build ---------------------------------------
verilate: compile
	$(VERILATOR) --cc $(VERILOG_DIR)/$(TOP_MODULE).v \
	    --exe sim_main.cpp \
	    -O3 \
	    --top-module $(TOP_MODULE) \
	    --Mdir $(OBJ_DIR)

	$(MAKE) -C $(OBJ_DIR) -f V$(TOP_MODULE).mk

# ---- Run simulation ----------------------------------------
sim: verilate
	./$(OBJ_DIR)/V$(TOP_MODULE)

# ---- Clean -------------------------------------------------
clean:
	rm -rf $(BUILD_DIR) $(VERILOG_DIR) $(OBJ_DIR)

.PHONY: all compile verilate sim clean

