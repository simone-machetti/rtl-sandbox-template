# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

# -----------------------------------------------------------------------------
# Technology (physical views)
# -----------------------------------------------------------------------------
read_lef $TECH_LEF
read_lef $SC_LEF

if {$::env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $::env(SEL_MACRO_DIRS) {
        read_lef $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$dir/output/abstract.lef
    }
}

# -----------------------------------------------------------------------------
# Netlist & top-level linking
# -----------------------------------------------------------------------------
read_verilog $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_NETLIST_DIR)/output/netlist.v
link_design $::env(SEL_TOP_LEVEL)

# -----------------------------------------------------------------------------
# Constraints & wire RC
# -----------------------------------------------------------------------------
source $::env(REPO_HOME)/scripts/pnr/constraints.tcl
source $::env(REPO_HOME)/scripts/pnr/setRC_extra.tcl
source $::env(BEOL_HOME)/setRC.tcl
set_dont_use $DONT_USE

# -----------------------------------------------------------------------------
# Floorplan & routing tracks
# -----------------------------------------------------------------------------
initialize_floorplan \
    -utilization  $::env(SEL_CORE_UTIL) \
    -aspect_ratio $::env(SEL_ASPECT_RATIO) \
    -core_space   $::env(SEL_CORE_MARGIN) \
    -site         $SITE

source $::env(BEOL_HOME)/openRoad/make_tracks.tcl

# -----------------------------------------------------------------------------
# Manual macro placement (project-owned floorplan file)
# -----------------------------------------------------------------------------
if {$::env(SEL_FLOORPLAN) ne "none"} {
    set fp_file $::env(SEL_FLOORPLAN)
    if {[file pathtype $fp_file] ne "absolute"} {
        set fp_file $::env(REPO_HOME)/$fp_file
    }
    source $fp_file
    cut_rows -halo_width_x 1 -halo_width_y 1
}

# -----------------------------------------------------------------------------
# Pin placement (provisional, refined after global placement)
# -----------------------------------------------------------------------------
set_pin_length -hor_length 0.24 -ver_length 0.24
if {$PINS_CFG ne "none"} {
    source $PINS_CFG
}
place_pins -hor_layers $PIN_LAYER_HOR -ver_layers $PIN_LAYER_VER {*}$PIN_ARGS

# -----------------------------------------------------------------------------
# Tie cells & tap cells
# -----------------------------------------------------------------------------
insert_tiecells $TIEHI_PORT -prefix "TIEHI_"
insert_tiecells $TIELO_PORT -prefix "TIELO_"

tapcell -distance 25 -tapcell_master $TAPCELL -endcap_master $TAPCELL

# -----------------------------------------------------------------------------
# Power distribution network
# -----------------------------------------------------------------------------
source $PDN_CFG
pdngen

report_stage 1_floorplan
save_checkpoint 1_floorplan
