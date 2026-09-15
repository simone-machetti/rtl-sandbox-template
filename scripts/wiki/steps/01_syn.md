# Synthesis

Synthesis translates behavioral RTL into a netlist of standard cells from the target library — the single transformation that turns "description of behavior" into "list of physical gates". Everything after this step reasons about cells, not statements.

## Inputs and outputs

**Inputs**

- RTL files `.sv`
- Library of cells `.lib` (Liberty, five ASAP7 NLDM RVT TT groups: SEQ, SIMPLE, INVBUF, AO, OA)
- Latch technology map `.v` (`$ASAP7_HOME/yoSys/cells_latch_R.v`)
- Previously synthesized netlists `imp/<mod>/output/netlist.v` (blackbox linking)
- Delay target for the ABC mapper, derived from `CLK_PERIOD_NS` (the resolved ABC script is archived as `output/abc.script`)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `OUT_DIR` (required); `CLK_PERIOD_NS`, `PARAMS`, `KEEP_HIERARCHY`, `KEEP_MODULES`, `BLACKBOX_MODULES`, `LINK_BLACKBOXES` (optional)

**Outputs**

- Post-syn netlist `.v` (`output/netlist.v`)
- Synthesis log (`output/yosys.log`)
- Area report (`report/area.rpt`)

## Theory

A synthesis run is a fixed sequence of transformations:

1. **Elaboration** — parse the HDL, resolve parameters and generate loops, build the design hierarchy. The output is a netlist of *generic* operations (adders, muxes, registers), not yet gates.
2. **High-level optimization** — constant propagation, dead-code removal, FSM re-encoding, memory inference: technology-independent cleanups on the generic netlist.
3. **Technology mapping** — three distinct problems: sequential cells (map each generic flip-flop/latch onto a library cell with compatible reset/enable behavior), and combinational logic (cover the Boolean network with library gates optimizing delay/area). In Yosys these are `dfflibmap`, `techmap`-based latch mapping, and ABC respectively. **ABC** works on an AIG (and-inverter graph) representation: it structurally hashes, restructures, then *covers* the graph with library cells using the liberty delay model, followed by post-mapping sizing/buffering passes.
4. **Netlist emission** — flatten (or not), clean, and write structural Verilog.

Two cross-cutting concepts:

- **Hierarchy.** Flat netlists give the optimizer maximum freedom (boundaries block optimization) and are what placement wants; preserved hierarchy enables per-module area accounting and — in the extreme form, *blackboxing* — reuse of already-synthesized results. This flow supports four modes (below).
- **Timing-driven mapping.** ABC can map against a delay target. This flow passes the clock period as that target — although ABC's classic `map` command is delay-oriented by default, so the explicit target mainly documents intent (see Notes).

## Implementation walkthrough

### Elaboration — `scripts/syn/compile.tcl`

```tcl
yosys "design -reset"
yosys "plugin -i $env(YOSYS_SLANG_HOME)/bin/slang.so"
```

A clean database, then the **yosys-slang** plugin: a SystemVerilog frontend built on the slang parser, far more complete than Yosys's native reader — the reason modern SV (unpacked array ports, interfaces-free but rich SV) elaborates cleanly.

```tcl
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib"
```

`-lib` loads the cells as *declarations* (interfaces without content) so that any pre-mapped cells in the input — e.g. a hand-instantiated clock gate — are recognized rather than re-elaborated.

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

foreach mod $blackbox_modules {
    set netlist "$imp_dir/$mod/output/netlist.v"
    if {![file exists $netlist]} {
        error "BLACKBOX_MODULES: $netlist not found - run 'make syn PROJECT=$env(SEL_PROJECT) TOP_LEVEL=$mod OUT_DIR=$mod' first"
    }

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

Blackbox *linking*, part one. Each blackboxed module's previously synthesized netlist must exist (two-pass discipline: components first). The parameter dance strips residual parameters from the stub instances (a stub carries the RTL's parameter list; the synthesized netlist has none — they must match before binding). The netlist is then read as an interface (`-lib`) and the boundary is pinned with `keep_hierarchy` so nothing dissolves it.

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
yosys "dfflibmap -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"
yosys "opt"

yosys "techmap -map $env(ASAP7_HOME)/yoSys/cells_latch_R.v"
yosys "opt"
```

Sequential mapping: `dfflibmap` matches every generic flip-flop against the SEQ liberty (choosing cells with the required reset/set behavior — e.g. the async-reset `DFFASRHQNx1_ASAP7_75t_R`); latches go through the platform's explicit techmap file (ASAP7's latch modeling needs the hand-written map).

```tcl
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
```

Combinational mapping. The clock period becomes ABC's delay target by substituting the `{D}` placeholder in the script template — done by *this* script, because Yosys performs that substitution only for inline scripts, never inside `-script` files; the resolved script is archived with the run (`output/abc.script`) so every run records exactly what ABC executed. The template, `scripts/syn/abc.tcl`:

```tcl
strash
dc2
map {D} -B 0.9
topo
stime -c
buffer -c
upsize -c
dnsize -c
```

`strash` builds the AIG; `dc2` restructures it (don't-care-based optimization); `map` covers it with library cells (delay-oriented; `-D` sets the target, `-B 0.9` allows slight delay slack for area recovery); then topological ordering, static timing (`stime`), and the post-mapping physical-aware passes: `buffer` (fanout buffering), `upsize`/`dnsize` (drive-strength selection under the constraint context `-c`).

```tcl
if {$env(SEL_LINK_BLACKBOXES) ne "0"} {
    foreach mod $blackbox_modules {
        yosys "read_verilog $imp_dir/$mod/output/netlist.v"
    }
}
```

Blackbox linking, part two: the real gate-level content of each blackboxed module is read back in, replacing the stubs — the final netlist is self-contained. Unless `LINK_BLACKBOXES=0`: then the stubs stay empty, which is what a hierarchical P&R needs to bind them to hard macros by name ([18_hierarchical.md](../concepts/hierarchical.md)).

```tcl
yosys "tee -o $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report/area.rpt stat -hierarchy \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib \
    -liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib"
```

The area report: `stat -hierarchy` with liberty areas — one number for a flat run, per-module numbers in hierarchy modes (the basis for area accounting studies).

```tcl
if {!$partial_flatten && $env(SEL_KEEP_HIERARCHY) eq "0"} {
    yosys "flatten"
    yosys "opt_clean"
    yosys "rename -hide"
}

yosys "write_verilog -noattr -noexpr -nodec $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/output/netlist.v"
```

Default runs flatten fully here (`rename -hide` replaces internal names with compact `_NNN_` identifiers). Emission flags produce the plainest possible structural Verilog: no attributes, no expressions (pure cell instances and wires), no decimal-constant sugar — maximally portable into OpenSTA/OpenROAD/Verilator.

## Design space

- **Hierarchy modes** (the flow's four): flat (default — best optimization, what P&R wants), `KEEP_HIERARCHY=1` (all boundaries — per-module reporting), `KEEP_MODULES` (selected boundaries), `BLACKBOX_MODULES` (reuse of prior runs — constant per-component results, fast top-level runs; boundaries block cross-optimization, so timing across them is pessimistic and boundary nets go unbuffered). `LINK_BLACKBOXES=0` converts the last mode into macro-ready stubs.
- **Timing-driven strategy.** The `{D}` target with classic `map` is one point; ABC's modern `&nf`-based flows use the target more aggressively (and are the natural experiment if synthesis QoR ever becomes the bottleneck). Retiming (`abc -dff` style flows) would move registers across logic — a much deeper intervention.
- **Constants**: Yosys can map constants to tie cells itself (`hilomap`); this flow leaves them as `assign` statements and inserts tie cells in P&R instead ([06_pnr_floorplan.md](06_pnr_floorplan.md)) — either point is valid, exactly once.
- **Alternative frontends/tools**: Yosys's native SV reader (limited), or entirely different synthesis (commercial) feeding the same downstream flow — the netlist contract is the only interface.

## Knobs

| Knob               | Where | Default | Effect / tradeoff                                                       |
| ------------------ | ----- | ------- | ----------------------------------------------------------------------- |
| `CLK_PERIOD_NS`    | make  | 1.0     | ABC delay target (documenting intent; mapping is delay-oriented anyway) |
| `PARAMS`           | make  | none    | Design configuration at elaboration                                     |
| `KEEP_HIERARCHY`   | make  | 0       | Full boundary preservation; reporting vs optimization freedom           |
| `KEEP_MODULES`     | make  | none    | Selective boundaries                                                    |
| `BLACKBOX_MODULES` | make  | none    | Reuse of prior component runs; constant sub-results, faster top runs    |
| `LINK_BLACKBOXES`  | make  | 1       | `0` = leave stubs empty for hierarchical P&R                            |

## Notes and caveats

- ABC treats flip-flop outputs as primary inputs of the combinational network and **does not buffer their fanout** — a synthesized netlist can carry huge-fanout register-driven nets with correspondingly bad pre-layout slews. This is a known property, repaired in P&R (`repair_design`), and the reason pre-layout STA of large flat/linked netlists must be read with care ([03_post_syn_sta.md](03_post_syn_sta.md)).
- Yosys substitutes `{D}` only in inline ABC scripts; a literal `{D}` inside a `-script` file reaches ABC unexpanded and corrupts `map`'s option parsing — the reason this flow resolves the template itself and archives `output/abc.script`.
- Measured on this flow, explicit delay targets produce mapping identical to the default across a wide target range: classic `map` is already delay-oriented. Synthesis-side timing leverage is therefore limited; real timing QoR comes from P&R repair.
- Blackbox linking requires the component run to predate the top run — and a component RTL change requires re-running the component first (the error message encodes the discipline).
- The emitted netlist represents constants as `assign` statements; downstream tools handle this, and tie-cell insertion happens in the floorplan stage.

## Commercial perspective

The commercial equivalents (Design Compiler, Genus) integrate the same pipeline with full SDC awareness end-to-end: mapping, sizing and even placement-aware synthesis (physical synthesis) driven by the real constraint set, plus DFT insertion (scan chains) and UPF-driven power intent. The Yosys/ABC split — generic optimization vs AIG-based mapping — mirrors their internal architecture more closely than the tool names suggest.

Source: [run.tcl](../../syn/run.tcl) — [compile.tcl](../../syn/compile.tcl) — [abc.tcl](../../syn/abc.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
