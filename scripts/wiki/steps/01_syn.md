# Synthesis

Synthesis translates behavioral RTL into a netlist of standard cells from the target library — the single transformation that turns "description of behavior" into "list of physical gates". Everything after this step reasons about cells, not statements.

## Inputs and outputs

**Inputs**

- RTL files `.sv`
- Library of cells `.lib` (Liberty, five ASAP7 NLDM RVT groups of the `CORNER`: SEQ, SIMPLE, INVBUF, AO, OA; with `VT_SWAP=1` also the same groups in LVT and SLVT)
- Latch technology map `.v` (`$ASAP7_HOME/yoSys/cells_latch_R.v`)
- Previously synthesized netlists `imp/<mod>/output/netlist.v` (blackbox linking)
- Delay target for the ABC mapper, derived from `CLK_PERIOD_NS`, `SETUP_MARGIN_PCT` and `DERATE` (the resolved ABC script is archived as `output/abc.script`)
- With `VT_SWAP=1` only: physical views `.lef` (technology LEF and the R, L and SL cell LEFs), wire RC (`$BEOL_HOME/setRC.tcl`) and a project timing budget (`SDC`)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `OUT_DIR` (required); `CLK_PERIOD_NS`, `CORNER`, `SETUP_MARGIN_PCT`, `DERATE`, `PARAMS`, `KEEP_HIERARCHY`, `KEEP_MODULES`, `BLACKBOX_MODULES`, `LINK_BLACKBOXES`, `VT_SWAP`, `FANOUT_BUF`, `BUF_OUTPUTS`, `SWAP_TNS`, `SWAP_LAST_GASP`, `SWAP_REPAIRS`, `IO_DELAY_PCT`, `SDC` (optional)

**Outputs**

- Post-syn netlist `.v` (`output/netlist.v`; with `VT_SWAP=1` the swapped netlist, the Yosys one kept as `output/netlist_rvt.v`)
- Synthesis log (`output/yosys.log`; with `VT_SWAP=1` also `output/openroad.log`)
- Area report (`report/area.rpt`, of the Yosys netlist)
- Swap report (`report/vt_swap.rpt`, `VT_SWAP=1` only): cells, area, worst slack and cells per threshold voltage before buffering, after buffering, after each swap call and at the end

## Theory

A synthesis run is a fixed sequence of transformations:

1. **Elaboration** — parse the HDL, resolve parameters and generate loops, build the design hierarchy. The output is a netlist of *generic* operations (adders, muxes, registers), not yet gates.
2. **High-level optimization** — constant propagation, dead-code removal, FSM re-encoding, memory inference: technology-independent cleanups on the generic netlist.
3. **Technology mapping** — three distinct problems: sequential cells (map each generic flip-flop/latch onto a library cell with compatible reset/enable behavior), and combinational logic (cover the Boolean network with library gates optimizing delay/area). In Yosys these are `dfflibmap`, `techmap`-based latch mapping, and ABC respectively. **ABC** works on an AIG (and-inverter graph) representation: it structurally hashes, restructures, then *covers* the graph with library cells using the liberty delay model, followed by post-mapping sizing/buffering passes.
4. **Netlist emission** — flatten (or not), clean, and write structural Verilog.

Two cross-cutting concepts:

- **Hierarchy.** Flat netlists give the optimizer maximum freedom (boundaries block optimization) and are what placement wants; preserved hierarchy enables per-module area accounting and — in the extreme form, *blackboxing* — reuse of already-synthesized results. This flow supports four modes (below).
- **Timing-driven mapping.** ABC can map against a delay target. This flow passes the clock period as that target — although ABC's classic `map` command is delay-oriented by default, so the explicit target mainly documents intent (see Notes).
- **Threshold-voltage mixing.** The same cell exists with different threshold-voltage implants (RVT, LVT, SLVT in ASAP7), same footprint and area, faster and leakier at lower threshold. The classic use maps everything to the regular flavour and swaps only the cells of failing paths to a faster one, so leakage grows only where speed is needed. Synthesis offers it as an optional step after Yosys (`VT_SWAP=1`, below).

## Implementation walkthrough

### Elaboration — `scripts/syn/compile.tcl`

```tcl
yosys "design -reset"
yosys "plugin -i $env(YOSYS_SLANG_HOME)/bin/slang.so"
```

A clean database, then the **yosys-slang** plugin: a SystemVerilog frontend built on the slang parser, far more complete than Yosys's native reader — the reason modern SV (unpacked array ports, interfaces-free but rich SV) elaborates cleanly.

```tcl
proc lib_file {name} {
    set f $::env(ASAP7_HOME)/lib/NLDM/$name.lib
    if {[file exists $f]} { return $f }
    return $f.gz
}

proc vt_lib_files {vt} {
    set c $::env(SEL_CORNER)
    return [list \
        [lib_file asap7sc7p5t_SEQ_${vt}_${c}_nldm_220123] \
        [lib_file asap7sc7p5t_SIMPLE_${vt}_${c}_nldm_211120] \
        [lib_file asap7sc7p5t_INVBUF_${vt}_${c}_nldm_220122] \
        [lib_file asap7sc7p5t_AO_${vt}_${c}_nldm_211120] \
        [lib_file asap7sc7p5t_OA_${vt}_${c}_nldm_211120]]
}

set rvt_libs [vt_lib_files RVT]
set vt_libs {}
if {$env(SEL_VT_SWAP) ne "0"} {
    foreach vt {LVT SLVT} {
        set vt_libs [concat $vt_libs [vt_lib_files $vt]]
    }
}
foreach lib [concat $rvt_libs $vt_libs] {
    yosys "read_liberty -lib $lib"
}
```

The five groups of the selected corner (`CORNER`, TT by default), plain file when the kit has one, gzipped otherwise ([technology.md](../concepts/technology.md)). `-lib` loads the cells as *declarations* (interfaces without content) so that any pre-mapped cells in the input — e.g. a hand-instantiated clock gate — are recognized rather than re-elaborated. With `VT_SWAP=1` the LVT and SLVT cells are declared too (Yosys reads the gzipped files directly), so that a blackbox run can link component netlists that the swap step has changed, and count their area. Mapping itself never uses them: `dfflibmap` and ABC receive the RVT files only. `rvt_libs` and `vt_libs` stay defined for the mapping and the area report of `run.tcl`.

```tcl
set rtl_dir "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/rtl"
set rtl_files [lsort [split [exec find $rtl_dir -name "*.sv"] "\n"]]

set inc_flags ""
foreach dir [lsort [split [exec find $rtl_dir -type d] "\n"]] {
    append inc_flags " -I $dir"
}
```

All project RTL, all subdirectories as include paths — sorted for reproducibility.

```tcl
set g_flags ""
if {$env(SEL_PARAMS) ne "none"} {
    foreach param [regexp -all -inline {\S+} $env(SEL_PARAMS)] {
        append g_flags " -G $param"
    }
}

set kh_flag ""
if {$env(SEL_KEEP_HIERARCHY) eq "1" || $env(SEL_KEEP_MODULES) ne "none"} {
    set kh_flag " --keep-hierarchy"
}

set blackbox_modules {}
if {$env(SEL_BLACKBOX_MODULES) ne "none"} {
    set blackbox_modules [regexp -all -inline {\S+} $env(SEL_BLACKBOX_MODULES)]
}

set bb_flags ""
foreach mod $blackbox_modules {
    append bb_flags " --blackboxed-module $mod"
}

yosys "read_slang --single-unit [join $rtl_files]$inc_flags --extern-modules --top $env(SEL_TOP_LEVEL)$g_flags$kh_flag$bb_flags"
```

The single elaboration call: `-G` overrides top-level parameters; `--keep-hierarchy` preserves module boundaries when any hierarchy mode is requested; `--blackboxed-module` tells slang **not to elaborate** the listed modules — their instances stay as empty interface stubs. `--extern-modules` lets instantiated-but-undefined names (the liberty declarations) pass.

### Mapping and emission — `scripts/syn/run.tcl`

```tcl
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
```

Blackbox *linking*, part one. Each blackboxed module's previously synthesized netlist must exist (two-pass discipline: components first); `bb_netlist` looks for it in `imp/<mod>_syn/` and then in `imp/<mod>/` — and with `VT_SWAP=1` first in `imp/<mod>_vt_syn/`, the folder convention for swapped component runs, so a swapped grid and the plain one can be built side by side from the same components. The parameter dance strips residual parameters from the stub instances (a stub carries the RTL's parameter list; the synthesized netlist has none — they must match before binding). The netlist is then read as an interface (`-lib`) and the boundary is pinned with `keep_hierarchy` so nothing dissolves it.

```tcl
set keep_modules {}
if {$env(SEL_KEEP_MODULES) ne "none"} {
    set keep_modules [regexp -all -inline {\S+} $env(SEL_KEEP_MODULES)]
}
set partial_flatten [expr {[llength $keep_modules] > 0 || [llength $blackbox_modules] > 0}]

foreach mod $keep_modules {
    yosys "log KEEP_MODULES: preserving the boundary of module '$mod'"
    yosys "select -assert-any t:${mod}\$*"
    yosys "setattr -set keep_hierarchy 1 t:${mod}\$*"
}
yosys "select -clear"
```

`KEEP_MODULES` boundaries are marked the same way (the `t:${mod}$*` pattern matches slang's parameter-specialized module names). `partial_flatten` remembers that *some* hierarchy must survive.

```tcl
yosys "hierarchy -check -top $env(SEL_TOP_LEVEL)"
yosys "check"

yosys "proc"

if {$partial_flatten} {
    yosys "flatten"
    yosys "opt_clean"
}
```

`hierarchy` resolves and prunes the tree from the chosen top; `check` catches structural problems early. `proc` lowers behavioral processes into netlist primitives (muxes, registers). In hierarchy modes the flatten happens *now* — it respects `keep_hierarchy`, so it flattens everything *around and inside* the preserved boundaries but not through them.

```tcl
yosys "opt"
yosys "fsm"
yosys "opt"
yosys "memory"
yosys "opt"
yosys "techmap"
yosys "opt"
```

The generic optimization pipeline: iterative constant/dead-logic optimization interleaved with FSM extraction/re-encoding and memory inference, then `techmap` — lowering all remaining generic operators to Yosys's internal gate library (`$_AND_`, `$_DFF_*`, ...), the form the mappers consume.

```tcl
yosys "dfflibmap -liberty [lindex $rvt_libs 0]"
yosys "opt"

yosys "techmap -map $env(ASAP7_HOME)/yoSys/cells_latch_R.v"
yosys "opt"
```

Sequential mapping: `dfflibmap` matches every generic flip-flop against the SEQ liberty (choosing cells with the required reset/set behavior — e.g. the async-reset `DFFASRHQNx1_ASAP7_75t_R`); latches go through the platform's explicit techmap file (ASAP7's latch modeling needs the hand-written map).

```tcl
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
```

Combinational mapping. ABC's delay target is the clock period less the setup margin, divided by the derate — `CLK_PERIOD_NS` × (1 − `SETUP_MARGIN_PCT`/100) / `DERATE`, the period itself at the defaults: ABC knows neither clock uncertainty nor derate, so this is how it maps for the budget the swap step and STA check ([constraints](../concepts/constraints.md)). ABC also reads only uncompressed liberty, so the gzipped groups of the FF and SS corners are unpacked into the run folder for the call and deleted after it. The target reaches ABC by substituting the `{D}` placeholder in the script template — done by *this* script, because Yosys performs that substitution only for inline scripts, never inside `-script` files; the resolved script is archived with the run (`output/abc.script`) so every run records exactly what ABC executed. The template, `scripts/syn/abc.tcl`:

```tcl
strash
map {D} -B 0.9
topo
stime -c
buffer -c
upsize -c
dnsize -c
```

`strash` builds the AIG; `map` covers it with library cells (delay-oriented; `-D` sets the target, `-B 0.9` allows slight delay slack for area recovery); then topological ordering, static timing (`stime`), and the post-mapping physical-aware passes: `buffer` (fanout buffering), `upsize`/`dnsize` (drive-strength selection under the constraint context `-c`).

The script does no AIG rewriting between `strash` and `map`, so the adder trees that `techmap` builds keep their depth through the mapping.

```tcl
if {$env(SEL_LINK_BLACKBOXES) ne "0"} {
    foreach mod $blackbox_modules {
        yosys "read_verilog [bb_netlist $imp_dir $mod]"
    }
}
```

Blackbox linking, part two: the real gate-level content of each blackboxed module is read back in, replacing the stubs — the final netlist is self-contained. Unless `LINK_BLACKBOXES=0`: then the stubs stay empty, which is what a hierarchical P&R needs to bind them to hard macros by name ([18_hierarchical.md](../concepts/hierarchical.md)).

```tcl
set stat_libs ""
foreach lib [concat $rvt_libs $vt_libs] {
    append stat_libs " -liberty $lib"
}
yosys "tee -o $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report/area.rpt stat -hierarchy$stat_libs"
```

The area report: `stat -hierarchy` with liberty areas — one number for a flat run, per-module numbers in hierarchy modes (the basis for area accounting studies). With `VT_SWAP=1` the LVT and SLVT files join the list, so the swapped cells of linked components are counted; a component's own report describes the Yosys netlist, before the swap step (whose buffers appear in `report/vt_swap.rpt`).

```tcl
if {!$partial_flatten && $env(SEL_KEEP_HIERARCHY) eq "0"} {
    yosys "flatten"
    yosys "opt_clean"
    yosys "rename -hide"
}

yosys "write_verilog -noattr -noexpr -nodec $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/output/netlist.v"
```

Default runs flatten fully here (`rename -hide` replaces internal names with compact `_NNN_` identifiers). Emission flags produce the plainest possible structural Verilog: no attributes, no expressions (pure cell instances and wires), no decimal-constant sugar — maximally portable into OpenSTA/OpenROAD/Verilator.

### Threshold-voltage swap — `scripts/syn/vt_swap.tcl` (`VT_SWAP=1`)

An optional second tool after Yosys: OpenROAD's resizer takes the RVT netlist, buffers its high-fanout nets and swaps the cells of failing paths to LVT or SLVT, against the clock period and the project's timing budget. On a blackbox run (`BLACKBOX_MODULES`) it works on the logic around the linked components: these keep their netlists (swapped ones from `imp/<mod>_vt_syn/`), and the parent's own cells — registers, gates and the drivers of the nets between components, which ABC mapped without knowing their loads — are sized and swapped in context, against the real pin loads of the components.

```tcl
set CORNER $::env(SEL_CORNER)
foreach vt {RVT LVT SLVT} {
    read_liberty [lib_file asap7sc7p5t_SEQ_${vt}_${CORNER}_nldm_220123]
    read_liberty [lib_file asap7sc7p5t_SIMPLE_${vt}_${CORNER}_nldm_211120]
    read_liberty [lib_file asap7sc7p5t_INVBUF_${vt}_${CORNER}_nldm_220122]
    read_liberty [lib_file asap7sc7p5t_AO_${vt}_${CORNER}_nldm_211120]
    read_liberty [lib_file asap7sc7p5t_OA_${vt}_${CORNER}_nldm_211120]
}

read_lef $::env(BEOL_HOME)/lef/asap7_tech_1x_201209.lef
foreach vt {R L SL} {
    read_lef $::env(ASAP7_HOME)/lef/asap7sc7p5t_28_${vt}_1x_220121a.lef
}
```

Timing models of all three flavours at the selected corner (`lib_file` picks the plain `.lib` where it exists, the `.lib.gz` otherwise) and their physical views. The LEFs matter for more than geometry: the resizer tells the flavours apart by the implant layer each cell carries in its LEF (RVTN/RVTP, LVTN/LVTP, SLVTN/SLVTP), and refuses a swap on a cell without a LEF master.

```tcl
file rename -force $OUT_DIR/netlist.v $OUT_DIR/netlist_rvt.v
read_verilog $OUT_DIR/netlist_rvt.v
if {$::env(SEL_BLACKBOX_MODULES) eq "none"} {
    link_design $::env(SEL_TOP_LEVEL)
} else {
    link_design -hier $::env(SEL_TOP_LEVEL)
}
```

The Yosys netlist is kept as `netlist_rvt.v`; the swapped one takes its place as `netlist.v`, the name every downstream step reads. A blackbox run links hierarchically (`-hier`), so the written netlist keeps its modules and instance names for the downstream steps. OpenROAD gives every further instance of a module its own copy (`<module>_<instance>`); the copies of the linked components are merged back when the netlist is written (below).

```tcl
if {[llength $data_in] > 0} {
    set_input_delay $IO_DELAY_PS -clock vclk $data_in
    set_driving_cell -lib_cell BUFx2_ASAP7_75t_R -pin Y $data_in
}
...
set SETUP_MARGIN_PS [expr {$CLK_PERIOD_PS * $::env(SEL_SETUP_MARGIN_PCT) / 100.0}]
if {$SETUP_MARGIN_PS > 0} {
    set_clock_uncertainty -setup $SETUP_MARGIN_PS [all_clocks]
}
if {$::env(SEL_DERATE) != 1.0} {
    set_timing_derate -late $::env(SEL_DERATE)
}
...
source $::env(BEOL_HOME)/setRC.tcl
set_dont_use {SDF* ICG* HB*}
```

The constraint scheme of post-synthesis STA ([03_post_syn_sta.md](03_post_syn_sta.md)) — clock on `clk_i`, virtual clock, `IO_DELAY_PCT`, the setup margin and derate (`SETUP_MARGIN_PCT`, `DERATE`), then the project `SDC` — plus a driving cell on every data input: a component synthesized alone has ideal inputs, and only a real driver exposes the input nets whose fanout no single cell can carry. The wire RC is loaded because the resizer refuses to run without one; with the placement below it never sees a wire. The dont-use list is narrower than P&R's: fractional drives (`xp`, `x1p`) stay allowed, since the netlist uses them and a swap keeps the drive; a dont-use on such a cell would also bar its LVT and SLVT twins and leave it RVT on a path that is otherwise all SLVT. The hold buffers (`HB*`) are excluded, for the reason below.

```tcl
proc leaf_cells {} {
    return [get_cells -hierarchical -filter "is_hierarchical == 0" *]
}

if {$::env(SEL_BLACKBOX_MODULES) ne "none"} {
    set linked {}
    foreach c [get_cells -hierarchical -filter "is_hierarchical == 1" *] {
        set name [get_full_name $c]
        set ref  [string map {\\ {}} [get_property $c ref_name]]
        foreach m $::env(SEL_BLACKBOX_MODULES) {
            if {$ref eq $m || $ref eq "${m}_$name"} {
                dict set linked $name 1
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
```

The linked components stay as built. Every instance of a `BLACKBOX_MODULES` module (the copies included) is found by its module, and each cell inside it is marked dont-touch, so the resizer can still time through it but changes only the parent's own cells. `leaf_cells` is the cell list of every later loop: in a hierarchical design it skips the module instances, and in a flat one it is the plain cell list.

```tcl
foreach c [leaf_cells] {
    if {[string match HB* [get_property $c ref_name]]} {
        replace_cell $c BUFx2_ASAP7_75t_R
    }
}
```

ABC's `buffer` step builds its fanout trees from the smallest buffer of the library, and in ASAP7 that is a hold buffer: `HB1xp67`, a delay cell of about 50 ps that synthesis then chains by the hundred on high-fanout nets (an enable that masks a whole operand bus ends up behind a chain of nine). A threshold-voltage swap only trims such a chain. The step therefore maps every hold buffer onto `BUFx2` (same pins, about a third of the delay) before anything else, keeping the shape of ABC's trees.

```tcl
initialize_floorplan -utilization 30 -aspect_ratio 1.0 -core_space 2 -site asap7sc7p5t
...
foreach inst [$block getInsts] {
    $inst setLocation $cx $cy
    $inst setPlacementStatus PLACED
}
...
estimate_parasitics -placement
```

A single-point placement: a floorplan just large enough to exist, and every instance placed at its centre. The resizer only inserts buffers in a placed design, and with all cells on one point every wire has zero length — the netlist keeps the ideal-wire timing of this stage while the resizer can work.

```tcl
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
```

High-fanout buffering. `repair_design` fixes the liberty slew and capacitance limits, but only on nets driven by a cell: an input net, driven by a port, is left alone. Every input net with more than `FANOUT_BUF` loads therefore first gets one buffer at its root, and `repair_design` then builds the tree behind it. `BUF_OUTPUTS=1` adds one buffer per output port, for a block whose outputs feed a whole grid: Yosys merges outputs that carry the same function onto one driver, so a single small gate can end up driving several ports and, in the parent, hundreds of loads. A blackbox run skips this stage: in a hierarchical design the resizer cannot insert a buffer in front of the pins of a component it may not touch, so the parent's drivers are sized by the swap below instead, which needs no new cell.

```tcl
set moves vt_swap
if {$::env(SEL_BLACKBOX_MODULES) ne "none"} {
    set moves sizeup,vt_swap
}
set swap_args [list -setup -sequence $moves -repair_tns $::env(SEL_SWAP_TNS) \
    -max_repairs_per_pass $::env(SEL_SWAP_REPAIRS)]
if {$::env(SEL_SWAP_LAST_GASP) eq "0"} {
    lappend swap_args -skip_last_gasp
}
...
for {set pass 1} {$pass <= 20} {incr pass} {
    repair_timing {*}$swap_args
    set wns [sta::worst_slack -max]
    set tns [sta::total_negative_slack -max]
    ...
    if {$wns >= 0.0 || ($wns - $wns_prev < 1.0 && $tns - $tns_prev < -0.01 * $tns_prev)} { break }
    ...
}
```

The swap itself, restricted to threshold-voltage moves: no buffering, cloning or downsizing, so the cell count and the area stay those of the buffered netlist. A blackbox run adds upsizing (`sizeup`), the one way to give its drivers the strength their real loads need without new cells; it acts on the parent's cells only, the components being dont-touch. A call works pass by pass. Each pass takes the worst path of the register being repaired, ranks its cells by the part of their delay due to their load, replaces the first ones that can still go faster with their fastest flavour (SLVT in ASAP7; the move does not stop at LVT), re-times the design, and keeps the change only if the slack improved. The call first chases the worst register of the design, pass after pass, until its path has nothing left to switch; it then repairs `SWAP_TNS` percent of the other failing registers in the same way, and ends with a last-gasp round over them unless `SWAP_LAST_GASP=0`. `SWAP_REPAIRS` caps the cells switched per pass: the worst paths get the cap, the mildest one cell. The defaults (100 %, last gasp on, one cell per pass) repair every failing register. `SWAP_TNS=0 SWAP_LAST_GASP=0` with a large `SWAP_REPAIRS` works on the worst path only and switches it whole in a pass: once that path is all SLVT and still fails, no other swap can raise the frequency, so the step stops there, far sooner on a large block, and the paths better than the worst keep their flavours.

One call is not enough on a large block. The resizer gives up when the total negative slack falls by too small a fraction of its starting value per hundred moves, and with thousands of failing endpoints a single swap moves that total by very little: the call stops with most failing paths untouched. Each new call measures progress against the new, smaller total, so the step repeats the call — at most 20 times — until the worst slack is met, or until a call gains less than 1 ps of worst slack and less than 1 % of total negative slack. Each call is one line of the report.

```tcl
write_verilog $OUT_DIR/netlist.v

if {$::env(SEL_BLACKBOX_MODULES) ne "none"} {
    ...
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
            ...
        }
        puts $fout $line
    }
    ...
}
```

The swapped netlist, together with `report/vt_swap.rpt` (cells, area, worst slack and cells per flavour before buffering, after buffering, after each swap call and at the end). On a blackbox run the per-instance copies of a linked component are identical to it, since its cells are dont-touch, so the step drops their definitions and points their instances back at the component's own module (the `copies` map, filled while marking the components): the netlist keeps one module per component, as Yosys wrote it, instead of one per instance — which would multiply the netlist size and, above all, the compile time of a gate-level simulation. The same pass writes the constant ties back as constants: OpenROAD writes a pin tied to 0 or 1 as a connection to a net named `zero_` or `one_` that it never drives, and in a hierarchical netlist it prefixes that name with an instance path (`\<instance>/one_`), which the flat-netlist rewrite of the gate-level simulation ([02_post_syn_sim.md](02_post_syn_sim.md)) does not recognize; left as is, a two-state simulator drives such a pin to 0 (the set input of every glue register).

## Design space

- **Hierarchy modes** (the flow's four): flat (default — best optimization, what P&R wants), `KEEP_HIERARCHY=1` (all boundaries — per-module reporting), `KEEP_MODULES` (selected boundaries), `BLACKBOX_MODULES` (reuse of prior runs — constant per-component results, fast top-level runs; boundaries block cross-optimization, so timing across them is pessimistic and boundary nets go unbuffered). `LINK_BLACKBOXES=0` converts the last mode into macro-ready stubs.
- **Timing-driven strategy.** The `{D}` target with classic `map` is one point; ABC's modern `&nf`-based flows use the target more aggressively (and are the natural experiment if synthesis QoR ever becomes the bottleneck). Retiming (`abc -dff` style flows) would move registers across logic — a much deeper intervention.
- **Threshold-voltage mixing** (`VT_SWAP=1`): speed from the cell flavour, at equal area and cell count, paid in leakage. Mapping straight to a faster library (all-LVT or all-SLVT) would be the leakage-blind alternative; the swap keeps RVT wherever the timing allows. Per component, the result depends on the budget the project `SDC` gives each boundary.
- **Constants**: Yosys can map constants to tie cells itself (`hilomap`); this flow leaves them as `assign` statements and inserts tie cells in P&R instead ([06_pnr_floorplan.md](06_pnr_floorplan.md)) — either point is valid, exactly once.
- **Alternative frontends/tools**: Yosys's native SV reader (limited), or entirely different synthesis (commercial) feeding the same downstream flow — the netlist contract is the only interface.

## Knobs

| Knob               | Where | Default | Effect / tradeoff                                                                                                                                                  |
| ------------------ | ----- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CLK_PERIOD_NS`    | make  | 1.0     | ABC delay target (documenting intent; mapping is delay-oriented anyway); the swap step's clock                                                                     |
| `CORNER`           | make  | TT      | Liberty corner of the mapping, the area report and the swap step (TT, FF or SS)                                                                                    |
| `SETUP_MARGIN_PCT` | make  | 0       | Setup margin as a share of the period: ABC maps for period × (1 − margin) / derate, the swap step takes it as setup uncertainty                                    |
| `DERATE`           | make  | 1.0     | Late derate: divides ABC's delay target and stretches the swap step's cell and net delays                                                                          |
| `PARAMS`           | make  | none    | Design configuration at elaboration                                                                                                                                |
| `KEEP_HIERARCHY`   | make  | 0       | Full boundary preservation; reporting vs optimization freedom                                                                                                      |
| `KEEP_MODULES`     | make  | none    | Selective boundaries                                                                                                                                               |
| `BLACKBOX_MODULES` | make  | none    | Reuse of prior component runs; constant sub-results, faster top runs                                                                                               |
| `LINK_BLACKBOXES`  | make  | 1       | `0` = leave stubs empty for hierarchical P&R                                                                                                                       |
| `VT_SWAP`          | make  | 0       | `1` = buffer high-fanout nets and swap failing paths to LVT/SLVT after Yosys; blackbox runs link `imp/<mod>_vt_syn/` and size and swap only the parent's own cells |
| `FANOUT_BUF`       | make  | 16      | Input nets above this fanout get a root buffer before `repair_design` (`VT_SWAP=1`)                                                                                |
| `BUF_OUTPUTS`      | make  | 0       | `1` = one buffer per output port, for blocks whose outputs feed a whole grid (`VT_SWAP=1`)                                                                         |
| `SWAP_TNS`         | make  | 100     | Share (%) of the failing registers the swap repairs after the worst one; `0` = the worst path only (`VT_SWAP=1`)                                                   |
| `SWAP_LAST_GASP`   | make  | 1       | `0` = skip the last-gasp round over the failing registers (`VT_SWAP=1`)                                                                                            |
| `SWAP_REPAIRS`     | make  | 1       | Cells switched per pass on the worst paths; ↑ = fewer passes and faster runs, more SLVT cells (`VT_SWAP=1`)                                                        |
| `IO_DELAY_PCT`     | make  | 0       | Boundary delays of the swap step, as a share of the period (`VT_SWAP=1`)                                                                                           |
| `SDC`              | make  | none    | Project timing budget for the swap step, sourced after the generated constraints (`VT_SWAP=1`)                                                                     |

## Notes and caveats

- ABC treats flip-flop outputs as primary inputs of the combinational network and **does not buffer their fanout** — a synthesized netlist can carry huge-fanout register-driven nets with correspondingly bad pre-layout slews. This is a known property, repaired in P&R (`repair_design`), and the reason pre-layout STA of large flat/linked netlists must be read with care ([03_post_syn_sta.md](03_post_syn_sta.md)). `VT_SWAP=1` component runs buffer the input-driven high-fanout nets already in synthesis; the boundary nets between linked components then stay clean as long as each component buffers its own inputs, and a `VT_SWAP=1` blackbox run upsizes the parent's drivers of those nets against their real loads (it inserts no buffers there, so a net too heavy for the largest cell of its driver's function still needs a buffer at the component's input).
- The swap step's resizer has two traps on an unplaced netlist: `repair_design -pre_placement` buffers by gain on almost every net (thousands of buffers, worse timing) and ignores `-buffer_gain`, hence the single-point placement and plain `repair_design`; and `insert_buffer` crashes while generating names unless it receives explicit `-buffer_name`/`-net_name`.
- The swap cannot add cells or area, but it adds leakage (power analysis needs all three flavours loaded), and the post-synthesis simulation and power steps still load RVT models only.
- Yosys substitutes `{D}` only in inline ABC scripts; a literal `{D}` inside a `-script` file reaches ABC unexpanded and corrupts `map`'s option parsing — the reason this flow resolves the template itself and archives `output/abc.script`.
- Measured on this flow, explicit delay targets produce mapping identical to the default across a wide target range: classic `map` is already delay-oriented. Synthesis-side timing leverage is therefore limited; real timing QoR comes from P&R repair.
- Blackbox linking requires the component run to predate the top run — and a component RTL change requires re-running the component first (the error message encodes the discipline).
- The emitted netlist represents constants as `assign` statements; downstream tools handle this, and tie-cell insertion happens in the floorplan stage.

## Commercial perspective

The commercial equivalents (Design Compiler, Genus) integrate the same pipeline with full SDC awareness end-to-end: mapping, sizing and even placement-aware synthesis (physical synthesis) driven by the real constraint set, plus DFT insertion (scan chains) and UPF-driven power intent. The Yosys/ABC split — generic optimization vs AIG-based mapping — mirrors their internal architecture more closely than the tool names suggest.

Source: [run.tcl](../../syn/run.tcl) — [compile.tcl](../../syn/compile.tcl) — [abc.tcl](../../syn/abc.tcl) — [vt_swap.tcl](../../syn/vt_swap.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
