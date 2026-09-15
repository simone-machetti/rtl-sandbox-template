# P&R stage 5 — Finishing

The routed design becomes a set of deliverables: the last physical cells go in, the real parasitics come out, and every downstream consumer — timing, power, simulation, hierarchical reuse, GDS merge — gets its file.

## Inputs and outputs

- **Inputs**: `output/4_route.odb` (+ re-applied context).
- **Outputs**: `output/design.def`, `design.odb`, `design.sdc`, the routed `netlist.v`, `netlist.spef`, `abstract.lef`, `timing_model.lib`; the final report set under `report/`.

## Theory

### Fillers and decap

After placement and repair, rows still contain gaps. **Filler cells** close them — not for looks: they guarantee the continuity of wells, implants and power rails along each row, which the manufacturing rules require. Their **decap** variants fill the same gaps with MOS decoupling capacitors: local charge reservoirs between VDD and VSS that smooth switching-induced supply noise. The tradeoff: decap leaks more than plain filler — density of decap vs leakage budget is a real (if second-order) knob.

### Parasitic extraction and SPEF

Every routed net is a distributed RC network: resistance along each segment and via, capacitance to ground and to neighboring wires (coupling). **Extraction** computes these from the actual geometry — OpenROAD's engine is **OpenRCX**, which applies pattern-calibrated per-unit values (from the platform's `rcx_patterns.rules`, itself calibrated against a golden field-solver extraction) to each segment. The interchange format is **SPEF**: per net, the RC network plus pin connections. SPEF is what makes post-route STA and DPA *parasitics-accurate* — the wire, not the gate, dominates delay and switching energy at advanced nodes.

### Abstracts: making the block reusable

Two generated views turn a finished block into a component ([18_hierarchical.md](../concepts/hierarchical.md)): an **abstract LEF** (`write_abstract_lef` — the outline, boundary pins, and obstruction summary of the real layout) and a **liberty timing model** (`write_timing_model` — port-to-port arcs condensed from the full timing graph, setup/hold at the pins, internal clock latency folded in). Together they let a parent flow place, route around, and time through the block without ever loading its contents. What the timing model does *not* carry: power tables — the reason parent-level power analysis links the block's real netlist instead ([14_post_pnr_dpa.md](14_post_pnr_dpa.md)).

### The netlist contract, again

The routed netlist differs from the synthesized one (repair changed cells; CTS added a tree), so it is re-emitted — minus the purely physical cells (fillers, taps), which have no liberty/simulation models and would break downstream linking. The emitted file satisfies the same `output/netlist.v` contract as synthesis, which is what lets every post-P&R analysis reuse the post-synthesis machinery.

## Implementation walkthrough

`scripts/pnr/5_final.tcl`:

```tcl
source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 4_route
set_propagated_clock [all_clocks]
```

Prologue, routed design, real clocks.

```tcl
# -----------------------------------------------------------------------------
# Filler cells
# -----------------------------------------------------------------------------
filler_placement $FILL_CELLS
global_connect
check_placement -verbose
```

`filler_placement` packs every row gap using the masters from `init_tech.tcl` (`FILLERxp5/FILLER` + the `DECAPx1..x10` family — the tool picks sizes to fit each gap exactly). `global_connect` re-applies the PDN's connection rules so the new cells' power pins join VDD/VSS. The placement invariant is checked one last time.

```tcl
# -----------------------------------------------------------------------------
# Parasitic extraction (OpenRCX)
# -----------------------------------------------------------------------------
define_process_corner -ext_model_index 0 X
extract_parasitics -ext_model_file $::env(ASAP7_HOME)/rcx_patterns.rules
write_spef $OUT_DIR/netlist.spef
read_spef $OUT_DIR/netlist.spef
```

Extraction: one process corner is declared (named `X`, selecting model index 0 in the rules file — single-corner extraction matching the flow's single-corner analysis), OpenRCX runs over the routed geometry, and the result is written as SPEF. The immediate `read_spef` loads it back into this session's timer, so the final reports below are computed on *extracted* — not estimated — parasitics.

```tcl
# -----------------------------------------------------------------------------
# Final reports
# -----------------------------------------------------------------------------
report_checks \
    -path_delay max \
    -fields {slew cap input_pins} \
    -digits 4 \
    -group_path_count 10 \
    > $REPORT_DIR/critical_paths.rpt
report_wns        > $REPORT_DIR/wns.rpt
report_tns        > $REPORT_DIR/tns.rpt
report_clock_skew > $REPORT_DIR/clock_skew.rpt
report_power      > $REPORT_DIR/power.rpt
report_design_area_file $REPORT_DIR/design_area.rpt
```

The definitive in-flow measurement set: worst paths (named to match the STA steps' reports for easy comparison), the WNS/TNS scalars, the clock tree's achieved skew, a power snapshot (static-probability activity — the vector-accurate number comes from [14_post_pnr_dpa.md](14_post_pnr_dpa.md)), and area/utilization via the helper from [05_pnr_overview.md](05_pnr_overview.md).

```tcl
# -----------------------------------------------------------------------------
# Final products
# -----------------------------------------------------------------------------
write_def $OUT_DIR/design.def
write_sdc $OUT_DIR/design.sdc
write_verilog -remove_cells "$FILL_CELLS $TAPCELL" $OUT_DIR/netlist.v
write_abstract_lef $OUT_DIR/abstract.lef
write_timing_model $OUT_DIR/timing_model.lib
write_db $OUT_DIR/design.odb
```

The deliverables: the layout as DEF (interchange; input to the GDS merge) and as ODB (complete database — the file to open in the GUI); the constraints as actually applied; the routed netlist with physical-only cells stripped (`-remove_cells` takes the filler and tap masters — tie cells *stay*: they drive real nets and have models); the two hard-macro abstracts; and the final database, written last so it includes everything.

## Design space

- **Decap density**: replacing plain fillers with more/larger decaps trades leakage for supply-noise margin; IR-drop-driven flows place decap deliberately near aggressors rather than as gap-filler.
- **Extraction fidelity**: multi-corner extraction (C-worst/RC-worst...), coupling-preserving SPEF for SI analysis, or signoff extractors (StarRC, Quantus) calibrated to the foundry deck — the ladder above single-pattern-corner OpenRCX.
- **Abstract quality**: `write_abstract_lef` options (bloating/merging obstructions) trade abstract precision for parent-tool robustness — with real consequences on parent-level routing and PDN (a fully-covered layer blocks the parent's via stacks; see [18_hierarchical.md](../concepts/hierarchical.md)).
- **Extra outputs**: SDF (delay annotation for event-driven GLS) is one `write_sdf` away when a consuming simulator exists; some flows also emit an LEF+lib+GDS "IP package" per block release.

## Knobs

| Knob             | Where           | Default        | Effect / tradeoff                                      |
| ---------------- | --------------- | -------------- | ------------------------------------------------------ |
| `FILL_CELLS`     | `init_tech.tcl` | filler + decap | Gap filling mix: decap share = noise margin vs leakage |
| extraction rules | `5_final.tcl`   | platform file  | Parasitic accuracy — calibrated per technology         |

## Notes and caveats

- `read_spef` before the reports is what makes this stage's numbers the run's ground truth; the post-P&R STA step reproduces them exactly from the written files — a built-in consistency check between flow and analysis.
- The stripped netlist is the reason gate-level simulation of the routed design works at all; simulating a netlist containing fillers/taps would fail at link time for lack of models.
- `write_timing_model` produces timing arcs only — no power tables (a characterization-tool task); plan hierarchical power analysis accordingly.
- The in-flow `report_power` uses default activity assumptions; only VCD-annotated DPA gives workload power.
- Everything this stage writes is per-run and disposable; the run directory *is* the release artifact.

## Commercial perspective

Same checklist under commercial flows — filler/decap insertion, signoff extraction, and "model generation" (abstract LEF + ETM/ILM timing models; ETMs are the direct analog of `write_timing_model`). The additions: metal fill (density-rule dummy metal, usually with the GDS step), signoff-grade extraction decks, and formal IP packaging conventions around the same set of views.

Source: [5_final.tcl](../../pnr/5_final.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
