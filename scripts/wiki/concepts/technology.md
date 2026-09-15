# Technology foundations — PDK, liberty, LEF, GDS

Every step of the flow consumes *views* of the same physical reality: the standard-cell library fabricated in a given process. This document dissects those views — what each file format describes, why several coexist, and what is specific to ASAP7 — so that later documents can reference them without re-explaining.

## Inputs and outputs

- **Consumed by**: every step. Synthesis and the STA/DPA steps read liberty (`.lib`); gate-level simulation reads behavioral Verilog cell models (`.v`); place-and-route reads liberty + LEF (`.lef`); the GDS merge reads the cell layouts (`.gds`).
- **Provided by**: the ASAP7 platform tree, reachable as `$ASAP7_HOME` (derived by `sourceme.sh` from `PDK_HOME`).

## Theory

### What a PDK is

A **process design kit** is the interface between a fabrication process and design tools: the set of files that describe what can be manufactured (layers, design rules), what is available pre-designed (standard cells, memories, I/O cells), and how it behaves (timing, power, parasitics). For digital implementation the central piece is the **standard-cell library**: a few hundred pre-laid-out logic gates in a common frame (same height, shared power-rail positions) so that any mix of them tiles into rows.

A single cell exists simultaneously as several views, each serving one tool class:

| View               | File format    | Content                                        | Consumer                 |
| ------------------ | -------------- | ---------------------------------------------- | ------------------------ |
| Timing/power model | Liberty `.lib` | Delays, slews, capacitances, energies, leakage | Synthesis, STA, DPA, P&R |
| Physical abstract  | LEF `.lef`     | Footprint, pin shapes, obstructions            | P&R                      |
| Full layout        | GDS `.gds`     | Every polygon on every mask layer              | Final GDS merge, DRC/LVS |
| Behavioral model   | Verilog `.v`   | Simulatable logic function                     | Gate-level simulation    |

The separation is deliberate: P&R placing a million cells cannot afford transistor-level geometry, and simulation cannot use polygons — each tool gets exactly the abstraction it needs, and consistency between the views is the library vendor's contract.

### Liberty: the timing and power view

A `.lib` file is a text database with one `cell` entry per gate. For each input-to-output arc it stores **NLDM tables** (non-linear delay model): two-dimensional lookup tables of delay and output slew indexed by *input slew* and *output load capacitance* — the two quantities that dominate a CMOS gate's speed. Alongside timing: pin capacitances, internal switching energy tables (used by power analysis), state-dependent leakage, and for sequential cells the setup/hold/recovery constraints and the clock-gating attributes that let tools recognize an integrated clock gate (ICG) as a clock-tree element. NLDM's successor, **CCS/ECSM** (current-source models), replaces the table's single numbers with current waveforms for better accuracy at advanced nodes; ASAP7 ships both, and this flow uses NLDM — simpler, faster, sufficient for relative comparisons.

Three axes multiply the number of `.lib` files:

- **Corner (PVT)**: process (slow/typical/fast transistors), voltage, temperature. A library is characterized per corner — e.g. `TT` 0.70 V (typical), `SS` 0.63 V 100 °C (worst-case slow, setup signoff), `FF` 0.77 V 0 °C (fast, hold signoff). This flow runs single-corner **TT** throughout: architectural comparison, not signoff.
- **VT flavor**: the same logical cell is offered with different threshold-voltage implants — in ASAP7: `R` (regular VT), `L` (low VT: faster, leakier), `SL` (super-low VT). Mixed-VT optimization is a classic leakage-vs-speed lever; this flow uses **RVT only**.
- **Functional group**: ASAP7 splits the library into five files — `SIMPLE` (basic gates), `INVBUF` (inverters/buffers), `AO`/`OA` (and-or / or-and complex gates), `SEQ` (flip-flops, latches, ICGs) — which is why every script reads five `read_liberty` lines.

One consequence used everywhere in the flow: **the ASAP7 liberty time unit is the picosecond**, so every SDC value, every report and every delay target in the scripts is in ps (`CLK_PERIOD_NS × 1000`).

### LEF: the physical abstract

Two LEF files split the physical description:

- The **technology LEF** (`asap7_tech_1x_201209.lef`) describes the *process* as routers see it: the metal/via stack (M1–M9 + Pad), each layer's preferred routing direction, widths/spacings/pitches and advanced rules (e.g. the LEF58 end-of-line keep-outs that appear in routing), via definitions, the manufacturing grid, and the placement **site** — for `asap7sc7p5t` a 0.054 × 0.270 µm tile, the atomic unit of placement.
- The **cell LEF** (`asap7sc7p5t_28_R_1x_220121a.lef`) holds one `MACRO` per standard cell: its size in sites, the shapes/layers of its pins, and obstruction geometry for everything else. P&R works exclusively on these abstracts.

The same MACRO format describes big hard macros (memories — or the blocks this flow hardens itself, whose `abstract.lef` is generated by `write_abstract_lef` in stage `5_final`): from the parent's perspective a macro is just a very large cell.

### GDS: the mask reality

GDSII is the polygon-level format of the actual masks. The flow touches it only at the very end: the router's DEF output (placements + wire segments) is *streamed* into GDS geometry and merged with the library's cell GDS (`asap7sc7p5t_28_R_220121a.gds`), replacing each abstract with its real transistor-level layout ([11_pnr_gds.md](../steps/11_pnr_gds.md)).

### Behavioral Verilog models

For gate-level simulation each cell needs a simulatable model. ASAP7 ships them (`verilog/stdcell/*.v`), with one caveat handled in [02_post_syn_sim.md](../steps/02_post_syn_sim.md): the sequential models are built on Verilog-1995 UDP primitives that Verilator does not implement, so the flow substitutes its own behavioral models for the sequential cells.

### ASAP7 specifics worth knowing

- It is a **predictive, academic** 7 nm PDK — no fab behind it. Ideal for architecture/methodology work; meaningless for tapeout.
- The distributed LEF/GDS are the **`1x` scaled** set (geometry up-scaled to a manufacturable grid); all `1x` files are mutually consistent and must never be mixed with other scalings.
- The platform packaging used here is the OpenROAD-flow-scripts ASAP7 tree, which adds ready-made physical setup the flow reuses: routing-track definitions (`make_tracks.tcl`), PDN strategies (`openRoad/pdn/*.tcl`), calibrated wire RC (`setRC.tcl`), and RC-extraction patterns (`rcx_patterns.rules`).
- Gaps that shape the flow: **no I/O pad library** (hence block-level implementation only), **no antenna diode cell** (hence no antenna repair step), and SRAMs only as "fake" generated macros (unused here).

## Implementation walkthrough

Technology enters the flow in three places, always through the same file lists.

Liberty — identically in synthesis (`scripts/syn/compile.tcl`, as `-lib` for cell recognition), in every OpenSTA step, and in every P&R stage (`scripts/pnr/init_tech.tcl`):

```tcl
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $::env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib
```

The file names encode the axes described above: `asap7sc7p5t` (7.5-track library) + group + `RVT` + `TT` + `nldm` + characterization date. The suppression file sourced before them in P&R (`liberty_suppressions.tcl`) silences one known benign warning in the SIMPLE library.

LEF — in `init_tech.tcl`, consumed by stage 1:

```tcl
set TECH_LEF        $::env(ASAP7_HOME)/lef/asap7_tech_1x_201209.lef
set SC_LEF          $::env(ASAP7_HOME)/lef/asap7sc7p5t_28_R_1x_220121a.lef
```

Cell names in netlists carry the same encoding — e.g. `NAND2xp33_ASAP7_75t_R`: function (`NAND2`), drive strength (`xp33` = 0.33× unit drive; `x2` = 2×), library family, `75t` = 7.5-track, `R` = RVT. Drive-strength families are what the resizer moves through when repairing timing.

Wire parasitics for pre-route estimation — `setRC.tcl`, sourced by every P&R stage, sets per-layer unit resistance/capacitance calibrated against extracted results:

```tcl
set_layer_rc -layer M2 -resistance 4.62311E-02 -capacitance 1.84542E-01
set_wire_rc -signal -resistance 3.23151E-02 -capacitance 1.73323E-01
set_wire_rc -clock  -resistance 5.13971E-02 -capacitance 1.44549E-01
```

(excerpt; one `set_layer_rc` per routing layer and via — the full file also covers M1–M7 and V1–V8).

## Design space

- **Corners**: adding `SS`/`FF` liberty sets and analyzing setup at SS / hold at FF is the step from "architectural comparison" to "signoff-style" timing. OpenSTA and OpenROAD support multi-corner analysis; the flow's single-TT choice trades that rigor for speed and simplicity.
- **VT mixing**: allowing `L`/`SL` cells during optimization (additional liberty files + removing them from the dont-use list) buys speed on critical paths at a leakage cost — one of the most effective knobs in real flows.
- **NLDM vs CCS**: switching the file set to `lib/CCS/` increases model fidelity (waveform effects, better slew handling) at higher runtime; relative comparisons rarely justify it.
- **Track library height**: ASAP7 also ships 6-track and 9-track variants conceptually (7.5T here); the height choice is a density-vs-drive tradeoff fixed at library selection time.
- **Other technologies**: the flow structure is technology-agnostic — `ASAP7_HOME` can point at another platform tree, provided liberty/LEF/GDS plus track and PDN setup exist for it (open PDKs like SKY130 or IHP SG13G2 ship the equivalent files, including real I/O libraries that would enable chip-level flows).

## Knobs

| Knob               | Where             | Default         | Effect / tradeoff                                           |
| ------------------ | ----------------- | --------------- | ----------------------------------------------------------- |
| `ASAP7_HOME`       | environment       | ORFS ASAP7 tree | Selects the whole technology platform                       |
| Liberty corner set | script file lists | RVT TT          | Analysis realism vs runtime; SS/FF needed for signoff-style |
| VT flavors loaded  | script file lists | RVT only        | Speed vs leakage optimization space                         |
| NLDM vs CCS        | script file lists | NLDM            | Model fidelity vs runtime                                   |

## Notes and caveats

- Time unit is **ps** throughout the flow — a consequence of the liberty characterization, not a choice in the scripts. Values passed to any timing command must be ps.
- The five liberty groups must all be loaded everywhere; a missing group surfaces as unlinked cells at `link_design` time.
- All physical files must come from the same `1x` scaled set; mixing scalings corrupts geometry silently.
- The platform's `.lib.gz` variants (present for other corners) must be uncompressed before use with these tools.
- ASAP7's missing I/O library and antenna diode are *structural* constraints of this flow (block-level style; no antenna repair), not omissions of the scripts.

## Commercial perspective

The same views exist under the same names in commercial kits — liberty is an industry standard (originated by Synopsys), LEF/DEF by Cadence, GDSII by Calma — with two main additions at production grade: signoff-calibrated extraction decks (replacing `setRC.tcl`-style estimates) and complete characterization matrices (dozens of corners, OCV/POCV derating data, CCS/ECSM everywhere) generated by dedicated characterization tools (Liberate, SiliconSmart). The `.db` files consumed by Synopsys tools are compiled liberty, not a different model.

Source: [init_tech.tcl](../../pnr/init_tech.tcl) — [compile.tcl](../../syn/compile.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
