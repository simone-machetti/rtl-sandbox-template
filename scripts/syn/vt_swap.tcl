# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

set OUT_DIR    $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_OUT_DIR)/output
set REPORT_DIR $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$::env(SEL_OUT_DIR)/report

# -----------------------------------------------------------------------------
# Libraries (timing models of the selected corner, three threshold voltages)
# -----------------------------------------------------------------------------
source $::env(ASAP7_HOME)/liberty_suppressions.tcl

proc lib_file {name} {
    set f $::env(ASAP7_HOME)/lib/NLDM/$name.lib
    if {[file exists $f]} { return $f }
    return $f.gz
}

set CORNER $::env(SEL_CORNER)
foreach vt {RVT LVT SLVT} {
    read_liberty [lib_file asap7sc7p5t_SEQ_${vt}_${CORNER}_nldm_220123]
    read_liberty [lib_file asap7sc7p5t_SIMPLE_${vt}_${CORNER}_nldm_211120]
    read_liberty [lib_file asap7sc7p5t_INVBUF_${vt}_${CORNER}_nldm_220122]
    read_liberty [lib_file asap7sc7p5t_AO_${vt}_${CORNER}_nldm_211120]
    read_liberty [lib_file asap7sc7p5t_OA_${vt}_${CORNER}_nldm_211120]
}

# -----------------------------------------------------------------------------
# Technology (physical views, three threshold voltages)
# -----------------------------------------------------------------------------
read_lef $::env(BEOL_HOME)/lef/asap7_tech_1x_201209.lef
foreach vt {R L SL} {
    read_lef $::env(ASAP7_HOME)/lef/asap7sc7p5t_28_${vt}_1x_220121a.lef
}

# -----------------------------------------------------------------------------
# Netlist & top-level linking
# -----------------------------------------------------------------------------
file rename -force $OUT_DIR/netlist.v $OUT_DIR/netlist_rvt.v
read_verilog $OUT_DIR/netlist_rvt.v
if {$::env(SEL_BLACKBOX_MODULES) eq "none"} {
    link_design $::env(SEL_TOP_LEVEL)
} else {
    link_design -hier $::env(SEL_TOP_LEVEL)
}

# -----------------------------------------------------------------------------
# Constraints & wire RC
# -----------------------------------------------------------------------------
set CLK_PERIOD_PS [expr {$::env(SEL_CLK_PERIOD_NS) * 1000}]
set IO_DELAY_PS   [expr {$CLK_PERIOD_PS * $::env(SEL_IO_DELAY_PCT) / 100.0}]

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
    set_driving_cell -lib_cell BUFx2_ASAP7_75t_R -pin Y $data_in
}
if {[llength [all_outputs]] > 0} {
    set_output_delay $IO_DELAY_PS -clock vclk [all_outputs]
}

set SETUP_MARGIN_PS [expr {$CLK_PERIOD_PS * $::env(SEL_SETUP_MARGIN_PCT) / 100.0}]
if {$SETUP_MARGIN_PS > 0} {
    set_clock_uncertainty -setup $SETUP_MARGIN_PS [all_clocks]
}
if {$::env(SEL_DERATE) != 1.0} {
    set_timing_derate -late $::env(SEL_DERATE)
}

if {$::env(SEL_SDC) ne "none"} {
    set sdc_file $::env(SEL_SDC)
    if {[file pathtype $sdc_file] ne "absolute"} {
        set sdc_file $::env(REPO_HOME)/$sdc_file
    }
    source $sdc_file
}

source $::env(BEOL_HOME)/setRC.tcl
set_dont_use {SDF* ICG* HB*}

# -----------------------------------------------------------------------------
# Linked components (kept as built, only the surrounding logic is optimized)
# -----------------------------------------------------------------------------
proc leaf_cells {} {
    return [get_cells -hierarchical -filter "is_hierarchical == 0" *]
}

set copies {}
if {$::env(SEL_BLACKBOX_MODULES) ne "none"} {
    set linked {}
    foreach c [get_cells -hierarchical -filter "is_hierarchical == 1" *] {
        set name [get_full_name $c]
        set ref  [string map {\\ {}} [get_property $c ref_name]]
        foreach m $::env(SEL_BLACKBOX_MODULES) {
            if {$ref eq $m || $ref eq "${m}_$name"} {
                dict set linked $name 1
            }
            if {$ref eq "${m}_$name"} {
                dict set copies $ref $m
            }
        }
    }
    set fixed {}
    foreach c [leaf_cells] {
        if {[dict exists $linked [lindex [split [get_full_name $c] /] 0]]} {
            lappend fixed $c
        }
    }
    set_dont_touch $fixed
}

# -----------------------------------------------------------------------------
# Hold buffers to plain buffers
# -----------------------------------------------------------------------------
foreach c [leaf_cells] {
    if {[string match HB* [get_property $c ref_name]]} {
        replace_cell $c BUFx2_ASAP7_75t_R
    }
}

# -----------------------------------------------------------------------------
# Single-point placement (zero-length wires)
# -----------------------------------------------------------------------------
initialize_floorplan -utilization 30 -aspect_ratio 1.0 -core_space 2 -site asap7sc7p5t

set block [ord::get_db_block]
set core  [$block getCoreArea]
set cx    [expr {([$core xMin] + [$core xMax]) / 2}]
set cy    [expr {([$core yMin] + [$core yMax]) / 2}]

foreach inst [$block getInsts] {
    $inst setLocation $cx $cy
    $inst setPlacementStatus PLACED
}
foreach bterm [$block getBTerms] {
    foreach bpin [$bterm getBPins] {
        $bpin setPlacementStatus PLACED
    }
}
estimate_parasitics -placement

# -----------------------------------------------------------------------------
# Reporting helpers
# -----------------------------------------------------------------------------
proc vt_mix {} {
    set n(R) 0
    set n(L) 0
    set n(SL) 0
    foreach c [leaf_cells] {
        if {[regexp {_ASAP7_75t_(R|L|SL)$} [get_property $c ref_name] -> vt]} {
            incr n($vt)
        }
    }
    return [format "RVT %d  LVT %d  SLVT %d" $n(R) $n(L) $n(SL)]
}

proc cell_area {} {
    set total 0.0
    foreach c [leaf_cells] {
        set total [expr {$total + [get_property [get_lib_cells -of_objects $c] area]}]
    }
    return [format "%.6f" $total]
}

set rpt [open $REPORT_DIR/vt_swap.rpt w]
puts $rpt [format "%-20s cells %d  area %s  wns %.1f  %s" before \
    [llength [leaf_cells]] [cell_area] [sta::worst_slack -max] [vt_mix]]

# -----------------------------------------------------------------------------
# High-fanout buffering (runs without linked components)
# -----------------------------------------------------------------------------
set n_buf 0
if {$::env(SEL_BLACKBOX_MODULES) eq "none"} {
    if {$::env(SEL_BUF_OUTPUTS) ne "0"} {
        buffer_ports -outputs -buffer_cell BUFx2_ASAP7_75t_R
    }

    foreach port $data_in {
        set net [get_nets -quiet [get_full_name $port]]
        if {[llength $net] == 0} { continue }
        if {[llength [get_pins -quiet -of_objects $net -filter "direction==input"]] > $::env(SEL_FANOUT_BUF)} {
            insert_buffer -buffer_cell BUFx4_ASAP7_75t_R -net [get_full_name $net] \
                -buffer_name fanout_buf_$n_buf -net_name fanout_net_$n_buf \
                -location [list [ord::dbu_to_microns $cx] [ord::dbu_to_microns $cy]]
            incr n_buf
        }
    }

    repair_design
}

puts $rpt [format "%-20s cells %d  area %s  wns %.1f  %s  (input nets buffered: %d)" buffered \
    [llength [leaf_cells]] [cell_area] [sta::worst_slack -max] [vt_mix] $n_buf]

# -----------------------------------------------------------------------------
# Threshold-voltage swap (with upsizing around linked components)
# -----------------------------------------------------------------------------
set moves vt_swap
if {$::env(SEL_BLACKBOX_MODULES) ne "none"} {
    set moves sizeup,vt_swap
}
set swap_args [list -setup -sequence $moves -repair_tns $::env(SEL_SWAP_TNS) \
    -max_repairs_per_pass $::env(SEL_SWAP_REPAIRS)]
if {$::env(SEL_SWAP_LAST_GASP) eq "0"} {
    lappend swap_args -skip_last_gasp
}

set wns_prev [sta::worst_slack -max]
set tns_prev [sta::total_negative_slack -max]
for {set pass 1} {$pass <= 20} {incr pass} {
    repair_timing {*}$swap_args
    set wns [sta::worst_slack -max]
    set tns [sta::total_negative_slack -max]
    puts $rpt [format "%-20s cells %d  area %s  wns %.1f  tns %.1f  %s" "swap pass $pass" \
        [llength [leaf_cells]] [cell_area] $wns $tns [vt_mix]]
    flush $rpt
    if {$wns >= 0.0 || ($wns - $wns_prev < 1.0 && $tns - $tns_prev < -0.01 * $tns_prev)} { break }
    set wns_prev $wns
    set tns_prev $tns
}

puts $rpt [format "%-20s cells %d  area %s  wns %.1f  %s" swapped \
    [llength [leaf_cells]] [cell_area] [sta::worst_slack -max] [vt_mix]]
close $rpt

# -----------------------------------------------------------------------------
# Write netlist (one module per linked component)
# -----------------------------------------------------------------------------
write_verilog $OUT_DIR/netlist.v

proc first_token {text} {
    set text [string trimleft $text]
    set end  [string first " " $text]
    return [string range $text 0 [expr {$end < 0 ? "end" : $end - 1}]]
}

if {$::env(SEL_BLACKBOX_MODULES) ne "none"} {
    set fin  [open $OUT_DIR/netlist.v r]
    set fout [open $OUT_DIR/netlist_merged.v w]
    set skip 0
    while {[gets $fin line] >= 0} {
        if {$skip} {
            if {[string match "endmodule*" $line]} { set skip 0 }
            continue
        }
        if {[string first "/one_ " $line] >= 0 || [string first "/zero_ " $line] >= 0} {
            regsub -all {\\\S*/one_ } $line {1'b1 } line
            regsub -all {\\\S*/zero_ } $line {1'b0 } line
        }
        if {[string match "module *" $line]} {
            set tok [first_token [string range $line 7 end]]
            if {[dict exists $copies [string range $tok 1 end]]} {
                set skip 1
                continue
            }
        } elseif {[string match " *" $line]} {
            set tok [first_token $line]
            if {[string index $tok 0] eq "\\" && [dict exists $copies [string range $tok 1 end]]} {
                set at   [string first $tok $line]
                set line "[string range $line 0 [expr {$at - 1}]][dict get $copies [string range $tok 1 end]][string range $line [expr {$at + [string length $tok]}] end]"
            }
        }
        puts $fout $line
    }
    close $fin
    close $fout
    file rename -force $OUT_DIR/netlist_merged.v $OUT_DIR/netlist.v
}
