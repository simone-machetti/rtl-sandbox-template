# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 2_place

# -----------------------------------------------------------------------------
# Clock tree synthesis
# -----------------------------------------------------------------------------
if {[llength [get_ports -quiet clk_i]] > 0} {
    repair_clock_inverters
    if {$::env(SEL_MACRO_DIRS) ne "none"} {
        clock_tree_synthesis -repair_clock_nets
    } else {
        clock_tree_synthesis -sink_clustering_enable -repair_clock_nets
    }
    set_propagated_clock [all_clocks]
}

# -----------------------------------------------------------------------------
# Post-CTS timing repair; skipped in routability-only runs
# -----------------------------------------------------------------------------
if {$::env(SEL_PNR_REPAIR) ne "0"} {
    estimate_parasitics -placement
    repair_timing -setup
}

# -----------------------------------------------------------------------------
# Legalization
# -----------------------------------------------------------------------------
detailed_placement
check_placement -verbose

report_stage 3_cts
save_checkpoint 3_cts
