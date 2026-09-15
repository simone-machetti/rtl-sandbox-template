# P&R stage 2 — Placement

Placement decides where every standard cell sits. It is the stage with the widest quality leverage in the whole backend: wire lengths — and therefore delay, power and routability — are largely fixed here.

## Inputs and outputs

- **Inputs**: the floorplan checkpoint `output/1_floorplan.odb` (+ the context re-applied by `load_checkpoint`).
- **Outputs**: `output/2_place.odb` — every cell legally placed, design repaired for fanout/slew — and `report/2_place.rpt`.

## Theory

### Global placement

Modern global placers treat placement as a continuous optimization: cells become movable objects, nets pull their cells together (minimizing estimated wirelength), while a spreading force pushes cells apart wherever local density exceeds the target. OpenROAD's engine (RePlAce lineage) models this electrostatically — cell area as charge, density as potential — and iterates to equilibrium. The result is an *overlapping but well-spread* placement that minimizes wirelength under a **density target**: the knob that decides how tightly cells may cluster locally (distinct from the floorplan's global utilization — density is enforced per region, catching local hot spots).

Two refinements matter in practice: **routability-driven** placement runs a quick routing congestion estimate and inflates cells in congested regions, trading wirelength for routability; **timing-driven** placement weights nets by their timing criticality so critical paths contract at the expense of don't-care nets.

### Legalization and detailed placement

Global placement's output is physically illegal (overlaps, off-site positions). **Detailed placement** snaps every cell to a legal site — respecting rows, fixed cells (taps, macros) and density — while minimizing the displacement from the global solution, then applies local improvements (cell swapping, flipping).

### Design repair

Between the two placement phases sits the first *netlist surgery* of the backend. The synthesized netlist arrives with two classes of electrical problems: high-fanout nets that synthesis never buffered (ABC does not buffer register outputs — [01_syn.md](01_syn.md)) and drive strengths chosen without knowledge of real wire loads. **`repair_design`** walks every net with estimated placement parasitics, inserting buffers and resizing drivers until slew, capacitance and fanout limits from the liberty are met. This is the step that turns "netlist that simulates" into "netlist that can meet electrical rules on silicon".

## Implementation walkthrough

`scripts/pnr/2_place.tcl`:

```tcl
source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 1_floorplan
```

Standard prologue ([05_pnr_overview.md](05_pnr_overview.md)): context + the floorplan database.

```tcl
# -----------------------------------------------------------------------------
# Netlist cleanup
# -----------------------------------------------------------------------------
remove_buffers
repair_tie_fanout -separation 0 $TIEHI_PORT
repair_tie_fanout -separation 0 $TIELO_PORT
```

`remove_buffers` deletes the buffer chains synthesis inserted — they were sized against no placement information; the repair steps below will re-buffer against *real* estimated loads, and starting clean gives a better result than patching. `repair_tie_fanout` splits overloaded tie cells: if one TIEHI/TIELO drives many constant loads, clones are inserted so each drives a legal fanout (`-separation 0` places clones freely near their loads).

```tcl
# -----------------------------------------------------------------------------
# Global placement & final pin placement
# -----------------------------------------------------------------------------
global_placement \
    -density $::env(SEL_PLACE_DENSITY) \
    -routability_driven \
    -timing_driven

set_pin_length -hor_length 0.24 -ver_length 0.24
place_pins -hor_layers $PIN_LAYER_HOR -ver_layers $PIN_LAYER_VER
```

Global placement with both refinement modes on and the density target from the make level (default 0.60 — the platform's recommended value: 60 % maximum local occupancy). Then the **final** pin placement: the floorplan's pin pass ran before any cell had a position; now, with the placement known, `place_pins` re-optimizes every port's boundary position against where its loads actually are (pin geometry settings are per-process, hence repeated).

```tcl
# -----------------------------------------------------------------------------
# Design repair (buffering & sizing)
# -----------------------------------------------------------------------------
estimate_parasitics -placement
repair_design
```

`estimate_parasitics -placement` computes every net's RC from the placed cell positions and the per-layer values of `setRC.tcl` — the best wire model available before routing. `repair_design` then fixes electrical violations net by net: buffering high-fanout and long nets, up/down-sizing drivers against real estimated loads (within the `set_dont_use` blacklist: no fractional-drive cells, no spontaneous ICGs).

```tcl
# -----------------------------------------------------------------------------
# Detailed placement
# -----------------------------------------------------------------------------
detailed_placement
optimize_mirroring
check_placement -verbose

report_stage 2_place
save_checkpoint 2_place
```

Legalization of everything — including the cells repair just created — followed by `optimize_mirroring` (flip cells about their y-axis where it shortens wires; free wirelength) and the invariant check: `check_placement` errors if any cell is unplaced, overlapping or off-site. Then the standard epilogue.

## Design space

- **Density** is the primary placement knob. Lowering it (toward the floorplan utilization) spreads cells: better routability, longer wires; raising it clusters: shorter wires until congestion bites. The classic congestion ladder is `PLACE_DENSITY` down → `CORE_UTIL` down → floorplan rework.
- **Mode selection**: `-timing_driven`/`-routability_driven` cost runtime (internal STA and trial routing per iteration) and are worth it for anything beyond trivial blocks. Skew-aware and cluster-guided variants exist upstream for special structures.
- **Cell padding** (`set_placement_padding`) reserves empty sites next to selected cells — a pre-emptive congestion/ECO-space tool this flow doesn't need yet.
- **Incremental placement**: re-legalizing after small netlist edits instead of re-running global placement — the pattern later stages use when their repairs add cells.
- **The repair-here-vs-repair-later split**: this flow repairs electrical rules now and timing after CTS ([08_pnr_cts.md](08_pnr_cts.md)) — matching the information available at each point (no real clock yet, so setup repair now would chase provisional numbers).

## Knobs

| Knob            | Where         | Default | Effect / tradeoff                                                   |
| --------------- | ------------- | ------- | ------------------------------------------------------------------- |
| `PLACE_DENSITY` | make          | 0.60    | Local packing; ↓ = routability, ↑ = shorter wires until congestion  |
| pin length      | `2_place.tcl` | 0.24 µm | Boundary pin depth (kept identical to the floorplan pass)           |
| repair limits   | tool defaults | liberty | `repair_design` honors liberty max-slew/cap/fanout — implicit knobs |

## Notes and caveats

- **Density ≠ utilization**: utilization (floorplan) fixes the die; density (placement) limits local clustering inside it. Density below utilization is infeasible; equal values force perfect spreading.
- `repair_design` is where the synthesized netlist's unbuffered broadcast nets get fixed — the buffer counts in this stage's log are the direct measure of how much electrical work synthesis left behind.
- Repair adds area: utilization reported after this stage is higher than the floorplan's construction value — headroom for it is part of choosing `CORE_UTIL`.
- The pin placement here is the binding one; the floorplan's pass was scaffolding.
- `check_placement` failing after repair usually means density/utilization left no room to legalize the added buffers — the congestion ladder applies.

## Commercial perspective

Commercial placers (Innovus `place_opt_design`, Fusion Compiler) fuse placement, buffering and sizing into one timing-driven mega-step with concurrent clock planning at the high end. The decomposition here — global placement, pin refinement, electrical repair, legalization — is exactly what that mega-step performs internally, just visible and separately controllable.

Source: [2_place.tcl](../../pnr/2_place.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
