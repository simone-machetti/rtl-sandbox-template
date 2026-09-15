# Hierarchical place-and-route — hard macros

The mechanism that breaks the size wall: implement a block once, freeze it, and reuse the frozen layout as a component — a *hard macro* — inside a larger design. This document collects the whole mechanism, whose hooks are spread across synthesis, every P&R stage, and the post-P&R analyses.

## Inputs and outputs

- **Spans**: `make syn` (`LINK_BLACKBOXES`), `make pnr` (`MACRO_DIRS`, `FLOORPLAN`, `PDN`), and all three `post-pnr-*` steps (`MACRO_DIRS`).
- **Consumes**: per hardened block, the three views every P&R run already emits — `abstract.lef`, `timing_model.lib`, `design.gds` — plus its routed `netlist.v` and `netlist.spef` for simulation/power.
- **Produces**: a parent layout containing the blocks as placed, routed-around, powered fixed objects, merged to a single final GDS.

## Theory

### Why hierarchy

Three forces push implementation hierarchical: **capacity** — flat P&R runtime and memory grow superlinearly with instance count, and a machine that routes half a million instances comfortably may simply not fit five million; **reuse** — a tile instantiated N times deserves one implementation, not N identical efforts (and gets *identical* physical characteristics per copy, which strengthens comparisons); **parallelism/ownership** — blocks implemented independently, integrated later. The price: boundaries. A frozen block's internals cannot be co-optimized with its surroundings, its abstraction hides information (see the caveats), and the parent inherits interface obligations (pin access, power connection).

### The two blackbox regimes

The flow's synthesis already had blackboxing ([01_syn.md](../steps/01_syn.md)) — but with the netlists *linked back* at the end: a logical-reuse device producing a self-contained netlist. Hierarchical P&R needs the opposite: the parent netlist must keep the blackboxed modules **empty**, because OpenROAD resolves an instance whose module has no definition against the loaded LEF/liberty *by name* — that unresolved-ness is the binding mechanism. One flag separates the regimes: `LINK_BLACKBOXES=0`.

### What each abstract carries

- **`abstract.lef`** — the physical contract: outline, boundary pin shapes/layers (including power pins — the block's top PDN straps exported at the boundary), and obstruction geometry summarizing the interior. The parent places it, cuts rows under it, routes to its pins and around its body.
- **`timing_model.lib`** — the timing contract: port-to-port arcs, setup/hold requirements at input pins, clock-to-output arcs with the internal tree latency folded in. The parent's timer prices paths *through* the block without seeing inside. Not included: power tables ([14_post_pnr_dpa.md](../steps/14_post_pnr_dpa.md)) and SI/aggressor information.
- **`design.gds`** — the geometric truth, substituted at the parent's GDS merge.

### The parent's special duties

Three things a parent flow must do that a flat flow doesn't: **place the macros** (a deliberate act — macro positions encode dataflow, so this flow makes them an explicit user file rather than an optimizer guess), **cut rows and keep halos** (no standard cell may sit under or hug a macro), and **power the macros** (the PDN must land on the blocks' power pins — a layer-matching exercise between the parent grid and the block's exported straps).

## Implementation walkthrough

The hooks, in pipeline order — each quoted from its home script.

**Synthesis** (`scripts/syn/run.tcl`): the stubs stay empty when requested.

```tcl
if {$env(SEL_LINK_BLACKBOXES) ne "0"} {
    foreach mod $blackbox_modules {
        yosys "read_verilog $imp_dir/$mod/output/netlist.v"
    }
}
```

**P&R context** (`scripts/pnr/init_tech.tcl`): every stage loads the blocks' timing models (liberty is per-process), and the PDN default switches to the macro-aware strategy.

```tcl
if {$::env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $::env(SEL_MACRO_DIRS) {
        read_liberty $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$dir/output/timing_model.lib
    }
}
```

```tcl
if {$::env(SEL_PDN) ne "none"} {
    set PDN_CFG $::env(SEL_PDN)
} elseif {$::env(SEL_MACRO_DIRS) ne "none"} {
    set PDN_CFG $::env(REPO_HOME)/scripts/pnr/pdn_macro.tcl
} else {
    set PDN_CFG $::env(ASAP7_HOME)/openRoad/pdn/grid_strategy-M1-M2-M5-M6.tcl
}
```

**Floorplan** (`scripts/pnr/1_floorplan.tcl`): the abstracts join the physical library, and the user's placement file runs, followed by row cutting.

```tcl
if {$::env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $::env(SEL_MACRO_DIRS) {
        read_lef $::env(REPO_HOME)/projects/$::env(SEL_PROJECT)/imp/$dir/output/abstract.lef
    }
}
```

```tcl
if {$::env(SEL_FLOORPLAN) ne "none"} {
    set fp_file $::env(SEL_FLOORPLAN)
    if {[file pathtype $fp_file] ne "absolute"} {
        set fp_file $::env(REPO_HOME)/$fp_file
    }
    source $fp_file
    cut_rows -halo_width_x 1 -halo_width_y 1
}
```

The `FLOORPLAN` file is project-owned and minimal — one line per macro instance:

```tcl
place_macro -macro_name <instance_name> -location {<x> <y>} -orientation R0
```

(coordinates in µm, orientations `R0 R90 R180 R270 MX MY MXR90 MYR90`; for a grid of tiles the file is naturally a generated loop). `cut_rows` then removes standard-cell rows under each macro plus a 1 µm halo, protecting pin access.

**PDN** (`scripts/pnr/pdn_macro.tcl`, macro grid section): the layer-matching duty. Blocks hardened by this flow export their **M6** power straps as PG pins, so the parent grid's M5 straps are dropped onto them:

```tcl
define_pdn_grid -name {MacroGrid} -voltage_domains {CORE} -macro -default -halo {2.0 2.0 2.0 2.0}
add_pdn_connect -grid {MacroGrid} -layers {M5 M6}
```

(The platform's default strategy instead assumes SRAM-style M4 pins — its macro grid finds no shapes on our blocks and `pdngen` aborts; the layer pair must match what the block actually exports. The rest of `pdn_macro.tcl` is the standard grid of [06_pnr_floorplan.md](../steps/06_pnr_floorplan.md).)

**GDS merge** (`scripts/pnr/6_gds.sh`): each block's abstract joins the reader setup and its GDS joins the merge, as quoted in [11_pnr_gds.md](../steps/11_pnr_gds.md) — the final GDS contains the blocks' real polygons.

**Analyses**: STA loads the timing models ([13_post_pnr_sta.md](../steps/13_post_pnr_sta.md)); gate-level simulation compiles the blocks' routed netlists ([12_post_pnr_sim.md](../steps/12_post_pnr_sim.md)); power analysis goes full-view — block netlists linked, per-instance SPEF, per-macro report ([14_post_pnr_dpa.md](../steps/14_post_pnr_dpa.md)).

### The recipe, end to end

```bash
# 1. Harden each block (a plain flat run of the block)
make pnr TOP_LEVEL=<block> CLK_PERIOD_NS=<t> OUT_DIR=<block_pnr> NETLIST_DIR=<block_syn>

# 2. Parent synthesis with empty stubs
make syn TOP_LEVEL=<top> CLK_PERIOD_NS=<t> OUT_DIR=<top_syn> \
    BLACKBOX_MODULES="<block> ..." LINK_BLACKBOXES=0

# 3. Parent P&R with macros
make pnr TOP_LEVEL=<top> CLK_PERIOD_NS=<t> OUT_DIR=<top_pnr> NETLIST_DIR=<top_syn> \
    MACRO_DIRS="<block_pnr> ..." FLOORPLAN=<path/to/floorplan.tcl>

# 4. Analyses, all with the same MACRO_DIRS
make post-pnr-sim ... NETLIST_DIR=<top_pnr> MACRO_DIRS="<block_pnr> ..." VCD=1
make post-pnr-sta ... NETLIST_DIR=<top_pnr> MACRO_DIRS="<block_pnr> ..."
make post-pnr-dpa ... NETLIST_DIR=<top_pnr> VCD_DIR=... MACRO_DIRS="<block_pnr> ..."
```

Combinational blocks harden cleanly (the CTS stage skips itself for clockless designs — [08_pnr_cts.md](../steps/08_pnr_cts.md)); clocked blocks carry their own internal tree, and the parent's CTS reaches only their clock *pin*.

## Design space

- **Hardening utilization**: the block's `CORE_UTIL` at hardening sets its footprint forever. Low utilization eases the block's own routing but pays rent in the parent — area and measurably higher wire power ([06_pnr_floorplan.md](../steps/06_pnr_floorplan.md)'s notes). Blocks meant for dense tiling deserve the highest utilization they close at.
- **Pin planning**: a block's pin placement quality becomes the *parent's* routing problem multiplied by instance count. Constraining block pins (edges, layers, ordering) to match the parent's dataflow is the natural refinement (`place_pins` options at hardening time).
- **Depth**: the mechanism composes — a hardened parent is itself macro-ready (its run emits the same three views). Multi-level hierarchies need only discipline in directory bookkeeping.
- **Abutment**: the zero-channel style (tiles touching, pins aligned edge-to-edge) eliminates parent routing between neighbors but demands pin-position contracts this flow doesn't yet automate; halo'd placement with parent routing is the general-purpose mode implemented.
- **Soft vs hard**: the alternative regime — *soft* hierarchy, boundaries kept logical but implementation flat — trades reuse and capacity for cross-boundary optimization. The synthesis `KEEP_MODULES`/`BLACKBOX_MODULES` modes without `LINK_BLACKBOXES=0` support exactly that study.

## Knobs

| Knob              | Where                  | Default | Effect / tradeoff                                          |
| ----------------- | ---------------------- | ------- | ---------------------------------------------------------- |
| `LINK_BLACKBOXES` | make (syn)             | 1       | `0` = macro-ready stubs; `1` = self-contained netlist      |
| `MACRO_DIRS`      | make (pnr, post-pnr-*) | none    | The hardened blocks to bind — the mode's master switch     |
| `FLOORPLAN`       | make (pnr)             | none    | The macro-placement file (repo-root-relative or absolute)  |
| `PDN`             | make (pnr)             | auto    | Override when the macro grid needs a different layer match |
| `cut_rows` halo   | `1_floorplan.tcl`      | 1 µm    | Macro keep-out vs lost placement area                      |
| block `CORE_UTIL` | make (block's pnr)     | 40      | The hardening-density tradeoff described above             |

## Notes and caveats

- **The abstract-DRC artifact**: detailed routing against abstracts can leave a few `Lef58EolKeepOut` markers at macro pins in the parent's `route_drc.rpt`. Diagnosis: the router's wire end faces an obstruction shape that is, in reality, the *same net's* continuation inside the block — the abstract cannot express "this OBS is my pin's own net". The markers are translation-invariant (they move with the macro) and insensitive to pin depth; coarse-obstruction abstracts are not a fix (full-layer covers block the parent PDN's via stacks). They are false positives: the merged GDS metal is continuous there.
- **`place_macro` self-overlap**: re-placing an already-placed macro at an overlapping location errors ("overlap with other macros: itself"); in interactive sessions, unplace first or move in two hops. The flow never hits it — stage 1 always starts from an unplaced floorplan.
- **Power abstraction**: `timing_model.lib` has no power tables — the reason parent DPA links real netlists ([14_post_pnr_dpa.md](../steps/14_post_pnr_dpa.md)). A parent STA, by contrast, is complete with the timing models alone.
- **Boundary optimization stops at the wall**: paths through a macro use its frozen arcs; the parent can buffer *up to* the pins only. Generous input margins at hardening time are the block designer's courtesy to the integrator.
- The block-and-parent runs must stay consistent: re-hardening a block invalidates the parent (abstract, timing, GDS all change) — rerun from parent P&R onward.

## Commercial perspective

This is the classic **hierarchical/block-based** methodology of every large SoC: blocks hardened with ILM/ETM timing abstracts and LEF physical abstracts, assembled by a top-level flow that places macros, builds the shared PDN, and closes boundary timing; power via block models or flattened analysis. Commercial suites add machinery this flow does without — automatic macro placers, boundary-timing budgeting tools, abstract generators with pin-net awareness (avoiding the DRC artifact above), and formal interface checks — but the contract (LEF + timing model + GDS per block, name-bound at the parent) is exactly the one implemented here.

Source: [run.tcl](../../syn/run.tcl) — [init_tech.tcl](../../pnr/init_tech.tcl) — [1_floorplan.tcl](../../pnr/1_floorplan.tcl) — [pdn_macro.tcl](../../pnr/pdn_macro.tcl) — [6_gds.sh](../../pnr/6_gds.sh) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
