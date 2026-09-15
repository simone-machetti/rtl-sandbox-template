# Post-place-and-route static timing analysis

The definitive timing measurement: the routed netlist with extracted parasitics and the real, propagated clock tree. The idealizations of pre-layout STA are gone — this is the number a datasheet would quote.

## Inputs and outputs

**Inputs**

- Post-pnr netlist `.v`
- Library of cells `.lib` (Liberty)
- Post-pnr parasitics `.spef`
- Constraints, generated inline (as in POST-SYN-STA), clocks propagated
- Hardened-block timing models `.lib` (`MACRO_DIRS`, hierarchical results)
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required); `MACRO_DIRS` (optional)

**Outputs**

- Timing reports (`unconstrained.rpt`, `critical_paths.rpt`, `wns.rpt`, `tns.rpt`)

## Theory

All STA theory from [03_post_syn_sta.md](03_post_syn_sta.md) carries over; two upgrades change the numbers:

- **Extracted parasitics.** `read_spef` replaces "zero-delay nets" with each net's real RC network from the routed geometry ([10_pnr_final.md](10_pnr_final.md)). Wire delay and its effect on cell delay (output load, input slew degradation) now come from the layout. This is why post-route WNS is worse than pre-layout WNS on the same design at the same clock — the delta *is* the wires.
- **Propagated clocks.** With the netlist containing the actual clock tree and the SPEF its wires, `set_propagated_clock` makes every check use measured clock arrivals: insertion delay appears explicitly in path reports ("clock network delay (propagated)"), and skew between flops is real. Hold analysis is now meaningful — though this step, like its pre-layout sibling, reports setup (`-path_delay max`); the flow's hold enforcement happened in routing's repair, and a hold report is one `-path_delay min` away when wanted.

Why this step exists at all when stage 5 already reported timing: separation of concerns — an analysis step that consumes only the run directory's *files* (netlist + SPEF), independent of the P&R session. Its agreement with the in-flow reports is a consistency check of the whole file contract, and the step works identically on any P&R run, current or archived.

## Implementation walkthrough

`scripts/post-pnr-sta/run.tcl`, highlighting the deltas against post-syn STA:

```tcl
set REPORT_DIR $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report
file mkdir $REPORT_DIR

read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

if {$env(SEL_MACRO_DIRS) ne "none"} {
    foreach dir $env(SEL_MACRO_DIRS) {
        read_liberty $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$dir/output/timing_model.lib
    }
}
```

Delta one: in hierarchical runs, each hardened block's generated `timing_model.lib` is loaded like a cell library — the parent's macro instances will link against these, and paths will be timed *through* the blocks via their condensed arcs.

```tcl
read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design  $env(SEL_TOP_LEVEL)
```

The routed netlist, satisfying the same contract as a synthesis netlist — the reason this script is a near-copy of the post-syn one.

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

The shared scheme ([02_constraints.md](../concepts/constraints.md)), unchanged — same period, same I/O modeling, so pre- and post-layout reports are comparable path-for-path.

```tcl
# -----------------------------------------------------------------------------
# Post-route parasitics
# -----------------------------------------------------------------------------
read_spef $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.spef
set_propagated_clock [all_clocks]
```

Delta two, the heart of the step: the extracted parasitics, then real clock arrivals. Order matters — propagating before the SPEF would compute tree latencies on ideal wires.

```tcl
report_checks -unconstrained > $REPORT_DIR/unconstrained.rpt
report_checks \
    -path_delay max \
    -fields {slew cap input_pins} \
    -digits 4 \
    -group_path_count 10 \
    > $REPORT_DIR/critical_paths.rpt
report_wns > $REPORT_DIR/wns.rpt
report_tns > $REPORT_DIR/tns.rpt
```

The same four reports as post-syn STA — by design: reading the two runs' `critical_paths.rpt` side by side shows exactly what implementation did to each path (wire delay entries, clock network lines, repair-inserted buffers).

## Design space

- **Hold reporting**: `-path_delay min` (or `min_max`) turns on hold reports — worth running once per design generation to confirm routing's hold repair converged with margin.
- **SI-aware timing**: coupling-annotated SPEF plus a crosstalk-capable timer upgrades to signal-integrity analysis (aggressor-induced delay deltas) — the main accuracy step this flow doesn't take.
- **Multi-corner**: the same script re-pointed at SS/FF liberty (plus per-corner extraction) is the signoff pattern; single-corner TT here.
- **Derating/uncertainty**: adding OCV derates or a nonzero uncertainty models variation; the flow keeps analysis and implementation targets identical instead.

## Knobs

| Knob            | Where | Default | Effect / tradeoff                                    |
| --------------- | ----- | ------- | ---------------------------------------------------- |
| `CLK_PERIOD_NS` | make  | 1.0     | Analysis period — use the implementation's for truth |
| `NETLIST_DIR`   | make  | —       | Which P&R run to analyze                             |
| `MACRO_DIRS`    | make  | none    | Blocks' timing models (hierarchical results)         |

## Notes and caveats

- Analyzing at a period different from the implementation's is legitimate *exploration* (measuring margin), but the routed design was optimized for its own target — slack at other periods is descriptive, not a design promise.
- This step's WNS reproducing the P&R's final report is the expected consistency check; disagreement means the run directory's files are stale or mixed.
- In hierarchical mode the macro timing models carry timing only — fine here; power is the other step's problem ([14_post_pnr_dpa.md](14_post_pnr_dpa.md)).
- The clock-network-delay line in each path is the visible signature of propagated analysis — its absence means the SPEF/propagation block didn't run.

## Commercial perspective

This is the role PrimeTime/Tempus play as *the* signoff gate, with SI, multi-corner-multi-mode scenarios, POCV, and ECO generation on top. The structural pattern — implementation tool reports during the flow, independent timer re-verifies from files — is exactly the industrial signoff separation, reproduced here open-source.

Source: [run.tcl](../../post-pnr-sta/run.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
