# Example

A small registered multiply-accumulate that exercises every step of the shared EDA flow — simulation, synthesis, the post-synthesis analyses, place-and-route, the post-place-and-route analyses — including hierarchical place-and-route with a hard macro. It is the template's reference project: copy its layout, testbench contract and documentation style for your own design, then delete it.

This project plugs into the repository-level EDA flow. See the [root README](../../README.md) for the `make` targets, their generic parameters, and the typical pipeline. This document covers the parts specific to `example`.

## Quick start

```bash
source ../../sourceme.sh   # or: source sourceme.sh from the repository root

make sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_top_example
```

`example` is selected with `PROJECT=example` on every `make` command. The [walkthrough](#walkthrough-the-complete-flow) below lists the exact commands that validated the template end to end, with their run times and reference results.

## Design

```
top_example                     registered wrapper, 2-cycle latency
├── reg_n ×3                    input registers: a lanes, b lanes, signedness flags
├── mac_n                       combinational core — the hard macro in the hierarchical run
│   ├── mul_n ×LANES            WIDTH_A × WIDTH_B multiplier, runtime signedness per operand
│   └── add_tree_n              balanced adder tree, ceil(log2(LANES)) levels
│       └── add_n ×(LANES−1)    two-input modular adder
└── reg_n                       output register
```

`out_o = Σ_k a_i[k] · b_i[k]`, exact, with each operand read as signed or unsigned per its flag. At the default shape (4 lanes of 8 × 8 bits) the result is 19 bits wide. The design is documented module by module in the [wiki](wiki/index.md): [top_example](wiki/architectures/top_example.md), [mac_n](wiki/modules/mac_n.md), [mul_n](wiki/modules/mul_n.md), [add_tree_n](wiki/modules/add_tree_n.md), [add_n](wiki/modules/add_n.md), [reg_n](wiki/modules/reg_n.md).

## Top-level modules

| `TOP_LEVEL`   | Testbench        | Description                                                                                            |
| ------------- | ---------------- | ------------------------------------------------------------------------------------------------------ |
| `top_example` | `tb_top_example` | The registered wrapper; the top-level of every flat run and of the hierarchical parent run.            |
| `mac_n`       | `tb_mac_n`       | The combinational core on its own; synthesized and hardened as the hard macro of the hierarchical run. |

Any module of the hierarchy can be given as `TOP_LEVEL` to `make syn`; only these two have a testbench.

## RTL elaboration parameters

Passed as `PARAMS="KEY=VAL ..."` to `make sim`, `make syn` and the gate-level simulations. In simulation they reach the testbench and, through it, the DUT; in synthesis they reach the top-level directly.

| Key        | Default | Applies to                           | Description                                                 |
| ---------- | ------- | ------------------------------------ | ----------------------------------------------------------- |
| `LANES`    | `4`     | `top_example`, `mac_n`, both benches | Number of multiply lanes accumulated into the result.       |
| `WIDTH_A`  | `8`     | `top_example`, `mac_n`, both benches | Bit width of each `a` operand.                              |
| `WIDTH_B`  | `8`     | `top_example`, `mac_n`, both benches | Bit width of each `b` operand.                              |
| `NUM_RAND` | `2000`  | both benches                         | Number of random vectors before the directed corner sweeps. |

A gate-level netlist has a fixed shape, so `post-syn-sim` / `post-pnr-sim` must use the values the netlist was synthesized with (the defaults, unless `make syn` was given the same `PARAMS`).

```bash
make sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_top_example_8x4 PARAMS="LANES=8 WIDTH_B=4"
```

## Testbenches

Both benches are self-checking against an exact 64-bit golden, stop with a fatal error on the first mismatch, name their DUT instance `dut`, dump `activity.vcd` when compiled with `VCD=1`, and carry a `POST_SYN_SIM` branch that instantiates the netlist through its flattened array ports.

| Testbench        | DUT           | What it does                                                                                                                                                                                                                                                                      |
| ---------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tb_top_example` | `top_example` | Streams a fresh corner-biased operand set with random signedness every clock and checks the registered result against a golden delayed by the 2-cycle latency; ends with directed extremes under all four signedness combinations. [Details](wiki/testbenches/tb_top_example.md). |
| `tb_mac_n`       | `mac_n`       | Clockless: every random or directed vector is checked under all four signedness combinations. [Details](wiki/testbenches/tb_mac_n.md).                                                                                                                                            |

## Walkthrough: the complete flow

The sequence below is what validated the template. Technology is ASAP7 (RVT, TT corner) with a 1.5 ns clock; every command is run from the repository root after `source sourceme.sh`. Output directories follow one naming rule — `<step>_<top>` — so each step's `NETLIST_DIR` / `VCD_DIR` names the run it consumes.

### Flat: `top_example` end to end

```bash
# 1. RTL simulation (both benches, plus one parameter override)
make sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_top_example
make sim PROJECT=example TOP_LEVEL=mac_n       CLK_PERIOD_NS=1.5 OUT_DIR=sim_mac_n
make sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_top_example_8x4 PARAMS="LANES=8 WIDTH_B=4"

# 2. Synthesis (flat, and once more with every module boundary kept for a per-module area report)
make syn PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=syn_top_example
make syn PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=syn_top_example_keep KEEP_HIERARCHY=1

# 3. Post-synthesis: gate-level simulation (dumps the VCD), timing, power
make post-syn-sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_post_syn_top_example NETLIST_DIR=syn_top_example VCD=1
make post-syn-sta PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sta_post_syn_top_example NETLIST_DIR=syn_top_example
make post-syn-dpa PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=dpa_post_syn_top_example NETLIST_DIR=syn_top_example VCD_DIR=sim_post_syn_top_example

# 4. Place-and-route, with the boundary pins placed by the project pin plan
make pnr PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=pnr_top_example NETLIST_DIR=syn_top_example PINS=projects/example/scripts/pins_top_example.tcl

# 5. Post-place-and-route: gate-level simulation of the routed netlist, timing and power with parasitics
make post-pnr-sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_post_pnr_top_example NETLIST_DIR=pnr_top_example VCD=1
make post-pnr-sta PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sta_post_pnr_top_example NETLIST_DIR=pnr_top_example
make post-pnr-dpa PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=dpa_post_pnr_top_example NETLIST_DIR=pnr_top_example VCD_DIR=sim_post_pnr_top_example
```

Reference results of this sequence (wall-clock times on one desktop machine, all cores):

| Step                     | Time | Result                                                                                                                                                                                           |
| ------------------------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sim` × 3                | 5 s  | All three benches `PASSED` (2000 random + corner vectors each).                                                                                                                                  |
| `syn`                    | 3 s  | 3421 cells, 322.03 µm².                                                                                                                                                                          |
| `syn` `KEEP_HIERARCHY=1` | 8 s  | Per-module `report/area.rpt`: `mac_n` 272.56 µm² (4 × `mul_n` 62.56, `add_tree_n` 22.31 = 3 × `add_n` 7.44), `reg_n` 15.86 / 15.86 / 9.42 / 0.87; top 314.58 µm² with every boundary kept.       |
| `post-syn-sim` `VCD=1`   | 14 s | `PASSED`; 11119 pins annotated, 0 unannotated.                                                                                                                                                   |
| `post-syn-sta`           | 1 s  | WNS 0, worst slack +415.8 ps (ideal wires).                                                                                                                                                      |
| `post-syn-dpa`           | 2 s  | 0.499 mW total (45.8 % internal, 54.1 % switching).                                                                                                                                              |
| `pnr`                    | 78 s | 329 µm² design area at 41 % utilization; WNS 0, worst slack +540.4 ps; `route_drc.rpt` empty; 5.0 ps setup clock skew; `design.gds` 3.6 MB; operands on the left/top edges, result on the right. |
| `post-pnr-sim` `VCD=1`   | 7 s  | `PASSED` on the routed netlist; 11246 pins annotated, 0 unannotated.                                                                                                                             |
| `post-pnr-sta`           | 2 s  | WNS 0, worst slack +540.4 ps with SPEF parasitics and propagated clocks.                                                                                                                         |
| `post-pnr-dpa`           | 2 s  | 0.610 mW total, of which the clock tree 8.7 %.                                                                                                                                                   |

The same sequence at `CLK_PERIOD_NS=1.0` still closes after place-and-route (repair leaves +70 ps), but the post-synthesis netlist alone violates by about 110 ps, which is why the reference period is 1.5 ns.

### Hierarchical: `mac_n` as a hard macro

The core is implemented once on its own, then the parent is synthesized with `mac_n` left as an empty stub and implemented with the hardened block bound as a macro. [floorplan_top_example.tcl](scripts/floorplan_top_example.tcl) places the macro: it looks up the single `mac_n` instance and its size from the design and centers it in the core, so it needs no edit when the block is re-hardened at another size. Two pin plans fix the boundaries: [pins_mac_n.tcl](scripts/pins_mac_n.tcl) puts the block's A operands on its left edge, the B operands and sign controls on the top, the result on the right, each bus in bit order; [pins_top_example.tcl](scripts/pins_top_example.tcl) gives the parent the same edges plus clock and reset on the top, so the input and output registers sit between the boundary and the block they feed. The block is hardened with its routing capped at M5 and the tile PDN, which exposes its M5 straps as power pins and leaves M6 and M7 to the parent's mesh and routing over the macro. The post-place-and-route analyses take the same `MACRO_DIRS` and see the block in full.

One naming rule applies here: `BLACKBOX_MODULES=<mod>` looks for the block's synthesized netlist in `imp/<mod>_syn/` (or `imp/<mod>/`), so the core's synthesis run is named `mac_n_syn`; its place-and-route run can carry any name, since `MACRO_DIRS` is given explicitly.

```bash
# 1. Harden the core: routing capped at M5, the tile PDN (M5 power pins, M6/M7 free for the parent) and the block's pin plan
make syn PROJECT=example TOP_LEVEL=mac_n CLK_PERIOD_NS=1.5 OUT_DIR=mac_n_syn
make pnr PROJECT=example TOP_LEVEL=mac_n CLK_PERIOD_NS=1.5 OUT_DIR=mac_n_pnr NETLIST_DIR=mac_n_syn \
    MAX_ROUTE_LAYER=M5 PDN=scripts/pnr/pdn_tile.tcl PINS=projects/example/scripts/pins_mac_n.tcl

# 2. Synthesize the parent with an empty mac_n stub, then place-and-route it around the macro with its own pin plan
make syn PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=syn_top_example_hier BLACKBOX_MODULES=mac_n LINK_BLACKBOXES=0
make pnr PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=pnr_top_example_hier NETLIST_DIR=syn_top_example_hier \
    MACRO_DIRS=mac_n_pnr FLOORPLAN=projects/example/scripts/floorplan_top_example.tcl PINS=projects/example/scripts/pins_top_example.tcl

# 3. Post-place-and-route analyses of the assembled design
make post-pnr-sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_post_pnr_top_example_hier NETLIST_DIR=pnr_top_example_hier MACRO_DIRS=mac_n_pnr VCD=1
make post-pnr-sta PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sta_post_pnr_top_example_hier NETLIST_DIR=pnr_top_example_hier MACRO_DIRS=mac_n_pnr
make post-pnr-dpa PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=dpa_post_pnr_top_example_hier NETLIST_DIR=pnr_top_example_hier MACRO_DIRS=mac_n_pnr VCD_DIR=sim_post_pnr_top_example_hier
```

Reference results of this sequence:

| Step                               | Time | Result                                                                                                                                                                                            |
| ---------------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `syn` `mac_n`                      | 3 s  | 285.24 µm² standalone.                                                                                                                                                                            |
| `pnr` `mac_n` `MAX_ROUTE_LAYER=M5` | 46 s | 285 µm² at 40 % utilization; WNS 0, worst slack +718.9 ps; `route_drc.rpt` empty; pins on the planned edges; emits `abstract.lef` (obstructions on M1–M5 only), `timing_model.lib`, `design.gds`. |
| `syn` parent, `mac_n` stubbed      | 2 s  | 42.14 µm² — the registers and glue only; `mac_n` stays an empty module in the netlist.                                                                                                            |
| `pnr` parent with the macro        | 72 s | 993 µm² design area (macro footprint included) at 41 % utilization; WNS 0, worst slack +556.2 ps; `route_drc.rpt` empty.                                                                          |
| `post-pnr-sim` `VCD=1`             | 8 s  | `PASSED` with the block's routed netlist compiled in full; 10857 pins annotated, 0 unannotated.                                                                                                   |
| `post-pnr-sta`                     | 2 s  | WNS 0, worst slack +556.2 ps through the macro's timing model.                                                                                                                                    |
| `post-pnr-dpa`                     | 2 s  | 0.694 mW total in full-view mode; `power_macros.rpt` attributes 0.425 mW to `mac_n_i`.                                                                                                            |

### Cleanup

```bash
make clean-all PROJECT=example      # removes projects/example/sim and projects/example/imp
```

## Experiments (automation scripts)

_None yet._ [scripts/](scripts/) holds the macro floorplan file and the two pin plans. Add sweeps and generators directly under `scripts/`, run directly with `bash` / `python`.
