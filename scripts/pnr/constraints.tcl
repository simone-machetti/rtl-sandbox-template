# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set CLK_PERIOD_PS [expr {$::env(SEL_CLK_PERIOD_NS) * 1000}]

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

if {$::env(SEL_CLK_UNCERTAINTY_PS) > 0} {
    set_clock_uncertainty $::env(SEL_CLK_UNCERTAINTY_PS) [all_clocks]
}
