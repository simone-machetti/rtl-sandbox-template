# Pre-synthesis simulation

The first step of the pipeline: proving the RTL functionally correct before anything downstream spends effort on it, and producing the switching-activity traces power analysis will later consume.

## Inputs and outputs

**Inputs**

- RTL files `.sv` (`projects/<project>/rtl/`)
- Testbench `.sv` (`projects/<project>/tb/tb_<top>.sv`)
- Lint waivers `.vlt`
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR` (required); `TB`, `PARAMS`, `VCD` (optional)

**Outputs**

- Simulation binary + logs (`compile.log`, `run.log`)
- Switching activity `.vcd` (with `VCD=1`)

## Theory

Two families of logic simulators exist. **Event-driven** simulators (the classic commercial tools) schedule every signal change as an event, support the full IEEE 4-state semantics (`0/1/X/Z`) and delay annotation. **Compiled/cycle-oriented** simulators translate the design into optimized C++ and evaluate it clock by clock — orders of magnitude faster, at the cost of restricted semantics. Verilator is the leading open-source member of the second family; in its modern `--timing` mode it also handles delays and event controls in *testbench* code (`#(...)` waits, `@(posedge ...)`), which is what allows a plain SystemVerilog bench to drive it without a C++ harness.

A **VCD** (value change dump) records every transition of the traced signals over time. It is both a debugging artifact (waveform viewing) and, in this flow, the input to dynamic power analysis: transition counts per net are exactly what power estimation needs ([04_post_syn_dpa.md](04_post_syn_dpa.md)). Tracing is expensive — it can dominate runtime and produce very large files — hence off by default.

The testbench convention this flow assumes: a self-checking bench named `tb_<top_level>` that instantiates the design, generates stimuli, checks responses against a golden model, ends with `$finish`, and (for the power path) names its DUT instance `dut` and dumps `activity.vcd` under `` `ifdef VCD ``.

## Implementation walkthrough

`scripts/sim/run.sh`, block by block:

```bash
set -euo pipefail

PROJ="${REPO_HOME}/projects/${SEL_PROJECT}"
SIM="${PROJ}/sim/${SEL_OUT_DIR}"
```

Strict bash mode (any failing command aborts the run, pipes included) and the run directory, resolved from the exported make parameters.

```bash
g_flags=()
if [ "${SEL_PARAMS}" != "none" ]; then
    for param in ${SEL_PARAMS}; do
        g_flags+=("-G${param}")
    done
fi
```

Elaboration parameters: each `KEY=VAL` from `PARAMS` becomes a Verilator `-GKEY=VAL`, overriding a top-level SystemVerilog `parameter` — how one testbench/top pair serves a whole family of design sizes.

```bash
inc_flags=()
while IFS= read -r d; do
    inc_flags+=(-I"$d")
done < <(find "${PROJ}/rtl" -type d | sort)

vlt_files=()
while IFS= read -r f; do
    vlt_files+=("$f")
done < <(find "${PROJ}/rtl" -name "*.vlt" | sort)
```

Every directory under `rtl/` becomes an include path (the bench includes nothing explicitly — modules are found by name), and any `.vlt` files are collected: Verilator *configuration* files carrying lint waivers, keeping pragma noise out of the RTL itself.

```bash
trace_flags=()
if [ "${SEL_VCD:-0}" = "1" ]; then
    trace_flags=(--trace --trace-max-array 0 --trace-max-width 0 --output-split 20000 -DVCD)
fi
```

Tracing is opt-in. `--trace` compiles VCD instrumentation in; the two `-max` options remove Verilator's default width/array tracing limits (wide datapaths would otherwise silently vanish from the dump); `--output-split` splits the generated C++ into smaller files so the C compiler copes with instrumented large designs; `-DVCD` activates the bench's `$dumpfile/$dumpvars` block.

```bash
verilator \
    -sv \
    --build-jobs 0 \
    --binary \
    --timing \
    "${trace_flags[@]}" \
    -Wall \
    -Wno-fatal \
    -DCLK_PERIOD_NS="${SEL_CLK_PERIOD_NS}" \
    "${g_flags[@]}" \
    "${inc_flags[@]}" \
    "${vlt_files[@]}" \
    --top-module "${SEL_TB}" \
    "${PROJ}/tb/${SEL_TB}.sv" \
    -Mdir "${SIM}/build/obj_dir" \
    -o "${SIM}/build/simv" \
    | tee "${SIM}/output/compile.log"
```

The single compile-and-build call: SystemVerilog mode, parallel C++ build (`--build-jobs 0` = all cores), `--binary` (produce a standalone executable — no hand-written C++ main), `--timing` (support the bench's delay/event constructs), full lint (`-Wall`) demoted to warnings (`-Wno-fatal` — the flow's RTL is expected lint-clean; the bench may waive specifics via `.vlt`). The clock period reaches the bench as the `CLK_PERIOD_NS` preprocessor define — the bench derives its clock generator from it. The top module is the *testbench*, and the model plus executable land in the run's `build/`.

```bash
exec "${REPO_HOME}/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/build/simv" "$@" \
    | tee "${REPO_HOME}/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/output/run.log"
```

Runs the simulation, teeing the bench's output to `run.log`. Extra arguments pass through to the binary — the mechanism benches use for runtime plusargs (`+mode=...`, `+vectors=...`). The Makefile afterwards moves the `activity.vcd` (dumped in the script's working directory) into `output/`.

## Design space

- **Simulator choice.** Event-driven simulators (Icarus open-source; Questa/VCS/Xcelium commercial) offer 4-state X-propagation semantics and SDF back-annotation, at far lower speed. Verilator's 2-state model means uninitialized-signal bugs may hide; the flow accepts this for speed and revisits X-behavior at gate level ([02_post_syn_sim.md](02_post_syn_sim.md)).
- **Tracing format.** FST (Verilator's `--trace-fst`) is far smaller than VCD and loads faster in viewers — but the power-analysis step consumes VCD, so VCD stays the flow's interchange format.
- **Scope-limited tracing** (dumping only the DUT rather than everything) trades debug visibility for speed/size; the bench's `$dumpvars` target controls it.
- **Verification depth.** The flow's convention is directed + constrained-random self-checking benches; the natural extensions are seed management for regression randomization, functional coverage, and assertion use — all orthogonal to the flow plumbing.

## Knobs

| Knob            | Where | Default          | Effect / tradeoff                                               |
| --------------- | ----- | ---------------- | --------------------------------------------------------------- |
| `TB`            | make  | `tb_<top_level>` | Selects an alternative bench for the same top                   |
| `CLK_PERIOD_NS` | make  | 1.0              | Bench clock period (functional runs rarely care; power runs do) |
| `PARAMS`        | make  | none             | Elaboration parameters → design size/configuration              |
| `VCD`           | make  | 0                | Activity dump for power analysis; large runtime and file cost   |

## Notes and caveats

- Verilator is 2-state by default: X-related bugs (missing resets) can pass here and surface only in gate-level simulation.
- The `--trace-max-*` overrides matter: without them, signals wider than 256 bits or deep arrays are silently absent from the VCD — and silently unannotated in power analysis later.
- The VCD is written in the tool's working directory and moved by the Makefile — a bench must call it `activity.vcd` for the flow to pick it up.
- `-Wno-fatal` keeps warnings advisory; the repository's expectation is that RTL lints clean with `-Wall` regardless.

## Commercial perspective

The same step under commercial tools (Questa/VCS/Xcelium) differs mainly in semantics (4-state, SDF-annotatable, UVM ecosystems) rather than in flow position. A common industrial pattern mirrors this repo exactly: Verilator for fast functional regression, an event-driven simulator for X-accurate and back-annotated runs.

Source: [run.sh](../../sim/run.sh) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
