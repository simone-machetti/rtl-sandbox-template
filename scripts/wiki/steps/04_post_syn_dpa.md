# Post-synthesis dynamic power analysis

Power estimation from real switching activity: the gate-level simulation's VCD is annotated onto the netlist and every cell's energy is summed. The pre-layout member of the pair — its post-route sibling ([14_post_pnr_dpa.md](14_post_pnr_dpa.md)) adds real wire capacitances.

## Inputs and outputs

**Inputs**

- Post-syn netlist `.v`
- Library of cells `.lib` (Liberty)
- Post-syn switching activity `.vcd` (annotated onto scope `<TB>/dut`)
- Constraints, generated inline (as in POST-SYN-STA)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR`, `VCD_DIR` (required); `TB`, `KEEP_HIERARCHY`, `KEEP_MODULES`, `BLACKBOX_MODULES` (optional)

**Outputs**

- Power reports (`power_summary.rpt`, `power_hierarchy.rpt` with hierarchy, VCD annotation reports)

## Theory

CMOS power splits into three components, and the report keeps them separate:

- **Switching power** — charging/discharging net capacitance: ½·C·V²·f per net, weighted by its *activity* (transitions per second). Scales with capacitance and the square of supply voltage.
- **Internal power** — energy burned inside a cell per transition (short-circuit current, internal node capacitance), tabulated in the liberty per arc.
- **Leakage** — state-dependent static current, drawn always, tabulated in the liberty per cell.

The quality of the estimate is the quality of the **activity** numbers. Three sources exist, in increasing fidelity: static defaults (assume some toggle probability everywhere — fast, blind to real behavior), propagated probabilities (assign inputs, propagate statistically), and **simulation-annotated activity** — this flow's method: the VCD from gate-level simulation gives every net its measured transition count under the actual stimulus. That makes power *workload-dependent*, which is the point: the same netlist under different operating modes can differ by tens of percent, and only annotated analysis sees it.

The known systematic bias at this stage: the VCD comes from a **zero-delay** simulation, where each net transitions at most once per cycle — real logic **glitches** (intermediate transitions while a cone settles), so deep combinational structures under-report switching power. And pre-layout, net capacitances are unknown — pin capacitances dominate the estimate; the post-route version adds extracted wire caps.

## Implementation walkthrough

`scripts/post-syn-dpa/run.tcl`, block by block (loading and constraints are as in [03_post_syn_sta.md](03_post_syn_sta.md) / [02_constraints.md](../concepts/constraints.md)):

```tcl
set REPORT_DIR $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report
```

```tcl
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design $env(SEL_TOP_LEVEL)
```

Liberty here serves double duty: the same files carry the *power* tables (internal energy, leakage) next to the timing tables.

```tcl
set CLK_PERIOD_PS [expr {$env(SEL_CLK_PERIOD_NS) * 1000}]

if {[llength [get_ports -quiet clk_i]] > 0} {
    create_clock -name clk_i -period $CLK_PERIOD_PS [get_ports clk_i]
}
create_clock -name vclk -period $CLK_PERIOD_PS

set data_in {}
foreach port [all_inputs] {
    if {[lsearch -exact {clk_i rst_ni} [get_property $port full_name]] < 0} {
        lappend data_in $port
    }
}
if {[llength $data_in] > 0} {
    set_input_delay 0 -clock vclk $data_in
    set_false_path -hold -from $data_in
}
if {[llength [all_outputs]] > 0} {
    set_output_delay 0 -clock vclk [all_outputs]
    set_false_path -hold -to [all_outputs]
}
```

The shared scheme. Power analysis needs the clock for two reasons: activity normalization (transitions per *period*) and slew computation along the clock network.

```tcl
set vcd_verilator "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/sim/$env(SEL_VCD_DIR)/output/activity.vcd"
read_vcd -scope $env(SEL_TB)/dut $vcd_verilator

report_activity_annotation -report_annotated   > $REPORT_DIR/vcd_annotated.rpt
report_activity_annotation -report_unannotated > $REPORT_DIR/vcd_unannotated.rpt
```

The heart of the step. `read_vcd -scope <TB>/dut` aligns the VCD's hierarchy with the linked netlist: the bench's DUT instance — which the flow's bench convention therefore *requires* to be named `dut` — is mapped onto the design top, and every matching net receives its measured activity. The two annotation reports are the health check: the annotated count should cover essentially all pins, and the unannotated report should be near-empty. **A poor match does not error — it silently degrades** the estimate toward defaults, which is why the reports are always written and worth reading.

```tcl
report_power > $REPORT_DIR/power_summary.rpt

if {$env(SEL_KEEP_HIERARCHY) eq "1" ||
    $env(SEL_KEEP_MODULES) ne "none" ||
    $env(SEL_BLACKBOX_MODULES) ne "none"} {
    report_power -instances [get_cells -hierarchical *] > $REPORT_DIR/power_hierarchy.rpt
}
```

The summary table (internal/switching/leakage × sequential/combinational/clock/macro/pad) and, when the netlist preserved hierarchy, a per-instance breakdown — the tool that turns "total power" into "which module burns it". The per-instance report requires module boundaries in the netlist, hence the condition mirroring the synthesis hierarchy options.

## Design space

- **Activity formats**: SAIF (accumulated toggle counts, much smaller than VCD) is the classic alternative; OpenSTA reads both. VCD keeps time-windowing possible (analyzing only a slice of the run).
- **Vectorless analysis**: `set_power_activity` on inputs plus propagation — instant but workload-blind; useful only for gross sanity checks.
- **Per-mode methodology**: running one gate-level simulation and one DPA per operating mode (same netlist, different stimulus) turns the workload-dependence into the *measurement* — the flow's plumbing supports it directly by pairing `VCD_DIR`s with runs.
- **Glitch-aware power** needs a delay-annotated GLS (SDF + event-driven simulator) so intermediate transitions appear in the VCD — the main known upgrade path for absolute accuracy.

## Knobs

| Knob                                               | Where | Default          | Effect / tradeoff                                   |
| -------------------------------------------------- | ----- | ---------------- | --------------------------------------------------- |
| `CLK_PERIOD_NS`                                    | make  | 1.0              | Frequency for normalization — power scales with it  |
| `NETLIST_DIR` / `VCD_DIR`                          | make  | —                | The netlist and the activity trace to combine       |
| `TB`                                               | make  | `tb_<top_level>` | Must match the bench that produced the VCD          |
| `KEEP_HIERARCHY`/`KEEP_MODULES`/`BLACKBOX_MODULES` | make  | off              | Enables the per-instance report (match the syn run) |

## Notes and caveats

- The `<TB>/dut` scope convention is load-bearing: a bench whose DUT instance is not named `dut` produces a silently unannotated (i.e. near-meaningless) analysis. Check `vcd_annotated.rpt` / `vcd_unannotated.rpt` on every new bench.
- Zero-delay VCDs under-count glitches; treat absolute numbers accordingly and prefer A-vs-B comparisons under identical stimulus.
- Pre-layout, wire capacitance is absent — post-route DPA on the same design runs noticeably higher, and the delta is real physics (wires, clock tree), not noise.
- Power scales linearly with frequency in the report: compare runs only at equal `CLK_PERIOD_NS`.

## Commercial perspective

PrimePower (and Voltus for implementation-side power) are the commercial versions, with the same activity-annotated methodology plus glitch propagation from SDF simulations, RTL-stage power estimation, and vector profiling across long workloads. The summary/per-instance report structure translates directly.

Source: [run.tcl](../../post-syn-dpa/run.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
