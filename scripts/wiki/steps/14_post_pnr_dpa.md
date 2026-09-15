# Post-place-and-route dynamic power analysis

The most accurate power number the flow produces: measured switching activity on the routed netlist with extracted wire capacitances — and, for hierarchical results, a *full-view* mode that analyzes hard macros as their real gates rather than powerless abstracts.

## Inputs and outputs

**Inputs**

- Post-pnr netlist `.v`
- Library of cells `.lib` (Liberty)
- Post-pnr parasitics `.spef`
- Post-pnr switching activity `.vcd` (from POST-PNR-SIM)
- Constraints, generated inline, clocks propagated
- Hardened-block routed netlists `.v` + parasitics `.spef` (`MACRO_DIRS`, hierarchical results: the blocks are linked in full and annotated per instance, so macro internals are analyzed with real power tables)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR`, `VCD_DIR` (required); `TB`, `MACRO_DIRS` (optional)

**Outputs**

- Power reports (`power_summary.rpt`, `power_macros.rpt` with per-macro breakdown in hierarchical runs, VCD annotation reports)

## Theory

All the power theory of [04_post_syn_dpa.md](04_post_syn_dpa.md) applies; the post-route upgrades:

- **Wire capacitance is real.** The SPEF supplies each net's extracted C, so switching power includes the wires — at advanced nodes frequently the *majority* of dynamic power. The post-syn→post-pnr power increase on the same design is genuine physics: wires, clock tree, repair buffers.
- **The clock tree exists.** Its buffers and wiring, a top-3 consumer in most synchronous designs, are now in the netlist and the report's "Clock" group.

### The hierarchical problem and the full-view solution

A parent netlist from a hierarchical P&R contains macros as *named instances only*; the generated `timing_model.lib` provides timing arcs but **no power tables** (power characterization is a different discipline requiring transistor-level simulation). Linked that way, a macro contributes zero internal/switching power — silently wrong totals.

The full-view mode dissolves the abstraction *for analysis only*: read each block's routed **netlist** together with the parent's (the macro instance then elaborates into its real gates, which all have liberty power data), annotate each instance's internals with the block's own **SPEF** (per-instance annotation), and use the GLS VCD — which already contains macro-internal activity, since simulation compiles the blocks too ([12_post_pnr_sim.md](12_post_pnr_sim.md)). Every gate then has real power tables, real wire caps, and measured activity: exact totals, plus a per-macro breakdown for free. The implementation stays hierarchical; only the power computation sees the whole.

Its natural limit is the VCD: full-chip gate-level simulation bounds the design size this works for. Beyond it, the compositional method applies — per-macro in-system power measured on a smaller configuration, scaled by instance count, plus the parent-level logic measured with the abstract view.

## Implementation walkthrough

`scripts/post-pnr-dpa/run.tcl` — loading, constraints and VCD blocks are as in the post-syn version ([04_post_syn_dpa.md](04_post_syn_dpa.md), [02_constraints.md](../concepts/constraints.md)); the hierarchical machinery is what's new:

```tcl
if {$env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $env(SEL_MACRO_DIRS) {
        read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$dir/output/netlist.v
    }
}
read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design $env(SEL_TOP_LEVEL)
```

Full-view linking: the blocks' routed netlists are read *before* the parent's, so `link_design` elaborates each macro instance into its gates. Deliberately, the blocks' `timing_model.lib` files are **not** loaded here — a Verilog definition and a liberty cell of the same name must not compete; power analysis wants the gates.

```tcl
read_spef $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.spef

if {$env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $env(SEL_MACRO_DIRS) {
        set netlist $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$dir/output/netlist.v
        set fh [open $netlist r]
        set mod ""
        while {[gets $fh line] >= 0} {
            if {[regexp {^module\s+(\S+?)\s*\(} $line -> mod]} {
                break
            }
        }
        close $fh
        if {$mod eq ""} {
            error "MACRO_DIRS: no module found in $netlist"
        }
        foreach inst [get_cells *] {
            if {[get_property $inst ref_name] eq $mod} {
                read_spef -path [get_full_name $inst] \
                    $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$dir/output/netlist.spef
                lappend macro_insts $inst
            }
        }
    }
}

set_propagated_clock [all_clocks]
```

Two-level parasitics. The parent SPEF annotates the top-level nets as usual. Then, per hardened block: its module name is parsed from its netlist's `module` line, every top-level instance of that module is found (matching by `ref_name` — a block placed N times gets annotated N times), and `read_spef -path <instance>` applies the block's SPEF *inside* that instance's scope. The instances are collected for the report below. Result: extracted parasitics everywhere, each region from its own layout's extraction.

```tcl
set vcd_verilator "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/sim/$env(SEL_VCD_DIR)/output/activity.vcd"
read_vcd -scope $env(SEL_TB)/dut $vcd_verilator

report_activity_annotation -report_annotated   > $REPORT_DIR/vcd_annotated.rpt
report_activity_annotation -report_unannotated > $REPORT_DIR/vcd_unannotated.rpt
```

The VCD annotation, unchanged in form — but because the GLS elaborated the blocks, the dump's hierarchy matches the full-view design and macro-internal nets annotate like any others. The coverage reports remain the health check: near-total annotated, near-zero unannotated.

```tcl
report_power > $REPORT_DIR/power_summary.rpt

if {[info exists macro_insts]} {
    report_power -instances $macro_insts > $REPORT_DIR/power_macros.rpt
}
```

The summary — true totals, macros included — and, when macros exist, the per-instance breakdown: one line per hard-macro instance with its in-system internal/switching/leakage/total. That per-macro number under real workload is the quantity compositional scaling methods consume.

## Design space

- **Full-view vs compositional**: full-view is exact but VCD-bounded; the compositional alternative (block power from its own run × instances + parent logic) scales indefinitely at the cost of ignoring per-instance activity variation. The per-macro report is precisely what calibrates the second against the first.
- **Real macro power models** (liberty power tables for blocks) would restore abstract-view power — but require characterization tooling outside this flow's scope, and a static table cannot represent workload dependence anyway.
- **Glitch accuracy**: as at post-syn, a delay-annotated GLS would add glitch power — most significant post-route, where real delays exist to model.
- **Time-windowed analysis** (VCD slices per operating phase) refines a single run into per-phase power without new simulations.

## Knobs

| Knob                      | Where | Default          | Effect / tradeoff                                  |
| ------------------------- | ----- | ---------------- | -------------------------------------------------- |
| `CLK_PERIOD_NS`           | make  | 1.0              | Frequency normalization — compare at equal periods |
| `NETLIST_DIR` / `VCD_DIR` | make  | —                | The P&R run and its GLS activity                   |
| `MACRO_DIRS`              | make  | none             | Enables full-view analysis + `power_macros.rpt`    |
| `TB`                      | make  | `tb_<top_level>` | Must match the VCD-producing bench                 |

## Notes and caveats

- The loose-logic-only failure mode is silent: a hierarchical run analyzed *without* `MACRO_DIRS`... does not link at all (missing modules) — but linking with the timing models loaded (as STA does) would produce zero-power macros. The step's design — netlists in, timing models out — exists to make the wrong path impossible.
- An internal consistency property worth knowing: the full-view total equals the abstract-view total (loose logic) plus the macro report's sum — the decomposition is exact.
- The module-name parse expects the flow's own `write_verilog` output format; hand-edited netlists that reshape the `module` line would break it loudly.
- All post-syn DPA caveats (dut scope, glitch bias, frequency scaling) carry over.
- A macro hardened at low utilization carries measurably more wire power than the same logic flat — implementation choices show up in this report.

## Commercial perspective

PrimePower on a routed design with SPEF and simulation activity is the direct equivalent; hierarchical designs there use either flattened analysis (this step's full-view) or characterized block power models when available. The per-instance macro breakdown corresponds to standard block-level power reporting in those tools.

Source: [run.tcl](../../post-pnr-dpa/run.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
