# ASIC Design Flow

The complete open-source ASIC flow of this repository, step by step: the tool that implements each step, its inputs and its outputs. Every step is a `make` target (see the root [README.md](../README.md) for commands and parameters); all paths follow the repository conventions (`projects/<project>/imp|sim/<OUT_DIR>/{output,report}`). Technology: ASAP7 (7 nm predictive PDK, RVT, TT corner), block-level implementation (pins on routing layers, no pad ring, single power domain).

## SIM — Verilator

Pre-synthesis functional simulation (`make sim`).

**Inputs**

- RTL files `.sv` (`projects/<project>/rtl/`)
- Testbench `.sv` (`projects/<project>/tb/tb_<top>.sv`)
- Lint waivers `.vlt`
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR` (required); `TB`, `PARAMS`, `VCD` (optional)

**Outputs**

- Simulation binary + logs (`compile.log`, `run.log`)
- Switching activity `.vcd` (with `VCD=1`)

## SYN — Yosys (yosys-slang frontend, ABC mapper)

Logic synthesis to the ASAP7 standard-cell library (`make syn`).

**Inputs**

- RTL files `.sv`
- Library of cells `.lib` (Liberty, five ASAP7 NLDM RVT TT groups: SEQ, SIMPLE, INVBUF, AO, OA)
- Latch technology map `.v` (`$ASAP7_HOME/yoSys/cells_latch_R.v`)
- Previously synthesized netlists `imp/<mod>/output/netlist.v` (blackbox linking)
- Delay target for the ABC mapper, derived from `CLK_PERIOD_NS` (the resolved ABC script is archived as `output/abc.script`)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `OUT_DIR` (required); `CLK_PERIOD_NS`, `PARAMS`, `KEEP_HIERARCHY`, `KEEP_MODULES`, `BLACKBOX_MODULES`, `LINK_BLACKBOXES` (optional)

**Outputs**

- Post-syn netlist `.v` (`output/netlist.v`)
- Synthesis log (`output/yosys.log`)
- Area report (`report/area.rpt`)

Note: the clock period enters synthesis only as the ABC delay target (ABC's mapper is delay-oriented by default, so the target mainly documents intent); timing/power reports come from POST-SYN-STA/DPA.

## POST-SYN-SIM — Verilator

Gate-level functional simulation of the synthesized netlist (`make post-syn-sim`). Zero-delay functional models, no back-annotated timing.

**Inputs**

- Post-syn netlist `.v`
- Functional models of cells `.v` (ASAP7 stdcell verilog + `scripts/post-syn-sim/asap7_seq_behav.v` for sequential cells)
- Testbench `.sv` (compiled with `POST_SYN_SIM`)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `TB`, `PARAMS`, `VCD` (optional)

**Outputs**

- Post-syn switching activity `.vcd` (with `VCD=1`)
- Simulation logs

## POST-SYN-STA — OpenSTA

Static timing analysis of the synthesized netlist, ideal wires and ideal clocks (`make post-syn-sta`).

**Inputs**

- Post-syn netlist `.v`
- Library of cells `.lib` (Liberty)
- Constraints, generated inline from `CLK_PERIOD_NS`: clock on `clk_i` (if present) + virtual clock with zero I/O delays, hold false-pathed on I/O
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required)

**Outputs**

- Timing reports (`unconstrained.rpt`, `critical_paths.rpt`, `wns.rpt`, `tns.rpt`)

## POST-SYN-DPA — OpenSTA

VCD-based dynamic power analysis of the synthesized netlist (`make post-syn-dpa`).

**Inputs**

- Post-syn netlist `.v`
- Library of cells `.lib` (Liberty)
- Post-syn switching activity `.vcd` (annotated onto scope `<TB>/dut`)
- Constraints, generated inline (as in POST-SYN-STA)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR`, `VCD_DIR` (required); `TB`, `KEEP_HIERARCHY`, `KEEP_MODULES`, `BLACKBOX_MODULES` (optional)

**Outputs**

- Power reports (`power_summary.rpt`, `power_hierarchy.rpt` with hierarchy, VCD annotation reports)

## PNR — OpenROAD (+ KLayout for the GDS merge)

Place-and-route from the synthesized netlist to the final layout (`make pnr`), six stages chained through ODB checkpoints: floorplan, placement, clock tree synthesis, routing, finishing, GDS merge.

**Inputs**

- Post-syn netlist `.v` (flat)
- Library of cells `.lib` (Liberty)
- Technology dimensions `.lef` (tech LEF + standard-cell LEF)
- Standard-cell layout `.gds` (for the final merge)
- Constraints, generated inline from `CLK_PERIOD_NS` (same scheme as the STA steps)
- ASAP7 platform physical setup (routing tracks, PDN grid strategy, wire RC, RC extraction rules)
- Hierarchical mode: hardened-block abstracts `.lef`/`.lib`/`.gds` (`MACRO_DIRS`) + project-owned macro-placement TCL (`FLOORPLAN`)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `CORE_UTIL`, `ASPECT_RATIO`, `CORE_MARGIN`, `PLACE_DENSITY`, `MAX_ROUTE_LAYER`, `CLK_UNCERTAINTY_PS`, `PNR_STEP`, `PNR_THREADS`, `MACRO_DIRS`, `FLOORPLAN`, `MACRO_CHANNEL`, `PDN` (optional)

**Outputs**

- Post-pnr netlist `.v` (routed, physical-only cells removed — same contract as the syn netlist)
- Post-pnr constraints `.sdc` (as implemented)
- Post-pnr parasitics `.spef` (OpenRCX extraction)
- Layout `.def` and `.gds`
- Database `.odb` (final + per-stage checkpoints)
- Hard-macro abstracts: `.lef` (abstract) + `.lib` (timing model) — for hierarchical place-and-route
- Post-pnr reports (per-stage timing/area, routing DRC, critical paths, WNS/TNS, clock skew, power, design area)

## POST-PNR-SIM — Verilator

Gate-level functional simulation of the routed netlist (`make post-pnr-sim`). Same setup as POST-SYN-SIM.

**Inputs**

- Post-pnr netlist `.v`
- Functional models of cells `.v`
- Testbench `.sv` (compiled with `POST_SYN_SIM`)
- Hardened-block routed netlists `.v` (`MACRO_DIRS`, hierarchical results)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `TB`, `PARAMS`, `VCD`, `MACRO_DIRS` (optional)

**Outputs**

- Post-pnr switching activity `.vcd` (with `VCD=1`)
- Simulation logs

## POST-PNR-STA — OpenSTA

Parasitics-accurate static timing analysis of the routed design (`make post-pnr-sta`).

**Inputs**

- Post-pnr netlist `.v`
- Library of cells `.lib` (Liberty)
- Post-pnr parasitics `.spef`
- Constraints, generated inline (as in POST-SYN-STA), clocks propagated
- Hardened-block timing models `.lib` (`MACRO_DIRS`, hierarchical results)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `MACRO_DIRS` (optional)

**Outputs**

- Timing reports (`unconstrained.rpt`, `critical_paths.rpt`, `wns.rpt`, `tns.rpt`)

## POST-PNR-DPA — OpenSTA

Parasitics-accurate dynamic power analysis of the routed design (`make post-pnr-dpa`).

**Inputs**

- Post-pnr netlist `.v`
- Library of cells `.lib` (Liberty)
- Post-pnr parasitics `.spef`
- Post-pnr switching activity `.vcd` (from POST-PNR-SIM)
- Constraints, generated inline, clocks propagated
- Hardened-block routed netlists `.v` + parasitics `.spef` (`MACRO_DIRS`, hierarchical results: the blocks are linked in full and annotated per instance, so macro internals are analyzed with real power tables)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR`, `VCD_DIR` (required); `TB`, `MACRO_DIRS` (optional)

**Outputs**

- Power reports (`power_summary.rpt`, `power_macros.rpt` with per-macro breakdown in hierarchical runs, VCD annotation reports)
