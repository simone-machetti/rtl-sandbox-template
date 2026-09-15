# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# Macro floorplan for top_example in hierarchical mode: places the single
# hardened `mac_n` macro at the center of the core, leaving the surrounding
# ring for the input/output registers and the boundary pins. Sourced by
# scripts/pnr/1_floorplan.tcl (after the core exists and the macros are
# loaded), then followed by cut_rows.
#
# The macro size and the instance name are discovered from the design, so the
# file needs no edit when the macro is re-hardened at a different size or the
# instance is renamed. Pass it as FLOORPLAN=projects/example/scripts/floorplan_top_example.tcl.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Database handles
# -----------------------------------------------------------------------------
set block [ord::get_db_block]
set dbu   [expr {double([$block getDbUnitsPerMicron])}]

# -----------------------------------------------------------------------------
# Find the mac_n macro instance
# -----------------------------------------------------------------------------
set macros {}
foreach inst [$block getInsts] {
    if {[[$inst getMaster] getName] eq "mac_n"} {
        lappend macros $inst
    }
}
if {[llength $macros] != 1} {
    error "floorplan_top_example: expected exactly one `mac_n` macro, found [llength $macros] - is this a MACRO_DIRS run?"
}
set inst   [lindex $macros 0]
set master [$inst getMaster]
set mac_w  [expr {[$master getWidth]  / $dbu}]
set mac_h  [expr {[$master getHeight] / $dbu}]

# -----------------------------------------------------------------------------
# Center the macro in the core
# -----------------------------------------------------------------------------
set core   [$block getCoreArea]
set core_w [expr {([$core xMax] - [$core xMin]) / $dbu}]
set core_h [expr {([$core yMax] - [$core yMin]) / $dbu}]
set x      [expr {[$core xMin] / $dbu + ($core_w - $mac_w) / 2.0}]
set y      [expr {[$core yMin] / $dbu + ($core_h - $mac_h) / 2.0}]

if {$mac_w > $core_w || $mac_h > $core_h} {
    error "floorplan_top_example: the mac_n macro does not fit in the core - lower CORE_UTIL"
}

place_macro -macro_name [$inst getName] -location [list $x $y] -orientation R0
