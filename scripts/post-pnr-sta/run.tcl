# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set REPORT_DIR $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report
file mkdir $REPORT_DIR

# -----------------------------------------------------------------------------
# Libraries (timing models of the selected corner)
# -----------------------------------------------------------------------------
proc lib_file {name} {
    set f $::env(ASAP7_HOME)/lib/NLDM/$name.lib
    if {[file exists $f]} { return $f }
    return $f.gz
}

set CORNER $env(SEL_CORNER)
read_liberty [lib_file asap7sc7p5t_SEQ_RVT_${CORNER}_nldm_220123]
read_liberty [lib_file asap7sc7p5t_SIMPLE_RVT_${CORNER}_nldm_211120]
read_liberty [lib_file asap7sc7p5t_INVBUF_RVT_${CORNER}_nldm_220122]
read_liberty [lib_file asap7sc7p5t_AO_RVT_${CORNER}_nldm_211120]
read_liberty [lib_file asap7sc7p5t_OA_RVT_${CORNER}_nldm_211120]

if {$env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $env(SEL_MACRO_DIRS) {
        read_liberty $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$dir/output/timing_model.lib
    }
}

# -----------------------------------------------------------------------------
# Netlist + top-level linking
# -----------------------------------------------------------------------------
read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design  $env(SEL_TOP_LEVEL)

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
# Post-route parasitics
# -----------------------------------------------------------------------------
read_spef $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.spef
set_propagated_clock [all_clocks]

# -----------------------------------------------------------------------------
# Reports generation
# -----------------------------------------------------------------------------
report_checks -unconstrained > $REPORT_DIR/unconstrained.rpt
report_checks \
    -path_delay max \
    -fields {slew cap input_pins} \
    -digits 4 \
    -group_path_count 10 \
    > $REPORT_DIR/critical_paths.rpt
report_wns > $REPORT_DIR/wns.rpt
report_tns > $REPORT_DIR/tns.rpt
