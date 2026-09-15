# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Elaborate design with Yosys Slang plugin
# -----------------------------------------------------------------------------
source $env(REPO_HOME)/scripts/syn/compile.tcl

# -----------------------------------------------------------------------------
# Link the pre-synthesized blackboxed modules
# -----------------------------------------------------------------------------
set imp_dir "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp"

# Resolve a blackboxed module's netlist: prefer imp/<mod>_syn/, fall back to imp/<mod>/
proc bb_netlist {imp_dir mod} {
    foreach dir [list ${mod}_syn $mod] {
        set f "$imp_dir/$dir/output/netlist.v"
        if {[file exists $f]} { return $f }
    }
    error "BLACKBOX_MODULES: netlist for '$mod' not found (looked in imp/${mod}_syn/ and imp/$mod/) - synthesize it first"
}

foreach mod $blackbox_modules {
    set netlist [bb_netlist $imp_dir $mod]

    set params_file "$imp_dir/$env(SEL_OUT_DIR)/output/${mod}_params.txt"
    yosys "dump -o $params_file t:$mod"
    set params {}
    set fh [open $params_file r]
    while {[gets $fh line] >= 0} {
        if {[regexp {^\s+parameter \\(\S+)} $line -> p] && [lsearch -exact $params $p] < 0} {
            lappend params $p
        }
    }
    close $fh
    file delete $params_file

    if {[llength $params] > 0} {
        set unset_args ""
        foreach p $params { append unset_args " -unset $p" }
        yosys "setparam$unset_args t:$mod"
    }

    yosys "log BLACKBOX_MODULES: linking $mod from $netlist"
    yosys "read_verilog -lib $netlist"
    yosys "setattr -set keep_hierarchy 1 t:$mod"
}

# -----------------------------------------------------------------------------
# Hierarchy boundaries to preserve
# -----------------------------------------------------------------------------
set keep_modules {}
if {$env(SEL_KEEP_MODULES) ne "none"} {
    set keep_modules [regexp -all -inline {\S+} $env(SEL_KEEP_MODULES)]
}
set partial_flatten [expr {[llength $keep_modules] > 0 || [llength $blackbox_modules] > 0}]

# -----------------------------------------------------------------------------
# Mark the boundaries
# -----------------------------------------------------------------------------
foreach mod $keep_modules {
    yosys "log KEEP_MODULES: preserving the boundary of module '$mod'"
    yosys "select -assert-any t:${mod}\$*"
    yosys "setattr -set keep_hierarchy 1 t:${mod}\$*"
}
yosys "select -clear"

# -----------------------------------------------------------------------------
# Elaboration / hierarchy
# -----------------------------------------------------------------------------
yosys "hierarchy -check -top $env(SEL_TOP_LEVEL)"
yosys "check"

# -----------------------------------------------------------------------------
# Synthesis & optimizations
# -----------------------------------------------------------------------------
yosys "proc"

# -----------------------------------------------------------------------------
# Flatten inside the preserved boundaries
# -----------------------------------------------------------------------------
if {$partial_flatten} {
    yosys "flatten"
    yosys "opt_clean"
}

# -----------------------------------------------------------------------------
# Coarse optimizations
# -----------------------------------------------------------------------------
yosys "opt"
yosys "fsm"
yosys "opt"
yosys "memory"
yosys "opt"
yosys "techmap"
yosys "opt"

# -----------------------------------------------------------------------------
# Technology mapping Flip-Flops
# -----------------------------------------------------------------------------
yosys "dfflibmap -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"
yosys "opt"

# -----------------------------------------------------------------------------
# Technology mapping Latches
# -----------------------------------------------------------------------------
yosys "techmap -map $env(ASAP7_HOME)/yoSys/cells_latch_R.v"
yosys "opt"

# -----------------------------------------------------------------------------
# Technology mapping Combinational Logic (delay target from CLK_PERIOD_NS)
# -----------------------------------------------------------------------------
set CLK_PERIOD_PS [expr {int($env(SEL_CLK_PERIOD_NS) * 1000)}]

set fh [open $env(REPO_HOME)/scripts/syn/abc.tcl r]
set abc_script [read $fh]
close $fh
set abc_script [string map [list "\{D\}" "-D $CLK_PERIOD_PS"] $abc_script]
set abc_file "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/output/abc.script"
set fh [open $abc_file w]
puts -nonewline $fh $abc_script
close $fh

yosys "abc \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib \
    -script  $abc_file"

yosys "opt"
yosys "clean"

# -----------------------------------------------------------------------------
# Swap blackbox stubs with their synthesized netlists
# -----------------------------------------------------------------------------
if {$env(SEL_LINK_BLACKBOXES) ne "0"} {
    foreach mod $blackbox_modules {
        yosys "read_verilog [bb_netlist $imp_dir $mod]"
    }
}

# -----------------------------------------------------------------------------
# Generate hierarchical area report
# -----------------------------------------------------------------------------
yosys "tee -o $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report/area.rpt stat -hierarchy \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib"

# -----------------------------------------------------------------------------
# Flatten full design, optimize and clean for netlist output
# -----------------------------------------------------------------------------
if {!$partial_flatten && $env(SEL_KEEP_HIERARCHY) eq "0"} {
    yosys "flatten"
    yosys "opt_clean"
    yosys "rename -hide"
}

# -----------------------------------------------------------------------------
# Write synthesized netlist
# -----------------------------------------------------------------------------
yosys "write_verilog -noattr -noexpr -nodec $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/output/netlist.v"
