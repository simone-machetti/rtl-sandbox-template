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

proc bb_netlist {imp_dir mod} {
    set dirs [list ${mod}_syn $mod]
    if {$::env(SEL_VT_SWAP) ne "0"} {
        set dirs [linsert $dirs 0 ${mod}_vt_syn]
    }
    foreach dir $dirs {
        set f "$imp_dir/$dir/output/netlist.v"
        if {[file exists $f]} { return $f }
    }
    error "BLACKBOX_MODULES: netlist for '$mod' not found (looked in imp/[join $dirs {/, imp/}]/) - synthesize it first"
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
yosys "dfflibmap -liberty [lindex $rvt_libs 0]"
yosys "opt"

# -----------------------------------------------------------------------------
# Technology mapping Latches
# -----------------------------------------------------------------------------
yosys "techmap -map $env(ASAP7_HOME)/yoSys/cells_latch_R.v"
yosys "opt"

# -----------------------------------------------------------------------------
# Technology mapping Combinational Logic
# -----------------------------------------------------------------------------
set CLK_PERIOD_PS [expr {int($env(SEL_CLK_PERIOD_NS) * 1000)}]
set ABC_DELAY_PS  [expr {int($CLK_PERIOD_PS * (100 - $env(SEL_SETUP_MARGIN_PCT)) / 100.0 / $env(SEL_DERATE))}]
set out_dir       "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/output"

set fh [open $env(REPO_HOME)/scripts/syn/abc.tcl r]
set abc_script [read $fh]
close $fh
set abc_script [string map [list "\{D\}" "-D $ABC_DELAY_PS"] $abc_script]
set abc_file "$out_dir/abc.script"
set fh [open $abc_file w]
puts -nonewline $fh $abc_script
close $fh

set abc_libs ""
set unpacked {}
foreach lib [lrange $rvt_libs 1 end] {
    if {[file extension $lib] eq ".gz"} {
        set plain $out_dir/[file rootname [file tail $lib]]
        exec gzip -dc $lib > $plain
        lappend unpacked $plain
        set lib $plain
    }
    append abc_libs " -liberty $lib"
}

yosys "abc$abc_libs -script $abc_file"

foreach f $unpacked {
    file delete $f
}

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
set stat_libs ""
foreach lib [concat $rvt_libs $vt_libs] {
    append stat_libs " -liberty $lib"
}
yosys "tee -o $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report/area.rpt stat -hierarchy$stat_libs"

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
