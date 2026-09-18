# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

PROJECT            ?=
BEOL               ?= asap7
TOP_LEVEL          ?=
TB                 ?= tb_$(TOP_LEVEL)
OUT_DIR            ?= no_name
NETLIST_DIR        ?= no_name
VCD_DIR            ?= no_name
CLK_PERIOD_NS      ?= 1
PARAMS             ?= none
KEEP_HIERARCHY     ?= 0
KEEP_MODULES       ?= none
BLACKBOX_MODULES   ?= none
VCD                ?= 0
CORE_UTIL          ?= 40
ASPECT_RATIO       ?= 1.0
CORE_MARGIN        ?= 2
PLACE_DENSITY      ?= 0.60
MAX_ROUTE_LAYER    ?= M7
CLK_UNCERTAINTY_PS ?= 0
PNR_STEP           ?= all
PNR_THREADS        ?= 0
PNR_REPAIR         ?= 1
LINK_BLACKBOXES    ?= 1
MACRO_DIRS         ?= none
FLOORPLAN          ?= none
MACRO_CHANNEL      ?= 10
MACRO_CHANNEL_Y    ?= $(MACRO_CHANNEL)
PDN                ?= none
PINS               ?= none
PIN_LAYERS_HOR     ?= M4
PIN_LAYERS_VER     ?= M5
PIN_ARGS           ?= none
IO_DELAY_PCT       ?= 0
SDC                ?= none
DROUTE_END_ITER    ?= -1
ODB                ?= design

PROJ_DIR := $(REPO_HOME)/projects/$(PROJECT)

export ASAP7_HOME := $(PDK_HOME)/vendor/asap7
export BEOL_HOME  := $(if $(filter asap7,$(BEOL)),$(ASAP7_HOME),$(PDK_HOME)/beol/$(BEOL))

export SEL_PROJECT            := $(PROJECT)
export SEL_TOP_LEVEL          := $(TOP_LEVEL)
export SEL_TB                 := $(TB)
export SEL_OUT_DIR            := $(OUT_DIR)
export SEL_NETLIST_DIR        := $(NETLIST_DIR)
export SEL_VCD_DIR            := $(VCD_DIR)
export SEL_CLK_PERIOD_NS      := $(CLK_PERIOD_NS)
export SEL_PARAMS             := $(PARAMS)
export SEL_KEEP_HIERARCHY     := $(KEEP_HIERARCHY)
export SEL_KEEP_MODULES       := $(KEEP_MODULES)
export SEL_BLACKBOX_MODULES   := $(BLACKBOX_MODULES)
export SEL_VCD                := $(VCD)
export SEL_CORE_UTIL          := $(CORE_UTIL)
export SEL_ASPECT_RATIO       := $(ASPECT_RATIO)
export SEL_CORE_MARGIN        := $(CORE_MARGIN)
export SEL_PLACE_DENSITY      := $(PLACE_DENSITY)
export SEL_MAX_ROUTE_LAYER    := $(MAX_ROUTE_LAYER)
export SEL_CLK_UNCERTAINTY_PS := $(CLK_UNCERTAINTY_PS)
export SEL_PNR_STEP           := $(PNR_STEP)
export SEL_PNR_THREADS        := $(PNR_THREADS)
export SEL_PNR_REPAIR         := $(PNR_REPAIR)
export SEL_LINK_BLACKBOXES    := $(LINK_BLACKBOXES)
export SEL_MACRO_DIRS         := $(MACRO_DIRS)
export SEL_FLOORPLAN          := $(FLOORPLAN)
export SEL_MACRO_CHANNEL      := $(MACRO_CHANNEL)
export SEL_MACRO_CHANNEL_Y    := $(MACRO_CHANNEL_Y)
export SEL_PDN                := $(PDN)
export SEL_PINS               := $(PINS)
export SEL_PIN_LAYERS_HOR     := $(PIN_LAYERS_HOR)
export SEL_PIN_LAYERS_VER     := $(PIN_LAYERS_VER)
export SEL_PIN_ARGS           := $(PIN_ARGS)
export SEL_IO_DELAY_PCT       := $(IO_DELAY_PCT)
export SEL_SDC                := $(SDC)
export SEL_DROUTE_END_ITER    := $(DROUTE_END_ITER)

.PHONY: init sim syn pnr post-syn-sta post-syn-sim post-syn-dpa post-pnr-sta post-pnr-sim post-pnr-dpa open-odb clean-all clean-sim clean-imp

init:
	mkdir -p $(PROJ_DIR)/sim
	mkdir -p $(PROJ_DIR)/imp

sim: clean-sim
	cd $(REPO_HOME)/scripts/sim && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/build && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/output && \
	./run.sh && \
	if [ -f $(REPO_HOME)/scripts/sim/activity.vcd ]; then \
	mv $(REPO_HOME)/scripts/sim/activity.vcd $(PROJ_DIR)/sim/$(OUT_DIR)/output; \
	fi

syn: clean-imp
	cd $(REPO_HOME)/scripts/syn && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	yosys -l $(PROJ_DIR)/imp/$(OUT_DIR)/output/yosys.log -c $(REPO_HOME)/scripts/syn/run.tcl

pnr: $(if $(filter all,$(PNR_STEP)),clean-imp)
	cd $(REPO_HOME)/scripts/pnr && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	./run.sh

post-syn-sta: clean-imp
	cd $(REPO_HOME)/scripts/post-syn-sta && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	sta -no_splash -exit $(REPO_HOME)/scripts/post-syn-sta/run.tcl | tee $(PROJ_DIR)/imp/$(OUT_DIR)/output/opensta.log

post-syn-sim: clean-sim
	cd $(REPO_HOME)/scripts/post-syn-sim && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/build && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/output && \
	./run.sh && \
	if [ -f $(REPO_HOME)/scripts/post-syn-sim/activity.vcd ]; then \
	mv $(REPO_HOME)/scripts/post-syn-sim/activity.vcd $(PROJ_DIR)/sim/$(OUT_DIR)/output; \
	fi

post-syn-dpa: clean-imp
	cd $(REPO_HOME)/scripts/post-syn-dpa && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	sta -no_splash -exit $(REPO_HOME)/scripts/post-syn-dpa/run.tcl | tee $(PROJ_DIR)/imp/$(OUT_DIR)/output/opensta.log

post-pnr-sta: clean-imp
	cd $(REPO_HOME)/scripts/post-pnr-sta && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	sta -no_splash -exit $(REPO_HOME)/scripts/post-pnr-sta/run.tcl | tee $(PROJ_DIR)/imp/$(OUT_DIR)/output/opensta.log

post-pnr-sim: clean-sim
	cd $(REPO_HOME)/scripts/post-pnr-sim && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/build && \
	mkdir -p $(PROJ_DIR)/sim/$(OUT_DIR)/output && \
	./run.sh && \
	if [ -f $(REPO_HOME)/scripts/post-pnr-sim/activity.vcd ]; then \
	mv $(REPO_HOME)/scripts/post-pnr-sim/activity.vcd $(PROJ_DIR)/sim/$(OUT_DIR)/output; \
	fi

post-pnr-dpa: clean-imp
	cd $(REPO_HOME)/scripts/post-pnr-dpa && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR) && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/report && \
	mkdir -p $(PROJ_DIR)/imp/$(OUT_DIR)/output && \
	sta -no_splash -exit $(REPO_HOME)/scripts/post-pnr-dpa/run.tcl | tee $(PROJ_DIR)/imp/$(OUT_DIR)/output/opensta.log

open-odb:
	@odb=$(PROJ_DIR)/imp/$(OUT_DIR)/output/$(ODB).odb; \
	if [ ! -f $$odb ]; then echo "open-odb: ODB not found: $$odb"; exit 1; fi; \
	tcl=$$(mktemp); \
	echo "read_db $$odb" > $$tcl; \
	openroad -gui $$tcl; \
	rm -f $$tcl

clean-all:
	rm -rf $(PROJ_DIR)/sim
	rm -rf $(PROJ_DIR)/imp

clean-sim:
	rm -rf $(PROJ_DIR)/sim/$(OUT_DIR)

clean-imp:
	rm -rf $(PROJ_DIR)/imp/$(OUT_DIR)
