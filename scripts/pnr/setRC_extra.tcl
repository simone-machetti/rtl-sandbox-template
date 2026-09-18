# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# Pre-route wire RC estimates for the layers the platform's setRC.tcl does not
# cover. Sourced before it, so a stack whose own file covers these layers
# overrides these values. Used by estimate_parasitics during the
# placement- and guide-based timing repair whenever MAX_ROUTE_LAYER reaches
# these layers; extraction (OpenRCX) has its own per-layer rules.
#
# ASAP7 M8/M9 (80 nm pitch, 40 nm width, single-exposure 193i): extrapolated
# from the platform's M4-M7 trend, where the resistance scales with the inverse
# square of the width ratio (M4/M5 48 nm -> M6/M7 64 nm gave x0.56; 64 -> 80 nm
# gives x0.64) and the capacitance per length stays close to the M6/M7 values.
# V9 takes the V8 value. Estimates, not calibrated data; a platform that ships
# its own values for these layers should drop this file.
# -----------------------------------------------------------------------------

set_layer_rc -layer M8 -resistance 7.7E-03 -capacitance 1.40E-01
set_layer_rc -layer M9 -resistance 7.7E-03 -capacitance 1.40E-01
set_layer_rc -via V9 -resistance 6.30E-03
