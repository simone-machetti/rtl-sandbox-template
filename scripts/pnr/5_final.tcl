# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 4_route
set_propagated_clock [all_clocks]

# -----------------------------------------------------------------------------
# Filler cells
# -----------------------------------------------------------------------------
filler_placement $FILL_CELLS
global_connect
check_placement -verbose

# -----------------------------------------------------------------------------
# Parasitic extraction (OpenRCX)
# -----------------------------------------------------------------------------
define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file $::env(ASAP7_HOME)/rcx_patterns.rules
write_spef $OUT_DIR/netlist.spef
read_spef $OUT_DIR/netlist.spef

# -----------------------------------------------------------------------------
# Final reports
# -----------------------------------------------------------------------------
report_checks \
    -path_delay max \
    -fields {slew cap input_pins} \
    -digits 4 \
    -group_path_count 10 \
    > $REPORT_DIR/critical_paths.rpt
report_wns        > $REPORT_DIR/wns.rpt
report_tns        > $REPORT_DIR/tns.rpt
report_clock_skew > $REPORT_DIR/clock_skew.rpt
report_power      > $REPORT_DIR/power.rpt
report_design_area_file $REPORT_DIR/design_area.rpt

# -----------------------------------------------------------------------------
# Final products
# -----------------------------------------------------------------------------
write_def $OUT_DIR/design.def
write_sdc $OUT_DIR/design.sdc
write_verilog -remove_cells "$FILL_CELLS $TAPCELL" $OUT_DIR/netlist.v
write_abstract_lef $OUT_DIR/abstract.lef
write_timing_model $OUT_DIR/timing_model.lib
write_db $OUT_DIR/design.odb
