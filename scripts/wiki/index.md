# Learn ASIC Flow

A complete, code-grounded walk through the ASIC implementation flow of this repository — from RTL to a routed, power-analyzed layout in ASAP7. Every page quotes the flow scripts in `scripts/` verbatim and links back to them. See [log.md](log.md) for the change history.

> Organized as: **concepts/** — the cross-cutting background every step assumes (the pipeline itself, the PDK, the timing constraints, the hierarchical macro flow); **steps/** — one page per pipeline stage, numbered in flow order, each a walkthrough of the scripts that implement it; **references/** — lookup material that is consulted rather than read.

## Reading order

1. [ASIC flow pipeline](concepts/pipeline.md) — this course's map; read first
2. [Technology](concepts/technology.md)
3. [Constraints](concepts/constraints.md)
4. [00 Simulation](steps/00_sim.md) → [01 Synthesis](steps/01_syn.md) → [02](steps/02_post_syn_sim.md) / [03](steps/03_post_syn_sta.md) / [04](steps/04_post_syn_dpa.md) post-synthesis analyses
5. [05 P&R overview](steps/05_pnr_overview.md), then the six stages [06](steps/06_pnr_floorplan.md) → [11](steps/11_pnr_gds.md)
6. [12](steps/12_post_pnr_sim.md) / [13](steps/13_post_pnr_sta.md) / [14](steps/14_post_pnr_dpa.md) post-P&R analyses
7. [Hierarchical flow](concepts/hierarchical.md)
8. [Knobs](references/knobs.md) — cross-reference, dip in as needed

The step numbers run `00`–`14` in pipeline order and index the steps only — the concept pages above are unnumbered, since their place in the course is what this list records.

## Concepts

* [ASIC flow pipeline](concepts/pipeline.md) — the map: the five `make` stages and how they chain, the tool and PDK inventory, and the repository conventions (the `SEL_*` parameter contract, run-directory layout, picoseconds, `clk_i`, in-repo flow code) that every later page relies on.
* [Technology](concepts/technology.md) — PDK anatomy: liberty, LEF, GDS, corners, VT flavors, and the ASAP7 specifics this flow depends on.
* [Constraints](concepts/constraints.md) — SDC theory and the shared clock + virtual-clock + hold-false-path scheme used across every timing-aware step.
* [Hierarchical flow](concepts/hierarchical.md) — the hard-macro loop across synthesis, P&R and the analyses: how a completed P&R run becomes a macro consumable by the next one.

## Steps

* [00 Simulation](steps/00_sim.md) — `make sim`: pre-synthesis functional simulation with Verilator, self-checking testbenches, optional activity dump.
* [01 Synthesis](steps/01_syn.md) — `make syn`: elaboration with yosys-slang, technology mapping through ABC, and the hierarchy modes (blackbox, keep, flat).
* [02 Post-synthesis simulation](steps/02_post_syn_sim.md) — gate-level simulation of the synthesized netlist and the cell models it needs.
* [03 Post-synthesis STA](steps/03_post_syn_sta.md) — static timing analysis on ideal wires.
* [04 Post-synthesis power](steps/04_post_syn_dpa.md) — VCD-annotated dynamic power analysis.
* [05 P&R overview](steps/05_pnr_overview.md) — the place-and-route architecture: six stages, the checkpoint mechanism, shared helpers and plumbing.
* [06 Floorplan](steps/06_pnr_floorplan.md) — die and core area, rows, tracks, pin placement, tie and tap cells, the power grid.
* [07 Placement](steps/07_pnr_place.md) — global and detailed placement plus design repair.
* [08 Clock-tree synthesis](steps/08_pnr_cts.md) — building and propagating the clock tree, then repairing setup.
* [09 Routing](steps/09_pnr_route.md) — global and detailed routing.
* [10 Finishing](steps/10_pnr_final.md) — filler insertion, RC extraction, final products.
* [11 GDS merge](steps/11_pnr_gds.md) — the KLayout stream-out that produces the final layout.
* [12 Post-P&R simulation](steps/12_post_pnr_sim.md) — gate-level simulation of the routed netlist.
* [13 Post-P&R STA](steps/13_post_pnr_sta.md) — parasitics-accurate timing with real wire RC and propagated clocks.
* [14 Post-P&R power](steps/14_post_pnr_dpa.md) — parasitics-accurate power, including the full-view hierarchical mode.

## References

* [Knobs](references/knobs.md) — cross-reference of every tunable parameter: default, range, effect and the direction each tradeoff moves.

## How to read


Every document follows the same template: **Inputs and outputs** (position in the pipeline, files consumed and produced) → **Theory** (the step in any ASIC flow, terms defined from scratch) → **Implementation walkthrough** (the scripts quoted verbatim, block by block — no code skipped) → **Design space** (alternatives to each decision and their implications) → **Knobs** (what can be tuned, in which direction each tradeoff moves) → **Notes and caveats** (flow-specific facts, pitfalls and known artifacts) → **Commercial perspective** (what the step is called in commercial flows, where useful).

Two companions while reading:

- `scripts/asic_flow.md` — the compact per-step inputs/outputs/parameters reference.
- `README.md` — the full command reference.
