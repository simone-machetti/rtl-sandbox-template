# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# Pin plan for hardening `mac_n` as a hard macro of top_example: the A operands
# on the left edge, the B operands with the two sign controls on the top edge,
# the result on the right edge, every bus ordered by bit index, so the parent's
# input and output registers route to the block without crossing. Sourced by
# scripts/pnr/1_floorplan.tcl before place_pins (PINS=). Port names are the
# flat vectors of the synthesized netlist.
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
set_io_pin_constraint -pin_names [concat [bus_pins b_i 32] is_signed_b_i is_signed_a_i] -region top:*   -group -order
set_io_pin_constraint -pin_names [bus_pins out_o 19]                                    -region right:* -group -order
