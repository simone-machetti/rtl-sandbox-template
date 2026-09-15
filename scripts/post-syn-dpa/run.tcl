# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set REPORT_DIR $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report

# -----------------------------------------------------------------------------
# Libraries (timing/power models)
# -----------------------------------------------------------------------------
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

# -----------------------------------------------------------------------------
# Netlist & top-level linking
# -----------------------------------------------------------------------------
read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design $env(SEL_TOP_LEVEL)

# -----------------------------------------------------------------------------
# Clock & I/O constraints
# -----------------------------------------------------------------------------
set CLK_PERIOD_PS [expr {$env(SEL_CLK_PERIOD_NS) * 1000}]

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
    set_input_delay 0 -clock vclk $data_in
    set_false_path -hold -from $data_in
}
if {[llength [all_outputs]] > 0} {
    set_output_delay 0 -clock vclk [all_outputs]
    set_false_path -hold -to [all_outputs]
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
