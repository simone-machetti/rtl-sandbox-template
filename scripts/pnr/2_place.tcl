# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 1_floorplan

# -----------------------------------------------------------------------------
# Netlist cleanup
# -----------------------------------------------------------------------------
remove_buffers
repair_tie_fanout -separation 0 $TIEHI_PORT
repair_tie_fanout -separation 0 $TIELO_PORT

# -----------------------------------------------------------------------------
# Global placement & final pin placement
# -----------------------------------------------------------------------------
global_placement \
    -density $::env(SEL_PLACE_DENSITY) \
    -routability_driven \
    -timing_driven

set_pin_length -hor_length 0.24 -ver_length 0.24
place_pins -hor_layers $PIN_LAYER_HOR -ver_layers $PIN_LAYER_VER {*}$PIN_ARGS

# -----------------------------------------------------------------------------
# Design repair (buffering & sizing); skipped in routability-only runs
# -----------------------------------------------------------------------------
if {$::env(SEL_PNR_REPAIR) ne "0"} {
    estimate_parasitics -placement
    repair_design
}

# -----------------------------------------------------------------------------
# Detailed placement
# -----------------------------------------------------------------------------
detailed_placement
optimize_mirroring
check_placement -verbose

report_stage 2_place
save_checkpoint 2_place
