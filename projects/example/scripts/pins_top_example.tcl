# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# Boundary pin plan for top_example, flat or assembled around the hardened
# `mac_n` macro: the same edges as the block (A operands left, B operands and
# sign controls top, result right) plus clock and reset on the top edge, every
# bus ordered by bit index, so the input and output registers sit between the
# boundary and the block they feed. Sourced by scripts/pnr/1_floorplan.tcl
# before place_pins (PINS=). Port names are the flat vectors of the synthesized
# netlist.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
proc bus_pins {name width} {
    set pins {}
    for {set i 0} {$i < $width} {incr i} {
        lappend pins "${name}\[$i\]"
    }
    return $pins
}

# -----------------------------------------------------------------------------
# Pin groups
# -----------------------------------------------------------------------------
set_io_pin_constraint -pin_names [bus_pins a_i 32]                                      -region left:*  -group -order
set_io_pin_constraint -pin_names {clk_i rst_ni}                                         -region top:*   -group -order
set_io_pin_constraint -pin_names [concat [bus_pins b_i 32] is_signed_b_i is_signed_a_i] -region top:*   -group -order
set_io_pin_constraint -pin_names [bus_pins out_o 19]                                    -region right:* -group -order
