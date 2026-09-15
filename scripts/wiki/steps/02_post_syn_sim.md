# Post-synthesis gate-level simulation

The first verification of the *netlist* rather than the RTL: the same self-checking testbench now drives the synthesized gates. It answers "did synthesis preserve the function?" and produces the netlist-level switching activity that dynamic power analysis consumes.

## Inputs and outputs

**Inputs**

- Post-syn netlist `.v`
- Functional models of cells `.v` (ASAP7 stdcell verilog + `scripts/post-syn-sim/asap7_seq_behav.v` for sequential cells)
- Testbench `.sv` (compiled with `POST_SYN_SIM`)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `TB`, `PARAMS`, `VCD` (optional)

**Outputs**

- Post-syn switching activity `.vcd` (with `VCD=1`)
- Simulation logs

## Theory

**Gate-level simulation (GLS)** replaces the RTL DUT with the netlist and re-runs the bench. What it can catch that RTL simulation cannot: synthesis tool bugs and mis-elaborations, incorrect hierarchy/blackbox linking, X-behavior differences (netlists expose uninitialized state more honestly), and — when delay-annotated — timing-dependent functional failure. In this flow GLS is **zero-delay**: cells evaluate instantly, so the check is purely functional; timing is OpenSTA's job, separately. (The delay-annotated variant needs SDF back-annotation, which Verilator does not support — an event-driven simulator would; see Design space.)

Two structural consequences of simulating a netlist:

- **Port flattening.** Synthesis flattens unpacked-array ports into single vectors and drops parameters. A bench that drives such a top must contain a `POST_SYN_SIM` branch instantiating the DUT with flat ports and the index mapping worked out — the flow's compile-time define selects that branch.
- **Cell models.** Every library cell needs a simulatable model. The netlist itself contains only instances; the models come from the PDK's Verilog views, listed alongside the netlist.

## Implementation walkthrough

`scripts/post-syn-sim/run.sh` shares its skeleton with the RTL sim script ([00_sim.md](00_sim.md)); the differences carry the meaning:

```bash
verilator \
    -sv \
    --build-jobs 0 \
    --binary \
    --timing \
    --output-split 20000 \
    "${trace_flags[@]}" \
    -Wall \
    -Wno-fatal \
    -Wno-SPECIFYIGN \
    -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL \
    -Wno-UNDRIVEN \
    -DPOST_SYN_SIM \
    -DCLK_PERIOD_NS="${SEL_CLK_PERIOD_NS}" \
    "${g_flags[@]}" \
    "${vlt_files[@]}" \
    --x-initial fast \
    --x-assign fast \
    --top-module "${SEL_TB}" \
    -f "${REPO_HOME}/scripts/post-syn-sim/filelist.f" \
       "${PROJ}/tb/${SEL_TB}.sv" \
    -Mdir "${SIM}/build/obj_dir" \
    -o "${SIM}/build/simv" \
    | tee "${SIM}/output/compile.log"
```

- `-DPOST_SYN_SIM` — flips the bench to its netlist-instantiation branch (flat ports, no parameters).
- `-f filelist.f` — sources come from a file list (below) instead of the RTL tree: the *netlist* is the design now.
- The extra `-Wno-*` waivers exist because PDK cell models are not lint-clean code (`SPECIFYIGN`: Verilator ignores `specify` timing blocks — expected in zero-delay GLS; the rest silence style noise from the vendor models).
- `--x-initial fast --x-assign fast` — Verilator's pragmatic 2-state answer to netlist X-semantics: uninitialized state resolves quickly to deterministic values rather than pessimistic X. Cheap and repeatable; *not* an X-propagation analysis.
- `--output-split 20000` — netlists produce one huge module; splitting the generated C++ keeps compiler memory in check.

The file list, `scripts/post-syn-sim/filelist.f`:

```
$(REPO_HOME)/scripts/post-syn-sim/asap7_seq_behav.v
$(ASAP7_HOME)/verilog/stdcell/asap7sc7p5t_AO_RVT_TT_201020.v
$(ASAP7_HOME)/verilog/stdcell/asap7sc7p5t_INVBUF_RVT_TT_201020.v
$(ASAP7_HOME)/verilog/stdcell/asap7sc7p5t_SIMPLE_RVT_TT_201020.v
$(PDK_HOME)/asap7/asap7sc7p5t_27/Verilog/asap7sc7p5t_OA_RVT_TT_201020.v

$(REPO_HOME)/projects/$(SEL_PROJECT)/imp/$(SEL_NETLIST_DIR)/output/netlist.v
```

Combinational cell models come from the PDK (the OA group from a sibling PDK tree, because the platform package ships no OA Verilog). The first entry is the flow's own file: **`asap7_seq_behav.v`**, behavioral replacements for the *sequential* cells (flip-flops, ICG). They exist because the PDK's sequential models are built on Verilog-1995 UDP primitives ("user-defined primitives" — truth-table constructs) that Verilator does not implement and, worse, miscompiles silently — the flow substitutes ordinary behavioral `always` models with identical function. If sequential mapping ever emits a cell the file does not cover, its model must be added there.

## Design space

- **Delay-annotated GLS.** With an event-driven simulator (Icarus, or commercial), the P&R-produced SDF could back-annotate real delays: at-speed functional checking and glitch-accurate activity (zero-delay VCDs systematically under-count glitches in deep combinational logic — a known bias of the power methodology). The flow's `write_sdf`-shaped extension point exists but is unused, Verilator being the only simulator assumed.
- **Formal equivalence checking** (LEC) is the industrial *replacement* for functional GLS: prove RTL ≡ netlist structurally instead of simulating vectors. Open-source options exist (Yosys-based) but scale poorly beyond medium designs; commercial LEC (Conformal, Formality) is standard signoff.
- **4-state GLS** (X-propagation accuracy) versus the flow's `--x-* fast` pragmatism: the former finds reset/initialization bugs; the latter finds functional mismatches quickly.

## Knobs

| Knob          | Where | Default          | Effect / tradeoff                                   |
| ------------- | ----- | ---------------- | --------------------------------------------------- |
| `NETLIST_DIR` | make  | —                | Which synthesis run to simulate                     |
| `TB`          | make  | `tb_<top_level>` | Bench (must contain a `POST_SYN_SIM` branch)        |
| `PARAMS`      | make  | none             | Bench-side parameters (the netlist itself has none) |
| `VCD`         | make  | 0                | Dump `activity.vcd` — required by power analysis    |

## Notes and caveats

- The `POST_SYN_SIM` bench branch must replicate synthesis's port flattening exactly (bit order of flattened arrays included); a mismatch shows up as immediate self-check failures, which makes the first GLS of a new bench double as a check of that mapping.
- The UDP substitution (`asap7_seq_behav.v`) is load-bearing: without it Verilator produces a *wrong* simulation, not an error.
- Zero-delay GLS validates function, not timing — a passing GLS with a failing STA is the expected division of labor.
- For power runs the bench must name its DUT instance `dut` (the VCD scope the power step annotates) and dump `activity.vcd`.

## Commercial perspective

Industrial flows run GLS with commercial event-driven simulators, usually SDF-annotated at signoff corners, and lean on formal equivalence as the primary functional guarantee — GLS surviving mainly for X-propagation, reset, and timing-anomaly hunting. The zero-delay functional GLS used here corresponds to their "fast functional netlist regression" mode.

Source: [run.sh](../../post-syn-sim/run.sh) — [filelist.f](../../post-syn-sim/filelist.f) — [asap7_seq_behav.v](../../post-syn-sim/asap7_seq_behav.v) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
