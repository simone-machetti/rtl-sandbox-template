# RTL Sandbox Template

A GitHub template for RTL research projects. It ships a complete open-source ASIC flow — Verilator simulation, Yosys synthesis, OpenROAD place-and-route, OpenSTA timing and dynamic power, on the ASAP7 predictive PDK — that is project-agnostic and lives at the repository root, plus a `projects/` folder where each design sits under `projects/<name>/`. Create your own repository from the template, add a project, and drive it with `make <target> PROJECT=<name>`; the flow itself never needs editing.

Projects:

- [`example`](projects/example/README.md) — a small registered multiply-accumulate (`top_example`) that exercises every step of the flow, including hierarchical place-and-route with a hard macro. It is the reference for the project layout, the testbench contract and the documentation conventions; copy its structure for your own design.

This README documents the shared EDA flow: the `make` targets, their parameters, and the typical pipeline. For a project's designs, top-levels, RTL parameters, and experiments, see that project's own README. The flow is also documented step by step in [scripts/asic_flow.md](scripts/asic_flow.md) (inputs, outputs and parameters per step) and taught in depth by the [flow course](scripts/wiki/index.md) under `scripts/wiki/`.

## Using this template

Create a new repository from it — the copy gets the files with a fresh history, no link back to this repository, and whatever visibility you choose:

- On GitHub: **Use this template → Create a new repository** on the template's page.
- From the terminal, with the [GitHub CLI](https://cli.github.com/):

  ```bash
  gh repo create my-design --template simone-machetti/rtl-sandbox-template --private --clone
  cd my-design
  ```

Then set up the [environment](#environment-setup) once and check the tools with the example project:

```bash
source sourceme.sh
make sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_top_example
```

Add your own project next to `projects/example/` (or replace it) and register it in the `Projects:` list above. Keep `scripts/`, `Makefile` and `sourceme.sh` as they are: they contain no project-specific names, so later template improvements merge cleanly.

### Pulling template updates

A repository created from a template has no upstream. To receive later flow updates, add the template as a remote once and merge it; the first merge joins the two unrelated histories, every later one is a plain merge:

```bash
git remote add template https://github.com/simone-machetti/rtl-sandbox-template.git
git fetch template
git merge template/main --allow-unrelated-histories # first time only
git merge template/main                             # afterwards
```

## Cloning

A full clone is the default. Because every project sits in its own folder, a working copy can also carry only the projects you need — useful once a repository holds several large ones:

```bash
git clone --filter=blob:none --sparse git@github.com:<owner>/<repo>.git
cd <repo>
git sparse-checkout set scripts projects/<name>
```

Add another project later with `git sparse-checkout add projects/<other>`.

## Quick start

```bash
source sourceme.sh

# Pre-synthesis simulation
make sim PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name>

# Logic synthesis
make syn PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name>

# Post-synthesis gate-level simulation
make post-syn-sim PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-synthesis static timing analysis
make post-syn-sta PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-synthesis dynamic power analysis
make post-syn-dpa PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name> VCD_DIR=<name>

# Place-and-route
make pnr PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-place-and-route gate-level simulation
make post-pnr-sim PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-place-and-route static timing analysis
make post-pnr-sta PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name>

# Post-place-and-route dynamic power analysis
make post-pnr-dpa PROJECT=<project> TOP_LEVEL=<top_level> CLK_PERIOD_NS=1.0 OUT_DIR=<name> NETLIST_DIR=<name> VCD_DIR=<name>
```

`PROJECT` and `TOP_LEVEL` are required on every command — there is no default. See `projects/<project>/README.md` for the available `TOP_LEVEL` values and runnable examples; the [example project README](projects/example/README.md) walks the whole pipeline end to end.

## Repository structure

```
.
├── scripts/                  # Project-agnostic EDA flow scripts
│   ├── asic_flow.md          # Per-step reference: tool, inputs, outputs, parameters
│   ├── wiki/                 # Flow course: one page per pipeline step, concepts, knobs
│   ├── sim/                  # Pre-synthesis simulation flow
│   │   └── run.sh            # Verilator compile and run script
│   ├── syn/                  # Logic synthesis flow
│   │   ├── run.tcl           # Yosys top-level synthesis script (ASAP7)
│   │   ├── compile.tcl       # RTL read and elaboration script
│   │   └── abc.tcl           # ABC technology mapping script
│   ├── pnr/                  # Place-and-route flow (OpenROAD, ASAP7)
│   │   ├── run.sh            # Stage sequencer (one openroad process per stage)
│   │   ├── init_tech.tcl     # Liberty reads and ASAP7 technology settings
│   │   ├── checkpoint.tcl    # ODB checkpoint save/load helpers
│   │   ├── constraints.tcl   # Clock constraints from CLK_PERIOD_NS
│   │   ├── reports.tcl       # Per-stage timing/area report helper
│   │   ├── 1_floorplan.tcl   # Floorplan, tracks, pins, tie/tap cells, PDN
│   │   ├── 2_place.tcl       # Global and detailed placement
│   │   ├── 3_cts.tcl         # Clock tree synthesis
│   │   ├── 4_route.tcl       # Global and detailed routing
│   │   ├── 5_final.tcl       # Fillers, SPEF extraction, reports, final products
│   │   ├── 6_gds.sh          # DEF-to-GDS merge (KLayout)
│   │   ├── pdn_macro.tcl     # Macro-aware PDN strategy (hierarchical parent runs)
│   │   ├── pdn_tile.tcl      # PDN strategy for a block hardened as a hard macro
│   │   └── def2stream.py     # KLayout DEF/GDS streaming script (from ORFS)
│   ├── post-syn-sta/         # Post-synthesis static timing analysis flow
│   │   └── run.tcl           # OpenSTA timing analysis script
│   ├── post-syn-sim/         # Post-synthesis gate-level simulation flow
│   │   ├── run.sh            # Verilator compile and run script
│   │   ├── filelist.f        # Gate-level netlist and cell library filelist
│   │   └── asap7_seq_behav.v # Behavioural ASAP7 sequential cells for Verilator
│   ├── post-syn-dpa/         # Post-synthesis dynamic power analysis flow
│   │   └── run.tcl           # OpenSTA power analysis script
│   ├── post-pnr-sta/         # Post-place-and-route static timing analysis flow
│   │   └── run.tcl           # OpenSTA timing analysis script (netlist + SPEF)
│   ├── post-pnr-sim/         # Post-place-and-route gate-level simulation flow
│   │   ├── run.sh            # Verilator compile and run script
│   │   └── filelist.f        # Routed netlist and cell library filelist
│   └── post-pnr-dpa/         # Post-place-and-route dynamic power analysis flow
│       └── run.tcl           # OpenSTA power analysis script (netlist + SPEF)
├── projects/                 # One subfolder per RTL project
│   ├── example/              # The shipped reference project (see its README.md)
│   └── <name>/               # An RTL project (see its README.md)
│       ├── README.md         # Project-specific documentation
│       ├── rtl/              # SystemVerilog source modules
│       ├── tb/               # Verilator SV testbenches
│       ├── scripts/          # Project-specific scripts (sweeps, floorplans; run directly)
│       ├── wiki/             # Design-doc wiki (Obsidian vault)
│       ├── sim/              # Simulation outputs (generated)
│       └── imp/              # Synthesis/P&R/STA/DPA outputs (generated)
├── Makefile                  # Build system entry point (PROJECT=<name> selects project)
├── sourceme.sh               # Environment setup (sources ~/.bashrc, derives REPO_HOME)
└── LICENSE                   # Apache-2.0
```

All `make` targets require `PROJECT=<name>` to select the project they operate on (there is no default; targets fail fast if it is unset or names a project that does not exist). The flow scripts in `scripts/` resolve project-specific paths through the `SEL_PROJECT` env var exported by the Makefile.

## Environment setup

Tool and PDK install locations are **per-user**: you declare them in your `~/.bashrc`, and `sourceme.sh` sources that file and derives the rest. Run this once per shell before any `make` command:

```bash
source sourceme.sh
```

`sourceme.sh` sets `REPO_HOME` from its own location, sources `~/.bashrc`, then derives `ASAP7_HOME` from `PDK_HOME`. You therefore export only the install **roots** in your `~/.bashrc` — the shared flow itself is project- and machine-agnostic:

| Variable                                                                            | Purpose                                                                                          |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `EDA_HOME`                                                                          | Root holding the EDA tool installs.                                                              |
| `VERILATOR_HOME`, `YOSYS_HOME`, `YOSYS_SLANG_HOME`, `OPENSTA_HOME`, `OPENROAD_HOME` | Per-tool install dirs (conventionally `$EDA_HOME/<tool>`); each tool's `bin/` must be on `PATH`. |
| `PDK_HOME`                                                                          | Root holding the PDK trees — the ASAP7 liberty, verilog, LEF and GDS consumed by the flow.       |

A minimal `~/.bashrc` block — add this and adjust the two roots (`EDA_HOME` and `PDK_HOME`) to your machine:

```bash
# --- EDA tool binaries ---
export EDA_HOME=/opt/eda
export VERILATOR_HOME=$EDA_HOME/verilator
export YOSYS_HOME=$EDA_HOME/yosys
export YOSYS_SLANG_HOME=$EDA_HOME/yosys-slang
export OPENSTA_HOME=$EDA_HOME/opensta
export OPENROAD_HOME=$EDA_HOME/openroad
export PATH=$VERILATOR_HOME/bin:$YOSYS_HOME/bin:$YOSYS_SLANG_HOME/bin:$OPENSTA_HOME/bin:$OPENROAD_HOME/bin:$PATH

# --- PDK ---
export PDK_HOME=/opt/pdks
```

Notes:

- **Do not** set `REPO_HOME` — `sourceme.sh` derives it from its own location, so the repo works unchanged if renamed or reused for a different project.
- `ASAP7_HOME` defaults to `$PDK_HOME/OpenROAD-flow-scripts/flow/platforms/asap7`; export it in `~/.bashrc` to target a different platform/technology.
- The final `make pnr` stage (DEF-to-GDS merge) additionally needs `klayout` (≥ 0.28) on `PATH`; a system-wide install is fine. The flow produces the routed DEF/ODB without it and errors clearly at the GDS stage if it is missing.

## Typical workflow

The make targets form a pipeline where earlier steps produce artifacts consumed by later ones:

1. `make sim` — functional verification (pass `VCD=1` to also dump `activity.vcd`).
2. `make syn` — logic synthesis; produces the netlist consumed by all post-synthesis flows.
3. `make post-syn-sim` — gate-level functional verification; produces `activity.vcd` consumed by `make post-syn-dpa`.
4. `make post-syn-sta` — static timing analysis from the synthesized netlist.
5. `make post-syn-dpa` — power estimation using the synthesized netlist and the `activity.vcd` from `make post-syn-sim`.
6. `make pnr` — place-and-route of the synthesized netlist; produces the final layout, the routed netlist and its parasitics.
7. `make post-pnr-sim` — gate-level functional verification of the routed netlist; produces `activity.vcd` for `make post-pnr-dpa`.
8. `make post-pnr-sta` — parasitics-accurate static timing analysis from the routed netlist and SPEF.
9. `make post-pnr-dpa` — parasitics-accurate power estimation using the routed netlist, SPEF and the post-pnr `activity.vcd`.

## Conventions

The flow imposes a small contract on every project; the example project follows all of it:

- **Layout.** RTL in `rtl/` (one module per file, file named after the module), one self-contained testbench per top-level in `tb/tb_<top>.sv`, project automation in `scripts/` run directly, design docs in `wiki/`.
- **Testbench.** The DUT instance is named `dut` (the power flows annotate the VCD on that scope), the clock period comes from the `CLK_PERIOD_NS` define, and a `POST_SYN_SIM` branch instantiates the netlist without parameters and with unpacked array ports flattened into vectors.
- **File header.** Every source file starts with an author line and an `SPDX-License-Identifier` line inside a dashed comment block, in the file's own comment syntax; RTL adds a `Description:` and a `Parameters:` paragraph.
- **RTL style.** Signals are lowercase with `_i`/`_o` direction suffixes and `_n` for active-low (`clk_i`, `rst_ni`); primitives are general and parameterized so they can be reused.

## Commands

The `TOP_LEVEL` values and `PARAMS` keys are project-specific; the syntax below is the shared interface. See the project README for the available top-levels and elaboration parameters.

### Pre-synthesis simulation (Verilator)

```bash
make sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1]
```

| Parameter       | Required | Description                                                     |
| --------------- | -------- | --------------------------------------------------------------- |
| `TOP_LEVEL`     | yes      | RTL module to simulate                                          |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                     |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`                                |
| `TB`            | no       | Testbench module to run; default `tb_<top_level>`               |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters                     |
| `VCD`           | no       | `1` enables tracing and dumps `activity.vcd`; default `0` (off) |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`.

### Logic synthesis (Yosys + ABC, ASAP7 target)

```bash
make syn TOP_LEVEL=<top_level> OUT_DIR=<name> [CLK_PERIOD_NS=<val>] [PARAMS="KEY=VAL ..."] \
    [KEEP_HIERARCHY=1] [KEEP_MODULES="mod ..."] [BLACKBOX_MODULES="mod ..."] [LINK_BLACKBOXES=0]
```

| Parameter          | Required          | Description                                                                    |
| ------------------ | ----------------- | ------------------------------------------------------------------------------ |
| `TOP_LEVEL`        | yes               | RTL module to synthesize; can be any module in the hierarchy                   |
| `OUT_DIR`          | yes               | Output subdirectory under `imp/`                                               |
| `CLK_PERIOD_NS`    | no (default: 1.0) | Delay target for the ABC mapper (resolved script saved as `output/abc.script`) |
| `PARAMS`           | no                | Project-specific RTL elaboration parameters                                    |
| `KEEP_HIERARCHY`   | no (default: 0)   | Preserve every module boundary in the netlist (skips `flatten`)                |
| `KEEP_MODULES`     | no                | Preserve only the listed module boundaries and flatten below them              |
| `BLACKBOX_MODULES` | no                | Do not elaborate the listed modules; link their netlists from an earlier run   |
| `LINK_BLACKBOXES`  | no (default: 1)   | `0` keeps the blackboxed modules as empty stubs for hierarchical `make pnr`    |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`.

#### Netlist hierarchy

| Mode               | Netlist                               | `report/area.rpt`                 |
| ------------------ | ------------------------------------- | --------------------------------- |
| default            | fully flat                            | one number                        |
| `KEEP_HIERARCHY=1` | every module boundary                 | every module                      |
| `KEEP_MODULES`     | listed modules only, flat inside each | top + listed modules              |
| `BLACKBOX_MODULES` | one shared module per listed name     | top + one entry per linked module |

The netlist of the BLACKBOX_MODULES is read from `imp/<mod>_syn/output/netlist.v` (or, failing that, `imp/<mod>/output/netlist.v`) and the run fails if neither exists — so name the block's own synthesis run `OUT_DIR=<mod>_syn`. A linked module is not resynthesized, so its area is exactly the one from its own run — rerun the first pass after changing its RTL.

### Post-synthesis static timing analysis (OpenSTA)

```bash
make post-syn-sta TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir>
```

| Parameter       | Required | Description                                                  |
| --------------- | -------- | ------------------------------------------------------------ |
| `TOP_LEVEL`     | yes      | RTL module name                                              |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                  |
| `OUT_DIR`       | yes      | Output subdirectory under `imp/`                             |
| `NETLIST_DIR`   | yes      | Directory containing the synthesized netlist from `make syn` |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`.

### Post-synthesis gate-level simulation

```bash
make post-syn-sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> \
    [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1]
```

| Parameter       | Required | Description                                                       |
| --------------- | -------- | ----------------------------------------------------------------- |
| `TOP_LEVEL`     | yes      | RTL module to simulate                                            |
| `CLK_PERIOD_NS` | yes      | Clock period in nanoseconds                                       |
| `OUT_DIR`       | yes      | Output subdirectory under `sim/`                                  |
| `NETLIST_DIR`   | yes      | Directory containing the synthesized netlist from `make syn`      |
| `TB`            | no       | Testbench module to run; default `tb_<top_level>`                 |
| `PARAMS`        | no       | Project-specific RTL elaboration parameters                       |
| `VCD`           | no       | `1` dumps `activity.vcd`; default `0`. Required by `post-syn-dpa` |

Outputs go to `projects/<PROJECT>/sim/<OUT_DIR>/`. Compiles the testbench with the `POST_SYN_SIM` compile-time flag, which the bench uses to instantiate the synthesized netlist instead of the RTL. Synthesis flattens unpacked array ports into single vectors and drops parameters, so a bench that drives such a top-level needs a `POST_SYN_SIM` branch that instantiates the DUT without parameters and wires the flat ports.

The ASAP7 sequential cells are read from `scripts/post-syn-sim/asap7_seq_behav.v` rather than from the PDK, because Verilator does not implement the 1995 UDP tables the PDK models are built on and miscompiles them silently. Add a model there if `dfflibmap` ever emits a cell it does not cover.

### Post-synthesis dynamic power analysis (OpenSTA)

```bash
make post-syn-dpa TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> VCD_DIR=<vcd_dir> \
    [TB=<testbench>] [KEEP_HIERARCHY=1] [KEEP_MODULES="mod ..."] [BLACKBOX_MODULES="mod ..."]
```

| Parameter          | Required        | Description                                                                       |
| ------------------ | --------------- | --------------------------------------------------------------------------------- |
| `TOP_LEVEL`        | yes             | RTL module name                                                                   |
| `CLK_PERIOD_NS`    | yes             | Clock period in nanoseconds                                                       |
| `OUT_DIR`          | yes             | Output subdirectory under `imp/`                                                  |
| `NETLIST_DIR`      | yes             | Directory containing the synthesized netlist from `make syn`                      |
| `VCD_DIR`          | yes             | Directory containing `activity.vcd` from `make post-syn-sim VCD=1`                |
| `TB`               | no              | Testbench module the VCD was dumped from; default `tb_<top_level>`                |
| `KEEP_HIERARCHY`   | no (default: 0) | Also generate `power_hierarchy.rpt` with a per-instance breakdown                 |
| `KEEP_MODULES`     | no              | Same effect as `KEEP_HIERARCHY=1` on the report; pass the value used at synthesis |
| `BLACKBOX_MODULES` | no              | Same effect as `KEEP_HIERARCHY=1` on the report; pass the value used at synthesis |

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`. The VCD is annotated onto the scope `<TB>/dut`, so the testbench must name its DUT instance `dut`. `report/vcd_annotated.rpt` and `report/vcd_unannotated.rpt` list how many pins were annotated — a low count means the scope did not match and the power numbers are estimates, not measurements.

The per-instance report needs a netlist with module boundaries, so pass the same hierarchy parameters that were used for `make syn`.

### Place-and-route (OpenROAD, ASAP7 target)

```bash
make pnr TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<netlist_dir> \
    [CORE_UTIL=<pct>] [ASPECT_RATIO=<val>] [CORE_MARGIN=<um>] [PLACE_DENSITY=<val>] \
    [MAX_ROUTE_LAYER=<layer>] [CLK_UNCERTAINTY_PS=<val>] [PNR_STEP=<stage>] [PNR_THREADS=<n>] \
    [MACRO_DIRS="dir ..."] [FLOORPLAN=<file>] [MACRO_CHANNEL=<um>] [PDN=<file>]
```

| Parameter            | Required           | Description                                                                                                |
| -------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------- |
| `TOP_LEVEL`          | yes                | Module to place-and-route (must match the netlist top)                                                     |
| `CLK_PERIOD_NS`      | yes                | Clock period in nanoseconds                                                                                |
| `OUT_DIR`            | yes                | Output subdirectory under `imp/`                                                                           |
| `NETLIST_DIR`        | yes                | Directory containing the flat netlist from `make syn`                                                      |
| `CORE_UTIL`          | no (default: 40)   | Core utilization percentage; the die area derives from it                                                  |
| `ASPECT_RATIO`       | no (default: 1.0)  | Core height/width ratio                                                                                    |
| `CORE_MARGIN`        | no (default: 2)    | Core-to-die margin in µm                                                                                   |
| `PLACE_DENSITY`      | no (default: 0.60) | Global placement target density                                                                            |
| `MAX_ROUTE_LAYER`    | no (default: M7)   | Top signal-routing layer; use `M6` when hardening a tile so M7 stays free for the parent PDN               |
| `CLK_UNCERTAINTY_PS` | no (default: 0)    | Clock uncertainty in picoseconds                                                                           |
| `PNR_STEP`           | no (default: all)  | `all` = full clean run; a stage name re-runs only that stage                                               |
| `PNR_THREADS`        | no (default: 0)    | OpenROAD thread count; `0` = all cores                                                                     |
| `MACRO_DIRS`         | no                 | Run dirs of hardened blocks to bind as hard macros                                                         |
| `MACRO_CHANNEL`      | no                 | Gap in µm between adjacent macros; read by the project floorplan file (wider = easier routing, larger die) |
| `FLOORPLAN`          | no                 | Project TCL placing the macros (`place_macro` per instance)                                                |
| `PDN`                | no                 | PDN strategy override (macro runs default to `pdn_macro.tcl`)                                              |

The flow is six stages, each an independent `openroad` process chained through ODB checkpoints: `1_floorplan`, `2_place`, `3_cts`, `4_route`, `5_final`, `6_gds` (KLayout merge). ICG clock gates from synthesis are placed, routed and balanced by CTS.

Outputs go to `projects/<PROJECT>/imp/<OUT_DIR>/`: the layout (`output/design.def/.odb/.gds`), the routed `output/netlist.v` and parasitics `output/netlist.spef` consumed by the `post-pnr-*` flows, the hard-macro abstracts (`output/abstract.lef`, `output/timing_model.lib`), per-stage checkpoints/logs, and the reports (per-stage timing/area, `route_drc.rpt` — must be empty — plus critical paths, WNS/TNS, clock skew, power, design area).

#### Hierarchical place-and-route (hard macros)

1. Harden each block: `make pnr TOP_LEVEL=<block> ... MAX_ROUTE_LAYER=M6` (reserve M7 for the parent's power over the macros; combinational blocks are fine — CTS skips itself).
2. Synthesize the parent with empty stubs: `make syn TOP_LEVEL=<top> BLACKBOX_MODULES="<block> ..." LINK_BLACKBOXES=0 ...`.
3. Implement the parent: `make pnr ... MACRO_DIRS="<block_dir> ..." FLOORPLAN=<file>`, where the file places each macro (`place_macro -macro_name <inst> -location {x y} -orientation R0`).

The `post-pnr-*` steps take the same `MACRO_DIRS`: STA uses the blocks' timing models, simulation compiles their routed netlists, and DPA analyzes the blocks in full — `power_summary.rpt` is the true total and `power_macros.rpt` breaks out each macro's in-system power. Note: `route_drc.rpt` may show a few `Lef58EolKeepOut` markers at macro pins — false positives of the abstract (the merged GDS metal is continuous there).

### Post-place-and-route static timing analysis (OpenSTA)

```bash
make post-pnr-sta TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> [MACRO_DIRS="dir ..."]
```

Same interface and reports as `make post-syn-sta`, but `NETLIST_DIR` points at a `make pnr` run: the routed `netlist.v` is linked and `netlist.spef` is read, so timing is parasitics-accurate with propagated clocks.

### Post-place-and-route gate-level simulation

```bash
make post-pnr-sim TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> \
    [TB=<testbench>] [PARAMS="KEY=VAL ..."] [VCD=1] [MACRO_DIRS="dir ..."]
```

Same interface and testbench conventions as `make post-syn-sim` (including the `POST_SYN_SIM` compile-time flag), but simulates the routed netlist from a `make pnr` run. Pass `VCD=1` to dump the `activity.vcd` consumed by `make post-pnr-dpa`.

### Post-place-and-route dynamic power analysis (OpenSTA)

```bash
make post-pnr-dpa TOP_LEVEL=<top_level> CLK_PERIOD_NS=<val> OUT_DIR=<name> NETLIST_DIR=<pnr_dir> VCD_DIR=<vcd_dir> \
    [TB=<testbench>] [MACRO_DIRS="dir ..."]
```

Same interface as `make post-syn-dpa`, but `NETLIST_DIR` points at a `make pnr` run: the routed netlist and `netlist.spef` are read, so power is parasitics-accurate. With `MACRO_DIRS`, the hardened blocks are analyzed in full and `power_macros.rpt` reports each macro's in-system power.

### Experiment automation

Project-specific automation — synthesis sweeps, result extraction, and chart/table generation — lives under `projects/<PROJECT>/scripts/`. These are plain, self-contained scripts, **run directly** rather than through `make`:

```bash
bash projects/<PROJECT>/scripts/<sweep>.sh # drive a batch of make syn/sim runs
```

Each script embeds or reads the data it needs and chooses where to write its results; see the project's own README for the experiments it provides.

### Cleanup

```bash
make clean-sim OUT_DIR=<name> # remove one simulation run
make clean-imp OUT_DIR=<name> # remove one synthesis/P&R/STA/DPA run
make clean-all                # remove all sim/ and imp/ directories
```

### Make-level parameters reference

| Parameter            | Make targets                | Values                          | Description                                                                          |
| -------------------- | --------------------------- | ------------------------------- | ------------------------------------------------------------------------------------ |
| `PROJECT`            | all                         | project name                    | Required. Project under `projects/` to operate on (no default)                       |
| `TOP_LEVEL`          | all except init and clean-* | module name                     | RTL module to build/simulate; can be any module in the hierarchy                     |
| `TB`                 | sim, post-*-sim, post-*-dpa | testbench module name           | Testbench to run (default `tb_$(TOP_LEVEL)`)                                         |
| `CLK_PERIOD_NS`      | all except init and clean-* | e.g. `1.0`                      | Clock period in nanoseconds (for `syn`: the ABC delay target, default `1.0`)         |
| `OUT_DIR`            | all except clean-all        | directory name                  | Output subdirectory under `sim/` or `imp/`                                           |
| `NETLIST_DIR`        | pnr, post-syn-*, post-pnr-* | e.g. `syn_top_example`          | Netlist run to consume (`make syn` for pnr/post-syn-*, `make pnr` for post-pnr-*)    |
| `VCD_DIR`            | post-syn-dpa, post-pnr-dpa  | e.g. `sim_top_example`          | Directory containing `activity.vcd` from the matching gate-level simulation          |
| `PARAMS`             | sim, syn, post-*-sim        | `"KEY=VAL ..."`                 | Project-specific RTL elaboration parameters                                          |
| `VCD`                | sim, post-*-sim             | `0` (default), `1`              | Enable Verilator tracing and dump `activity.vcd`                                     |
| `KEEP_HIERARCHY`     | syn, post-syn-dpa           | `0` (default), `1`              | Preserve module boundaries in the netlist                                            |
| `KEEP_MODULES`       | syn, post-syn-dpa           | `"mod ..."` (default: `none`)   | Preserve only the listed module boundaries and flatten everything below them         |
| `BLACKBOX_MODULES`   | syn, post-syn-dpa           | `"mod ..."` (default: `none`)   | Do not elaborate the listed modules; link their netlists from an earlier run         |
| `LINK_BLACKBOXES`    | syn                         | `1` (default), `0`              | `0` keeps blackboxed modules as empty stubs for hierarchical P&R                     |
| `CORE_UTIL`          | pnr                         | percent (default: `40`)         | Core utilization for the floorplan; die area derives from it                         |
| `ASPECT_RATIO`       | pnr                         | ratio (default: `1.0`)          | Core height/width ratio                                                              |
| `CORE_MARGIN`        | pnr                         | µm (default: `2`)               | Margin between core area and die edge                                                |
| `PLACE_DENSITY`      | pnr                         | 0–1 (default: `0.60`)           | Global placement target density                                                      |
| `MAX_ROUTE_LAYER`    | pnr                         | layer (default: `M7`)           | Top signal-routing layer; `M6` when hardening a tile reserves M7 for the parent PDN  |
| `CLK_UNCERTAINTY_PS` | pnr                         | ps (default: `0`)               | Clock uncertainty applied to the clocks                                              |
| `PNR_STEP`           | pnr                         | `all` (default) or a stage name | `all` = full clean run; a stage name re-runs that stage from the previous checkpoint |
| `PNR_THREADS`        | pnr                         | `0` (default) or thread count   | OpenROAD thread count; `0` = all cores. Fewer route threads lower the memory peak    |
| `MACRO_DIRS`         | pnr, post-pnr-*             | `"dir ..."` (default: `none`)   | Hardened-block run dirs to bind as hard macros                                       |
| `MACRO_CHANNEL`      | pnr                         | µm (default: `10`)              | Gap between adjacent macros, used by the project floorplan file                      |
| `FLOORPLAN`          | pnr                         | path (default: `none`)          | Project-owned macro-placement TCL sourced after the floorplan                        |
| `PDN`                | pnr                         | path (default: `none`)          | PDN strategy override (macro runs default to `scripts/pnr/pdn_macro.tcl`)            |

## License

Copyright 2026 Simone Machetti. Released under the [Apache License 2.0](LICENSE); every source file carries an `SPDX-License-Identifier: Apache-2.0` line in its header. The KLayout streaming script `scripts/pnr/def2stream.py` is copied verbatim from [OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) and keeps its BSD-3-Clause license, as noted in its header. The EDA tools and the ASAP7 PDK are not part of this repository and come under their own licenses.
