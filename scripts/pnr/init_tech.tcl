# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set OUT_DIR    $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_OUT_DIR)/output
set REPORT_DIR $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_OUT_DIR)/report

# -----------------------------------------------------------------------------
# Libraries (timing models)
# -----------------------------------------------------------------------------
source $::env(ASAP7_HOME)/liberty_suppressions.tcl

read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

if {$::env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $::env(SEL_MACRO_DIRS) {
        read_liberty $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$dir/output/timing_model.lib
    }
}

# -----------------------------------------------------------------------------
# Technology settings (ASAP7, RVT)
# -----------------------------------------------------------------------------
set TECH_LEF        $::env(BEOL_HOME)/lef/asap7_tech_1x_201209.lef
set SC_LEF          $::env(ASAP7_HOME)/lef/asap7sc7p5t_28_R_1x_220121a.lef
set SITE            asap7sc7p5t
set PIN_LAYER_HOR   $::env(SEL_PIN_LAYERS_HOR)
set PIN_LAYER_VER   $::env(SEL_PIN_LAYERS_VER)
set MIN_ROUTE_LAYER M2
set MAX_ROUTE_LAYER $::env(SEL_MAX_ROUTE_LAYER)
set MIN_CLK_LAYER   M4
set TAPCELL         TAPCELL_ASAP7_75t_R
set TIEHI_PORT      TIEHIx1_ASAP7_75t_R/H
set TIELO_PORT      TIELOx1_ASAP7_75t_R/L
set FILL_CELLS      {FILLERxp5_ASAP7_75t_R FILLER_ASAP7_75t_R DECAPx1_ASAP7_75t_R \
                     DECAPx2_ASAP7_75t_R DECAPx4_ASAP7_75t_R DECAPx6_ASAP7_75t_R \
                     DECAPx10_ASAP7_75t_R}
set DONT_USE        {*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}

if {$::env(SEL_PDN) ne "none"} {
    set PDN_CFG $::env(SEL_PDN)
    if {[file pathtype $PDN_CFG] ne "absolute"} {
        set PDN_CFG $::env(REPO_HOME)/$PDN_CFG
    }
} elseif {$::env(SEL_MACRO_DIRS) ne "none"} {
    set PDN_CFG $::env(REPO_HOME)/scripts/pnr/pdn_macro.tcl
} else {
    set PDN_CFG $::env(BEOL_HOME)/openRoad/pdn/grid_strategy-M1-M2-M5-M6.tcl
}

if {$::env(SEL_PINS) ne "none"} {
    set PINS_CFG $::env(SEL_PINS)
    if {[file pathtype $PINS_CFG] ne "absolute"} {
        set PINS_CFG $::env(REPO_HOME)/$PINS_CFG
    }
} else {
    set PINS_CFG none
}

if {$::env(SEL_PIN_ARGS) ne "none"} {
    set PIN_ARGS $::env(SEL_PIN_ARGS)
} else {
    set PIN_ARGS {}
}

if {$::env(SEL_PNR_THREADS) > 0} {
    set_thread_count $::env(SEL_PNR_THREADS)
} else {
    set_thread_count [exec nproc]
}
