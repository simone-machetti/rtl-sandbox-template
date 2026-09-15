# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# Power grid for a block hardened as a hard macro that will be assembled under a
# parent reserving the upper layers for over-macro routing. Rails on M1/M2 plus a
# single M5 mesh, exposed as M5 power pins; nothing is placed on M6/M7, so the
# hardened block obstructs only M1-M5 and leaves M6+M7 free for the parent to
# route over the macro. Pair with MAX_ROUTE_LAYER=M5 when hardening the block,
# and with pdn_macro.tcl (which drops the parent M6 straps onto these M5 pins) in
# the assembly. Mirrors the ASAP7 grid-strategy stripe geometry, topped at M5.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Global connections
# -----------------------------------------------------------------------------
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDCE$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSSE$}
global_connect

# -----------------------------------------------------------------------------
# Voltage domains
# -----------------------------------------------------------------------------
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

# -----------------------------------------------------------------------------
# Standard cell grid (M1/M2 rails, M5 mesh exposed as the block power pins)
# -----------------------------------------------------------------------------
define_pdn_grid -name {top} -voltage_domains {CORE} -pins {M5}
add_pdn_stripe -grid {top} -layer {M1} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M2} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M5} -width {0.12} -spacing {0.072} -pitch {5.4} -offset {0.300}
add_pdn_connect -grid {top} -layers {M1 M2}
add_pdn_connect -grid {top} -layers {M2 M5}
