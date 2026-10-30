# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set REPORT_DIR $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report

# -----------------------------------------------------------------------------
# Libraries (timing/power models of the selected corner)
# -----------------------------------------------------------------------------
proc lib_file {name} {
    set f $::env(ASAP7_HOME)/lib/NLDM/$name.lib
    if {[file exists $f]} { return $f }
    return $f.gz
}

set CORNER $env(SEL_CORNER)
set vts {RVT}
if {$env(SEL_VT_SWAP) ne "0"} {
    lappend vts LVT SLVT
}
foreach vt $vts {
    read_liberty [lib_file asap7sc7p5t_SEQ_${vt}_${CORNER}_nldm_220123]
    read_liberty [lib_file asap7sc7p5t_SIMPLE_${vt}_${CORNER}_nldm_211120]
    read_liberty [lib_file asap7sc7p5t_INVBUF_${vt}_${CORNER}_nldm_220122]
    read_liberty [lib_file asap7sc7p5t_AO_${vt}_${CORNER}_nldm_211120]
    read_liberty [lib_file asap7sc7p5t_OA_${vt}_${CORNER}_nldm_211120]
}

# -----------------------------------------------------------------------------
# Netlist & top-level linking
# -----------------------------------------------------------------------------
read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design $env(SEL_TOP_LEVEL)

# -----------------------------------------------------------------------------
# Clock & I/O constraints
# -----------------------------------------------------------------------------
set CLK_PERIOD_PS [expr {$env(SEL_CLK_PERIOD_NS) * 1000}]
set IO_DELAY_PS   [expr {$CLK_PERIOD_PS * $env(SEL_IO_DELAY_PCT) / 100.0}]

if {[llength [get_ports -quiet clk_i]] > 0} {
    create_clock -name clk_i -period $CLK_PERIOD_PS [get_ports clk_i]
}
create_clock -name vclk -period $CLK_PERIOD_PS

set data_in {}
foreach port [all_inputs] {
    if {[lsearch -exact {clk_i rst_ni} [get_property $port full_name]] < 0} {
        lappend data_in $port
    }
}
if {[llength $data_in] > 0} {
    set_input_delay $IO_DELAY_PS -clock vclk $data_in
    set_false_path -hold -from $data_in
}
if {[llength [all_outputs]] > 0} {
    set_output_delay $IO_DELAY_PS -clock vclk [all_outputs]
    set_false_path -hold -to [all_outputs]
}

if {$env(SEL_SDC) ne "none"} {
    set sdc_file $env(SEL_SDC)
    if {[file pathtype $sdc_file] ne "absolute"} {
        set sdc_file $env(REPO_HOME)/$sdc_file
    }
    source $sdc_file
}

# -----------------------------------------------------------------------------
# VCD-based switching activity
# -----------------------------------------------------------------------------
set vcd_verilator "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/sim/$env(SEL_VCD_DIR)/output/activity.vcd"
read_vcd -scope $env(SEL_TB)/dut $vcd_verilator

report_activity_annotation -report_annotated   > $REPORT_DIR/vcd_annotated.rpt
report_activity_annotation -report_unannotated > $REPORT_DIR/vcd_unannotated.rpt

# -----------------------------------------------------------------------------
# Power reports
# -----------------------------------------------------------------------------
report_power > $REPORT_DIR/power_summary.rpt

if {$env(SEL_KEEP_HIERARCHY) eq "1" ||
    $env(SEL_KEEP_MODULES) ne "none" ||
    $env(SEL_BLACKBOX_MODULES) ne "none"} {
    report_power -instances [get_cells -hierarchical *] > $REPORT_DIR/power_hierarchy.rpt
}
