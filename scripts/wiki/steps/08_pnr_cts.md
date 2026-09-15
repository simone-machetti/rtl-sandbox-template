# P&R stage 3 — Clock-tree synthesis

Until now the clock has been a fiction — an ideal signal arriving everywhere at once. CTS builds the physical network that actually delivers it: a tree of buffers from the clock port to every flop's clock pin. From this stage on, timing uses the *real* clock.

## Inputs and outputs

- **Inputs**: `output/2_place.odb` (+ re-applied context).
- **Outputs**: `output/3_cts.odb` — clock tree built, clocks propagated, setup repaired — and `report/3_cts.rpt`.

## Theory

### Why a tree

A clock net drives thousands of flip-flop clock pins — electrically impossible from one driver, so it must be buffered; and *how* it is buffered defines two quantities that dominate sequential timing:

- **Insertion delay** (latency): the delay from clock source to a flop's clock pin — typically ~100 ps for small blocks, growing with die size. Shared latency mostly cancels in setup checks between same-tree flops, but shows up at boundaries and in any analysis that mixes ideal and propagated domains ([02_constraints.md](../concepts/constraints.md)'s hold-artifact discussion).
- **Skew**: the *difference* in insertion delay between two flops. Setup skew (capture later than launch) can help or hurt; hold violations are *created* by skew — which is why hold repair only makes sense after CTS.

CTS algorithms cluster nearby sinks, place buffers to drive each cluster, and recursively build levels upward, balancing the branches so all sinks see similar latency. The classic geometric ideal is the H-tree; practical tools use clustered balancing driven by the placement.

### Clock gates in the tree

An **integrated clock gate** (ICG) — a latch-plus-AND cell that stops the clock to a region when idle — is a *node* of the clock network: the tree runs source → buffers → ICG → more buffers → flops. CTS must recognize ICGs (liberty marks them) and balance *through* them. Gating cells present in the netlist are honored; the flow's `set_dont_use ICG*` only prevents optimization engines from *inserting* new ones — clock gating stays an architectural decision, not a tool improvisation.

### After the tree: propagated clocks and the timing shift

Once the tree exists, `set_propagated_clock` switches analysis from ideal to measured arrival times. Consequences: insertion delay becomes visible in reports (the "clock network delay (propagated)" line), skew starts affecting every check, and **hold analysis becomes meaningful** — CTS is therefore always followed by re-repair: first setup here (the tree perturbed placement and added load), hold later with routed parasitics ([09_pnr_route.md](09_pnr_route.md)).

## Implementation walkthrough

`scripts/pnr/3_cts.tcl`:

```tcl
source $::env(REPO_HOME)/scripts/pnr/init_tech.tcl
source $::env(REPO_HOME)/scripts/pnr/checkpoint.tcl
source $::env(REPO_HOME)/scripts/pnr/reports.tcl

load_checkpoint 2_place
```

Standard prologue, placed design in.

```tcl
# -----------------------------------------------------------------------------
# Clock tree synthesis (skipped for clockless designs)
# -----------------------------------------------------------------------------
if {[llength [get_ports -quiet clk_i]] > 0} {
    repair_clock_inverters
    clock_tree_synthesis -sink_clustering_enable -repair_clock_nets
    set_propagated_clock [all_clocks]
}
```

The guard mirrors the constraint scheme's convention: no `clk_i` port → a combinational block → no tree to build (essential for hardening combinational hard macros — the stage degrades to a legalization/report pass instead of erroring).

Inside: `repair_clock_inverters` normalizes inverter pairs on the clock path so the tree builder sees clean polarity. `clock_tree_synthesis` builds the tree — `-sink_clustering_enable` groups nearby sinks under shared leaf buffers (smaller, lower-power trees), `-repair_clock_nets` fixes long root connections while building. No explicit buffer list is passed: the tool selects from the loaded liberty, and the `set_dont_use` blacklist (no fractional drives, no ICG insertion) bounds its choices. Then the switch: `set_propagated_clock [all_clocks]` — from here to the end of the flow, real arrival times. (The virtual clock, having no pins, is unaffected; the tool notes it with a benign warning.)

```tcl
# -----------------------------------------------------------------------------
# Post-CTS timing repair
# -----------------------------------------------------------------------------
estimate_parasitics -placement
repair_timing -setup
```

Fresh parasitics (the tree added cells and displaced others), then **setup repair**: resizing, buffering, pin-swapping and load-splitting on violating paths — the first timing repair of the flow, now that launch/capture use real clock arrivals. Hold is deliberately *not* repaired yet: hold buffers inserted against placement-estimated wires would be mis-sized; routing's real parasitics come first.

```tcl
# -----------------------------------------------------------------------------
# Legalization
# -----------------------------------------------------------------------------
detailed_placement
check_placement -verbose

report_stage 3_cts
save_checkpoint 3_cts
```

The tree's buffers and repair's cells are legalized into the rows, the invariant is checked, and the stage closes with the standard snapshot — whose WNS is the first *real-clock* timing number of the run.

## Design space

- **Buffer selection**: pinning the tree to explicit masters (`-buf_list`, `-root_buf`) trades the tool's freedom for predictability; leaving it free (this flow) matches reference-flow practice and adapts to the library.
- **Skew targeting**: bounded-skew CTS is the default goal; **useful skew** deliberately *unbalances* the tree to donate time to critical paths — powerful, and coupled tightly to setup optimization.
- **Tree topology**: buffered clustered trees (here) vs H-trees/fishbones (regular, low-skew, higher power) vs **clock meshes** (shorted grid — lowest skew, highest power, standard for CPUs).
- **Clock routing rules**: production flows route clocks with widened/shielded wires (NDRs — non-default rules) for SI immunity; this flow's clock nets use standard rules on the restricted layer window ([09_pnr_route.md](09_pnr_route.md): clock min-layer M4).
- **ICG sizing**: with `ICG*` blacklisted the resizer cannot up-size an overloaded clock gate (the library offers a full size family); a design whose gated-clock nets fail repair would motivate relaxing that entry for this stage.
- **Multi-corner CTS**: balancing trees across corners is the signoff-grade refinement; single-corner TT here.

## Knobs

| Knob                 | Where           | Default       | Effect / tradeoff                                            |
| -------------------- | --------------- | ------------- | ------------------------------------------------------------ |
| `CLK_UNCERTAINTY_PS` | make            | 0             | Margin available to CTS-era setup repair                     |
| `MIN_CLK_LAYER`      | `init_tech.tcl` | M4            | Clock wires' lowest layer — RC quality of the tree's routing |
| CTS options          | `3_cts.tcl`     | clustering on | Tree size/power vs skew fine-tuning (`-buf_list`, targets)   |

## Notes and caveats

- The clockless guard makes this stage safe for combinational blocks — a property the hierarchical flow depends on ([18_hierarchical.md](../concepts/hierarchical.md)).
- ICG cells present in the netlist are fully honored as clock-tree nodes; `set_dont_use ICG*` restricts only tool-initiated insertion/swap. The residual effect — no automatic ICG up-sizing — is a deliberate conservatism.
- Expect this stage's report to show *worse* WNS than stage 2's before repair wins some back: propagated clocks re-price every path (insertion delay asymmetries, real tree load). That step down is bookkeeping honesty, not regression.
- The "virtual clock can not be propagated" warning is expected and harmless.
- Clock power is real power: the tree's buffers show up as the "Clock" row of every subsequent power report — one of the reasons gating exists.

## Commercial perspective

Commercial CTS (`ccopt` in Innovus — "concurrent clock and datapath optimization") merges tree building with useful-skew setup optimization in one engine, applies NDR routing rules to clocks natively, and balances across all corners simultaneously. The structure here — build balanced tree, propagate, repair setup — is the same loop with the concurrency unrolled into visible steps.

Source: [3_cts.tcl](../../pnr/3_cts.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
