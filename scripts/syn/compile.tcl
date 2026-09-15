# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Reset the design
# -----------------------------------------------------------------------------
yosys "design -reset"

# -----------------------------------------------------------------------------
# Import Yosys Slang plugin
# -----------------------------------------------------------------------------
yosys "plugin -i $env(YOSYS_SLANG_HOME)/bin/slang.so"

# -----------------------------------------------------------------------------
# Read libraries to Yosys database
# -----------------------------------------------------------------------------
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib"

# -----------------------------------------------------------------------------
# Read SystemVerilog sources
# -----------------------------------------------------------------------------
set rtl_dir "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/rtl"
set rtl_files [lsort [split [exec find $rtl_dir -name "*.sv"] "\n"]]

set inc_flags ""
foreach dir [lsort [split [exec find $rtl_dir -type d] "\n"]] {
    append inc_flags " -I $dir"
}

# -----------------------------------------------------------------------------
# RTL elaboration parameters
# -----------------------------------------------------------------------------
set g_flags ""
if {$env(SEL_PARAMS) ne "none"} {
    foreach param [regexp -all -inline {\S+} $env(SEL_PARAMS)] {
        append g_flags " -G $param"
    }
}

# -----------------------------------------------------------------------------
# Keep module boundaries (full or partial hierarchy)
# -----------------------------------------------------------------------------
set kh_flag ""
if {$env(SEL_KEEP_HIERARCHY) eq "1" || $env(SEL_KEEP_MODULES) ne "none"} {
    set kh_flag " --keep-hierarchy"
}

# -----------------------------------------------------------------------------
# Blackboxed modules (not elaborated, linked in run.tcl)
# -----------------------------------------------------------------------------
set blackbox_modules {}
if {$env(SEL_BLACKBOX_MODULES) ne "none"} {
    set blackbox_modules [regexp -all -inline {\S+} $env(SEL_BLACKBOX_MODULES)]
}

set bb_flags ""
foreach mod $blackbox_modules {
    append bb_flags " --blackboxed-module $mod"
}

# -----------------------------------------------------------------------------
# Elaborate design
# -----------------------------------------------------------------------------
yosys "read_slang --single-unit [join $rtl_files]$inc_flags --extern-modules --top $env(SEL_TOP_LEVEL)$g_flags$kh_flag$bb_flags"
