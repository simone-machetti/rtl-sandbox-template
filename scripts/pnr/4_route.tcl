# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 3_cts
set_propagated_clock [all_clocks]

# -----------------------------------------------------------------------------
# Global routing
# -----------------------------------------------------------------------------
set_global_routing_layer_adjustment $MIN_ROUTE_LAYER-$MAX_ROUTE_LAYER 0.25
set_routing_layers \
    -signal $MIN_ROUTE_LAYER-$MAX_ROUTE_LAYER \
    -clock  $MIN_CLK_LAYER-$MAX_ROUTE_LAYER

global_route -congestion_iterations 30 -verbose

# -----------------------------------------------------------------------------
# Post-route timing repair
# -----------------------------------------------------------------------------
estimate_parasitics -global_routing
repair_timing -setup
repair_timing -hold
detailed_placement

global_route -congestion_iterations 30 -verbose

# -----------------------------------------------------------------------------
# Detailed routing
# -----------------------------------------------------------------------------
if {$::env(SEL_DROUTE_END_ITER) >= 0} {
    detailed_route \
        -output_drc $REPORT_DIR/route_drc.rpt \
        -droute_end_iter $::env(SEL_DROUTE_END_ITER) \
        -verbose 1
} else {
    detailed_route \
        -output_drc $REPORT_DIR/route_drc.rpt \
        -verbose 1
}

report_stage 4_route
save_checkpoint 4_route
