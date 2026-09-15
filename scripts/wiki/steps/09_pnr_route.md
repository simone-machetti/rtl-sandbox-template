# P&R stage 4 — Routing

Routing turns every logical net into metal: the longest, most memory-hungry stage, and the one whose output must satisfy the manufacturing rules exactly. It also hosts the final timing repair, because only routed wires have true parasitics.

## Inputs and outputs

- **Inputs**: `output/3_cts.odb` (+ re-applied context).
- **Outputs**: `output/4_route.odb` — every net detail-routed, timing repaired — and `report/4_route.rpt` + `report/route_drc.rpt` (which must be empty).

## Theory

### Global vs detailed routing

Routing is solved in two resolutions:

- **Global routing** divides the die into a coarse grid of cells (GCells) with a known track *capacity* per layer, and assigns every net a path through that grid — no exact wires yet, just corridors ("route guides"). Its currency is **congestion**: demand vs capacity per GCell edge; overflow means more nets want through a region than tracks exist. Global routing is fast, and its congestion map is the flow's early-warning system.
- **Detailed routing** turns each net's corridor into exact wire segments on exact tracks with exact vias, obeying every design rule — spacing, minimum area, via enclosure, and the advanced-node LEF58 rules (end-of-line keep-outs and friends). It works iteratively: route everything, count violations, rip-up-and-reroute offenders, repeat until clean (or stuck). At 7 nm this is by far the dominant consumer of runtime and memory.

### Layer management

Two policies shape where wires may go. The **layer window** (`set_routing_layers`) restricts signals to M2–M7: M1 belongs to cells and power rails, M8/M9 are reserved thick layers. Clocks get a *higher floor* (M4–M7): mid/upper layers have lower resistance, giving the tree lower latency and skew. The **layer adjustment** (`set_global_routing_layer_adjustment 0.25`) tells the global router to pretend 25 % of each layer's capacity doesn't exist — safety margin so its plan doesn't saturate what the detailed router (which also fights rule geometry, not just capacity) can deliver.

### Timing repair with real wires

After global routing, parasitics can be estimated *from the guides* — much closer to reality than placement estimates. This is where the flow performs its final optimization: setup repair (with real wire RC, some paths got slower) and the first **hold repair** — real now because clock skew (CTS) and true data-path delays (routing) both exist; the fix is inserting small delay buffers on too-fast paths. I/O hold is excluded by the constraint scheme ([02_constraints.md](../concepts/constraints.md)) precisely so this step spends buffers only on real, internal races.

### The antenna effect (and why this flow skips its repair)

During fabrication, a long wire connected to a gate but not yet to its driver (upper layers unbuilt) collects plasma charge that can damage the gate — the *antenna effect*. Standard cures: break the wire with a jumper to an upper layer, or attach a small **diode** cell to bleed charge. The ASAP7 platform ships no diode cell, so the flow performs no antenna repair — acceptable for a predictive-PDK methodology flow, mandatory to revisit for any real tapeout.

## Implementation walkthrough

`scripts/pnr/4_route.tcl`:

```tcl
source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 3_cts
set_propagated_clock [all_clocks]
```

Prologue plus the propagated-clock re-declaration (an analysis-state setting, lost between processes like all SDC).

```tcl
# -----------------------------------------------------------------------------
# Global routing
# -----------------------------------------------------------------------------
set_global_routing_layer_adjustment $MIN_ROUTE_LAYER-$MAX_ROUTE_LAYER 0.25
set_routing_layers \
    -signal $MIN_ROUTE_LAYER-$MAX_ROUTE_LAYER \
    -clock  $MIN_CLK_LAYER-$MAX_ROUTE_LAYER

global_route -congestion_iterations 30 -verbose
```

The two layer policies (M2–M7 signals, M4–M7 clocks, 25 % capacity haircut — the platform's calibrated value), then global routing with up to 30 congestion-negotiation iterations. The log's congestion table — per-layer resource/demand/overflow — is the report to read first when a design is too dense: nonzero overflow here predicts detailed-routing pain before hours are spent.

```tcl
# -----------------------------------------------------------------------------
# Post-route timing repair
# -----------------------------------------------------------------------------
estimate_parasitics -global_routing
repair_timing -setup
repair_timing -hold
detailed_placement

global_route -congestion_iterations 30 -verbose
```

Parasitics from the route guides, then the two repairs in the canonical order — setup first (may resize/restructure), hold second (adds delay buffers; doing it last avoids un-fixing setup) — followed by legalization of whatever repair inserted, and a **re-route**: the netlist changed, so the global plan is rebuilt to match it. The second congestion table is the one that must be clean.

```tcl
# -----------------------------------------------------------------------------
# Detailed routing
# -----------------------------------------------------------------------------
detailed_route \
    -output_drc $REPORT_DIR/route_drc.rpt \
    -verbose 1

report_stage 4_route
save_checkpoint 4_route
```

TritonRoute consumes the guides and produces DRC-clean metal, iterating (`Completing X% with N violations` in the log — the count must reach 0). Layer limits are inherited from `set_routing_layers`. Remaining violations are written to `route_drc.rpt` with type, nets and coordinates — the file the flow treats as its pass/fail gate. Then the standard epilogue; this stage's `report_stage` shows the final flow timing (stage 5 re-measures with extracted parasitics).

## Design space

- **The layer window** is a real design lever: shrinking it (e.g. M2–M5) models a cheaper metal stack or reserves layers for a parent design; widening (M8/M9) helps power-hungry global nets. Every window change re-prices congestion.
- **Adjustment factor**: lower values pack the global plan tighter (risking detailed-route churn), higher values spread and lengthen wires. 0.2–0.35 is the usual band; raising it is the cheap knob when detailed routing struggles but overflow reads zero.
- **Congestion iterations**: more negotiation helps marginal designs; a design needing many is telling you about density, not about the knob.
- **`-allow_congestion`**: lets global routing hand an overflowing plan to detailed routing — occasionally useful for post-mortems, never for production runs.
- **Antenna repair**: with a diode-equipped library, `repair_antennas` between global and detailed routing (plus a re-check after) is the standard insertion point.
- **Post-route optimization**: a final `repair_timing` on *extracted* parasitics (stage-5 quality) is the next escalation commercial flows apply; this flow stops repair at guide-based parasitics.

## Knobs

| Knob                  | Where           | Default | Effect / tradeoff                                                   |
| --------------------- | --------------- | ------- | ------------------------------------------------------------------- |
| `MIN/MAX_ROUTE_LAYER` | `init_tech.tcl` | M2/M7   | Signal layer window: capacity vs stack cost/reservations            |
| `MIN_CLK_LAYER`       | `init_tech.tcl` | M4      | Clock RC quality vs stealing upper-layer capacity                   |
| layer adjustment      | `4_route.tcl`   | 0.25    | Global-plan safety margin: wirelength vs detailed-route convergence |
| congestion iterations | `4_route.tcl`   | 30      | Negotiation effort on marginal designs                              |
| `PNR_THREADS`         | make            | all     | Detailed routing dominates: threads ↔ runtime ↔ memory peak         |

## Notes and caveats

- **`route_drc.rpt` must be empty** — the flow's definition of routed success. Exception documented in [18_hierarchical.md](../concepts/hierarchical.md): a few `Lef58EolKeepOut` markers at hard-macro pins are known false positives of abstract-based routing (the "obstruction" is the same net's continuation inside the block).
- Detailed routing dominates the whole flow's runtime (tens of minutes for ~50 k instances; hours at hundreds of thousands) and memory (its peak scales with parallel workers — `PNR_THREADS` is the relief valve).
- Hold repair *increases* area and power by design (delay buffers); its insertion counts in the log are worth watching — an explosion usually points at a constraint modeling problem, not a design problem.
- No antenna repair is performed (no diode in the platform) — a flow property to remember when reading DRC expectations elsewhere.
- Zero overflow in global routing does not guarantee easy detailed routing (rule geometry is a second fight), but overflow guarantees trouble.

## Commercial perspective

The same two-resolution architecture under commercial names (Innovus `routeDesign`/NanoRoute, Fusion Compiler/ICC2 Zroute), with production additions: signal-integrity-aware routing (crosstalk avoidance and SI timing), non-default rules for clocks/buses, timing-driven track assignment, and integrated antenna/metal-fill handling. TritonRoute's iterate-to-zero-DRC loop is the same convergence model those routers run.

Source: [4_route.tcl](../../pnr/4_route.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
