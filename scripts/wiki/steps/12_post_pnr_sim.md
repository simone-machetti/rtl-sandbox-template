# Post-place-and-route gate-level simulation

The functional check of the *implemented* design: the routed netlist — reshaped by repair, CTS and hold buffering — re-runs the self-checking bench, and produces the switching activity for parasitics-accurate power analysis.

## Inputs and outputs

**Inputs**

- Post-pnr netlist `.v`
- Functional models of cells `.v`
- Testbench `.sv` (compiled with `POST_SYN_SIM`)
- Hardened-block routed netlists `.v` (`MACRO_DIRS`, hierarchical results)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `TB`, `PARAMS`, `VCD`, `MACRO_DIRS` (optional)

**Outputs**

- Post-pnr switching activity `.vcd` (with `VCD=1`)
- Simulation logs

## Theory

Everything from [02_post_syn_sim.md](02_post_syn_sim.md) applies unchanged — same zero-delay functional model, same cell-model story, same bench branch. What is *new* is the netlist under test: place-and-route rebuilt it (buffers inserted and removed, cells resized, a clock tree added, tie fanouts split), and this step proves that none of that surgery changed the function. It works at all because stage 5 stripped the physical-only cells — fillers and taps have no simulation models — while everything electrical (tie cells, clock buffers, hold buffers) is ordinary modeled logic.

For hierarchical results one addition: the parent netlist instantiates hard macros *by name only* — no module content. Simulation therefore needs each block's own routed netlist compiled alongside, exactly like a cell-model library: that is what `MACRO_DIRS` provides here. The resulting simulation covers the full gate-level hierarchy — parent logic and macro internals — which also makes its VCD the complete-activity input the hierarchical power analysis requires.

## Implementation walkthrough

`scripts/post-pnr-sim/run.sh` differs from its post-syn sibling in one block plus one line. The addition:

```bash
macro_files=()
if [ "${SEL_MACRO_DIRS}" != "none" ]; then
    for dir in ${SEL_MACRO_DIRS}; do
        macro_files+=("${PROJ}/imp/${dir}/output/netlist.v")
    done
fi
```

and its use in the compile call, right after the file list:

```bash
    --top-module "${SEL_TB}" \
    -f "${REPO_HOME}/scripts/post-pnr-sim/filelist.f" \
       "${macro_files[@]}" \
       "${PROJ}/tb/${SEL_TB}.sv" \
```

Each hardened block's routed netlist joins the compilation, resolving the parent's macro instances. In flat runs the array is empty and the command collapses to the post-syn form.

The file list, `scripts/post-pnr-sim/filelist.f`, mirrors the post-syn one — same cell models (including the shared sequential-cell substitutions, referenced from the post-syn directory rather than duplicated), different netlist source:

```
$(REPO_HOME)/scripts/post-syn-sim/asap7_seq_behav.v
$(ASAP7_HOME)/verilog/stdcell/asap7sc7p5t_AO_RVT_TT_201020.v
$(ASAP7_HOME)/verilog/stdcell/asap7sc7p5t_INVBUF_RVT_TT_201020.v
$(ASAP7_HOME)/verilog/stdcell/asap7sc7p5t_SIMPLE_RVT_TT_201020.v
$(PDK_HOME)/asap7/asap7sc7p5t_27/Verilog/asap7sc7p5t_OA_RVT_TT_201020.v

$(REPO_HOME)/projects/$(SEL_PROJECT)/imp/$(SEL_NETLIST_DIR)/output/netlist.v
```

Everything else — strict mode, parameter/waiver plumbing, the Verilator options (`-DPOST_SYN_SIM`, X-handling, output splitting), run and log handling — is identical to [02_post_syn_sim.md](02_post_syn_sim.md) and explained there.

## Design space

As for the post-syn step, plus the specifically post-route option: **SDF-annotated GLS** is most meaningful *here*, where real routed delays exist — it would validate function at speed and capture glitches for power. It requires an event-driven simulator; with Verilator the flow stays zero-delay and delegates timing entirely to STA.

## Knobs

| Knob          | Where | Default          | Effect / tradeoff                                    |
| ------------- | ----- | ---------------- | ---------------------------------------------------- |
| `NETLIST_DIR` | make  | —                | Which P&R run to simulate                            |
| `MACRO_DIRS`  | make  | none             | Blocks' netlists to stitch in (hierarchical results) |
| `TB`          | make  | `tb_<top_level>` | Bench (same `POST_SYN_SIM` branch as post-syn GLS)   |
| `VCD`         | make  | 0                | Activity dump for post-route power analysis          |

## Notes and caveats

- The routed netlist keeps the top-level port interface of the synthesized one, so the same bench branch works unchanged for both GLS steps.
- CTS and repair cells are ordinary library cells — nothing new to model; the sequential-cell substitution file covers the flops and clock gates as before.
- In hierarchical runs, forgetting `MACRO_DIRS` fails at compile time with unresolved macro modules — a loud, safe failure.
- The VCD from a hierarchical run contains the macro-internal activity (the blocks are elaborated, not abstracted) — the property the full-view power analysis builds on.

## Commercial perspective

Identical positioning to post-syn GLS in commercial flows, with the post-route variant usually run SDF-annotated at signoff corners as the classic "tapeout gate sim". The zero-delay functional form used here is their fast-regression mode.

Source: [run.sh](../../post-pnr-sim/run.sh) — [filelist.f](../../post-pnr-sim/filelist.f) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
