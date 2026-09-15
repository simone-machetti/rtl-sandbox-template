# Knob reference

Every tunable of the flow in one place: the make-level parameters, the script-level values worth knowing (and possibly promoting to parameters), and the implicit tool defaults that behave like knobs. Each entry links to the document that explains it in depth. Direction arrows read: what happens when the value *increases*.

## Run plumbing

| Knob          | Steps       | Default          | Effect                                                                | Doc                                 |
| ------------- | ----------- | ---------------- | --------------------------------------------------------------------- | ----------------------------------- |
| `PROJECT`     | all         | — (required)     | Selects the project tree                                              | [pipeline](../concepts/pipeline.md) |
| `TOP_LEVEL`   | all         | — (required)     | The module to build/analyze                                           | [pipeline](../concepts/pipeline.md) |
| `OUT_DIR`     | all         | `no_name`        | Run directory name; full runs always start clean                      | [pipeline](../concepts/pipeline.md) |
| `NETLIST_DIR` | pnr, post-* | `no_name`        | The producing run to consume (syn for pnr/post-syn, pnr for post-pnr) | [pipeline](../concepts/pipeline.md) |
| `VCD_DIR`     | *-dpa       | `no_name`        | The simulation run holding `activity.vcd`                             | [04](../steps/04_post_syn_dpa.md)   |
| `TB`          | sims, dpas  | `tb_<top_level>` | Bench selection (must follow the bench conventions)                   | [00](../steps/00_sim.md)            |

## Timing intent

| Knob                 | Steps        | Default | Effect                                                                                                                        | Doc                                       |
| -------------------- | ------------ | ------- | ----------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| `CLK_PERIOD_NS`      | all but init | 1.0     | The one timing target: syn's ABC delay goal, every STA's period, P&R's optimization target. ↑ = easier closure, slower design | [constraints](../concepts/constraints.md) |
| `CLK_UNCERTAINTY_PS` | pnr          | 0       | Margin on all checks. ↑ = more pessimism → more repair, more area/power                                                       | [constraints](../concepts/constraints.md) |
| clock port name      | convention   | `clk_i` | Constraint generation targets it; absent = combinational treatment                                                            | [constraints](../concepts/constraints.md) |
| I/O delays           | scheme       | 0       | Boundary paths get the full period; nonzero values would model a real integration budget                                      | [constraints](../concepts/constraints.md) |

## Simulation

| Knob     | Steps         | Default | Effect                                                          | Doc                      |
| -------- | ------------- | ------- | --------------------------------------------------------------- | ------------------------ |
| `PARAMS` | sim, syn, GLS | none    | Elaboration parameters — the design-size dial                   | [00](../steps/00_sim.md) |
| `VCD`    | sims          | 0       | Activity dump. ↑runtime, large files; required by the dpa steps | [00](../steps/00_sim.md) |

## Synthesis

| Knob                   | Default                  | Effect                                                                                                          | Doc                                         |
| ---------------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `KEEP_HIERARCHY`       | 0                        | Preserve all module boundaries: per-module reporting vs optimization freedom                                    | [01](../steps/01_syn.md)                    |
| `KEEP_MODULES`         | none                     | Preserve selected boundaries only                                                                               | [01](../steps/01_syn.md)                    |
| `BLACKBOX_MODULES`     | none                     | Reuse prior component runs; constant sub-results, boundary pessimism                                            | [01](../steps/01_syn.md)                    |
| `LINK_BLACKBOXES`      | 1                        | `0` = leave stubs empty → macro-ready netlist                                                                   | [hierarchical](../concepts/hierarchical.md) |
| ABC script (`abc.tcl`) | map/buffer/sizing recipe | The mapping strategy itself; `{D}` carries the delay target. Alternative recipes (`&nf`) are the QoR experiment | [01](../steps/01_syn.md)                    |

## Floorplan

| Knob               | Level         | Default         | Effect                                                                                                                                                | Doc                                                                             |
| ------------------ | ------------- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `CORE_UTIL`        | make          | 40              | Die area from cell area. ↑ = smaller die, shorter wires ↔ congestion, less repair room. For blocks to be hardened: sets the macro's footprint forever | [06](../steps/06_pnr_floorplan.md)                                              |
| `ASPECT_RATIO`     | make          | 1.0             | Core shape; square minimizes average wirelength                                                                                                       | [06](../steps/06_pnr_floorplan.md)                                              |
| `CORE_MARGIN`      | make          | 2 µm            | Core-to-die ring for boundary pins                                                                                                                    | [06](../steps/06_pnr_floorplan.md)                                              |
| pin layers         | script        | M4/M5           | Boundary pin capacity and parent-level compatibility                                                                                                  | [06](../steps/06_pnr_floorplan.md)                                              |
| pin length         | script        | 0.24 µm         | Pin landing depth. ↑ = easier access, more boundary obstruction                                                                                       | [06](../steps/06_pnr_floorplan.md)                                              |
| tap distance       | script        | 25 µm           | Latch-up margin ↔ a sliver of area                                                                                                                    | [06](../steps/06_pnr_floorplan.md)                                              |
| PDN widths/pitches | strategy file | platform values | IR-drop/EM margin ↔ signal-track capacity on the strap layers                                                                                         | [06](../steps/06_pnr_floorplan.md)                                              |
| `PDN`              | make          | auto            | Whole-strategy override (flat default / macro-aware / custom file)                                                                                    | [06](../steps/06_pnr_floorplan.md), [hierarchical](../concepts/hierarchical.md) |

## Placement

| Knob            | Level   | Default                   | Effect                                                                                                        | Doc                            |
| --------------- | ------- | ------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| `PLACE_DENSITY` | make    | 0.60                      | Local packing limit. ↓ = routability, ↑ = shorter wires until congestion. First knob of the congestion ladder | [07](../steps/07_pnr_place.md) |
| placement modes | script  | routability+timing driven | Runtime ↔ QoR refinements of global placement                                                                 | [07](../steps/07_pnr_place.md) |
| repair limits   | liberty | max slew/cap/fanout       | Implicit electrical rules `repair_design` enforces                                                            | [07](../steps/07_pnr_place.md) |

## Clock tree

| Knob            | Level  | Default                           | Effect                                                                                       | Doc                          |
| --------------- | ------ | --------------------------------- | -------------------------------------------------------------------------------------------- | ---------------------------- |
| `MIN_CLK_LAYER` | script | M4                                | Clock wiring quality (RC) ↔ upper-layer capacity                                             | [08](../steps/08_pnr_cts.md) |
| CTS options     | script | clustering on, auto buffers       | Tree size/power ↔ skew; `-buf_list` pins the masters                                         | [08](../steps/08_pnr_cts.md) |
| `DONT_USE` list | script | fractional drives, `SDF*`, `ICG*` | What repair/CTS may *not* insert or swap to; relaxing `ICG*` would allow clock-gate resizing | [08](../steps/08_pnr_cts.md) |

## Routing

| Knob                  | Level  | Default | Effect                                                                                       | Doc                                                               |
| --------------------- | ------ | ------- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `MIN/MAX_ROUTE_LAYER` | script | M2/M7   | Signal layer window: capacity ↔ stack cost/reservations                                      | [09](../steps/09_pnr_route.md)                                    |
| layer adjustment      | script | 0.25    | Global-plan capacity haircut. ↑ = safer detailed routing, longer wires                       | [09](../steps/09_pnr_route.md)                                    |
| congestion iterations | script | 30      | Negotiation effort on marginal designs                                                       | [09](../steps/09_pnr_route.md)                                    |
| `PNR_THREADS`         | make   | 0 (all) | Parallelism. ↑ = faster routing, higher memory peak — the memory relief valve is lowering it | [05](../steps/05_pnr_overview.md), [09](../steps/09_pnr_route.md) |

## Finishing and outputs

| Knob             | Level  | Default        | Effect                                               | Doc                               |
| ---------------- | ------ | -------------- | ---------------------------------------------------- | --------------------------------- |
| `FILL_CELLS`     | script | filler + decap | Decap share: supply-noise margin ↔ leakage           | [10](../steps/10_pnr_final.md)    |
| extraction rules | script | platform file  | Parasitic accuracy (calibrated per technology)       | [10](../steps/10_pnr_final.md)    |
| `PNR_STEP`       | make   | all            | Full clean run vs single-stage rerun from checkpoint | [05](../steps/05_pnr_overview.md) |

## Hierarchical mode

| Knob              | Default | Effect                                                                 | Doc                                         |
| ----------------- | ------- | ---------------------------------------------------------------------- | ------------------------------------------- |
| `MACRO_DIRS`      | none    | The master switch: binds hardened runs as macros in pnr and post-pnr-* | [hierarchical](../concepts/hierarchical.md) |
| `FLOORPLAN`       | none    | The macro-placement file — where component positions are decided       | [hierarchical](../concepts/hierarchical.md) |
| `cut_rows` halo   | 1 µm    | Macro keep-out ↔ lost placement area                                   | [hierarchical](../concepts/hierarchical.md) |
| block `CORE_UTIL` | 40      | Hardening density: block routability ↔ parent area/power               | [hierarchical](../concepts/hierarchical.md) |

## The classic ladders

Recurring multi-knob procedures, for orientation:

- **Congestion / routing DRCs**: `PLACE_DENSITY` down → `CORE_UTIL` down → layer adjustment up → floorplan rework (shape, pins, macros).
- **Setup closure**: `CLK_PERIOD_NS` up (accept slower) — or hold the target and work the implementation: density/placement modes, CTS tuning, and (beyond this flow's defaults) VT mixing and post-route optimization.
- **Memory ceiling**: `PNR_THREADS` down → hierarchical decomposition ([hierarchical](../concepts/hierarchical.md)).
- **Power reduction**: utilization up (shorter wires), clock gating (architectural), decap/leakage balance, frequency/voltage outside the flow's scope.

Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
