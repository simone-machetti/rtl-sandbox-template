# ASIC flow pipeline

The map of the flow: what it is, how the pieces connect, and the repository conventions every other page relies on. Start here, then follow the reading order in [index.md](../index.md).

## The pipeline


```
rtl -> sim
rtl -> syn -> netlist -> post-syn-sim / post-syn-sta / post-syn-dpa
              netlist -> pnr -> layout + routed netlist + spef
                             -> post-pnr-sim / post-pnr-sta / post-pnr-dpa
```

Every step is a `make` target. In pipeline order:

1. **`make sim`** — pre-synthesis functional simulation with Verilator. Verifies the RTL against a self-checking testbench; optionally dumps switching activity (`activity.vcd`).
2. **`make syn`** — logic synthesis with Yosys (yosys-slang frontend, ABC mapper) into the ASAP7 standard-cell library. Produces the gate-level `netlist.v` that everything downstream consumes.
3. **`make post-syn-sim` / `post-syn-sta` / `post-syn-dpa`** — the three post-synthesis analyses: gate-level simulation (Verilator), static timing analysis (OpenSTA, ideal wires), and VCD-based dynamic power analysis (OpenSTA).
4. **`make pnr`** — place-and-route with OpenROAD, six stages from the synthesized netlist to the final layout: floorplan, placement, clock-tree synthesis, routing, finishing, GDS merge (KLayout). Produces the layout (`design.def/.odb/.gds`), the routed `netlist.v`, extracted parasitics (`netlist.spef`), and the hard-macro abstracts (`abstract.lef`, `timing_model.lib`) that enable hierarchical implementation.
5. **`make post-pnr-sim` / `post-pnr-sta` / `post-pnr-dpa`** — the same three analyses on the routed design, now parasitics-accurate: real wire RC from the SPEF and propagated (real) clock trees.

Two properties make the flow composable:

- **The netlist contract**: every netlist producer writes `imp/<OUT_DIR>/output/netlist.v` and every netlist consumer reads `imp/<NETLIST_DIR>/output/netlist.v`. A P&R run dir therefore plugs into the same analysis steps as a synthesis run dir.
- **The hierarchical loop**: a completed P&R run is itself consumable as a *hard macro* by a later P&R run (`MACRO_DIRS`), which is how designs too large for flat implementation are built ([18_hierarchical.md](hierarchical.md)).

## Tools and technology


| Tool                | Role                                    | Steps                  |
| ------------------- | --------------------------------------- | ---------------------- |
| Verilator           | RTL and gate-level simulation           | sim, post-*-sim        |
| Yosys + yosys-slang | SystemVerilog elaboration and synthesis | syn                    |
| ABC (inside Yosys)  | Technology mapping to standard cells    | syn                    |
| OpenROAD            | Place-and-route (all six stages)        | pnr                    |
| OpenSTA             | Static timing and power analysis        | post-*-sta, post-*-dpa |
| KLayout             | Final GDS merge and layout viewing      | pnr (6_gds)            |

The technology is **ASAP7**: a 7 nm predictive, academic PDK (`asap7sc7p5t` — 7.5-track cells, RVT flavor, TT corner in this flow). It is packaged inside the OpenROAD-flow-scripts platform tree (`$ASAP7_HOME`), from which the flow takes liberty files, LEFs, GDS, and physical-setup scripts. [01_technology.md](technology.md) dissects all of it. The implementation style is **block-level**: pins on routing layers, no pad ring, single power domain — the standard style for IP blocks that integrate into a larger die.

## Repository conventions


These conventions appear in every script and every later document:

- **Make parameters → `SEL_*` environment variables.** The Makefile exports each parameter (`PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR`, ...) as `SEL_<NAME>`, and flow scripts read only those plus `REPO_HOME`/`ASAP7_HOME`. The flow hardcodes no project or repo name.
- **Run directories.** Every run lands in `projects/<PROJECT>/imp/<OUT_DIR>/` (or `sim/<OUT_DIR>/` for simulations) with exactly two subdirectories: `output/` (products and tool logs) and `report/` (reports). Every `make` target starts by deleting its own `OUT_DIR` — runs are always clean and reproducible.
- **Time is in picoseconds.** The ASAP7 liberty files use ps, so OpenSTA and OpenROAD operate in ps throughout. The user-facing `CLK_PERIOD_NS` is converted once (`× 1000`) in each script.
- **The clock is `clk_i`.** All constraint generation targets the port `clk_i` when it exists; designs without it are treated as combinational ([02_constraints.md](constraints.md)).
- **All flow code is in-repo** (`scripts/`). Files from the ASAP7 platform are *sourced* when they are pure data (`make_tracks.tcl`, PDN strategies, `setRC.tcl`) and *inlined* into our scripts when they depend on ORFS-specific variables.

Source: [Makefile](../../../Makefile) — Reference: [asic_flow.md](../../asic_flow.md) — Commands: [README.md](../../../README.md)
