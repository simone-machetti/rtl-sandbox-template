# Post-synthesis static timing analysis

The first timing measurement of the netlist: exhaustive, vectorless, and — at this stage — under ideal wires and ideal clocks. Its numbers calibrate the clock target for everything downstream.

## Inputs and outputs

**Inputs**

- Post-syn netlist `.v`
- Library of cells `.lib` (Liberty)
- Constraints, generated inline from `CLK_PERIOD_NS`: clock on `clk_i` (if present) + virtual clock with zero I/O delays, hold false-pathed on I/O
- Make parameters: `PROJECT`, `TOP_LEVEL`, `CLK_PERIOD_NS`, `OUT_DIR`, `NETLIST_DIR` (required)

**Outputs**

- Timing reports (`unconstrained.rpt`, `critical_paths.rpt`, `wns.rpt`, `tns.rpt`)

## Theory

**Static timing analysis** verifies timing without simulation: it enumerates every register-to-register, input, and output path, sums cell delays (from the liberty NLDM tables, functions of input slew and output load) and wire delays along each, and compares the **arrival time** at each endpoint against the **required time** implied by the constraints. The difference is **slack** — negative slack is a violation. Because it is exhaustive, STA needs no vectors and cannot miss a path (the flip side: it also reports paths no vector could ever exercise — false paths, to be excluded by constraints when known).

Key vocabulary used by every report:

- **Setup check**: data must arrive one setup-time before the capturing clock edge — determines the maximum frequency. **Hold check**: data must not change sooner than a hold-time after the *same* edge — a race condition, period-independent.
- **WNS** (worst negative slack): the single worst path's slack — sets achievable frequency: `min_period = period − WNS`. **TNS** (total negative slack): the sum over all violating endpoints — measures how *widespread* violation is.
- **Path groups**: paths are reported per capturing clock; in this flow the real clock (`clk_i`) groups register paths and the virtual clock (`vclk`) groups the I/O paths.
- **Pre-layout idealizations**: wires contribute according to the estimated per-layer RC only in P&R; here, in pure OpenSTA with no parasitics file, nets are **zero-delay/zero-cap** — timing is optimistic — and clocks are **ideal** (no tree, no skew). Post-route STA ([13_post_pnr_sta.md](13_post_pnr_sta.md)) removes both idealizations; the empirically useful reading of *this* step is relative comparison and clock-target exploration, with margin for the layout to come.

## Implementation walkthrough

`scripts/post-syn-sta/run.tcl` in full, block by block:

```tcl
set REPORT_DIR $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_OUT_DIR)/report
file mkdir $REPORT_DIR
```

Report destination per the run-directory convention.

```tcl
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib
read_liberty $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib

read_verilog $env(REPO_HOME)/projects/$env(SEL_PROJECT)/imp/$env(SEL_NETLIST_DIR)/output/netlist.v
link_design  $env(SEL_TOP_LEVEL)
```

The standard loading sequence: timing models, then the netlist, then linking (every instance bound to a liberty cell; unresolved names error here).

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

The shared constraint scheme, explained line-by-line in [02_constraints.md](../concepts/constraints.md). Its effect here: register→register paths are constrained by `clk_i`, and all boundary paths (in→reg, reg→out, in→out) by the virtual clock — so the reports cover every path class, and a purely combinational netlist (no `clk_i` port) still produces meaningful in→out timing instead of an error.

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

Four reports: a sanity report of anything *still* unconstrained (should be only the reset); the ten worst paths per path group with per-stage slew/capacitance/input-pin detail (the report to read when asking *where* the nanoseconds go — each line is one cell traversal); and the two scalar summaries. `-path_delay max` selects setup analysis (`min` would report hold).

## Design space

- **Parasitics realism**: pre-layout STA can be made less optimistic with wire-load models (statistical net-length estimates — largely abandoned at advanced nodes) or SPEF from a trial placement; this flow simply defers realism to post-route STA.
- **Hold analysis** (`-path_delay min`) is omitted here deliberately: with ideal clocks hold is meaningless (no skew); it becomes real — and analyzed — after CTS.
- **Derating/OCV**: production STA multiplies delays by early/late derates (or uses statistical POCV) to model on-chip variation; single-corner TT without derates is the exploration-grade choice.
- **Report shaping**: `-group_path_count`, `-fields`, per-endpoint reports (`report_checks -to`), and bottleneck analysis (`report_check_types`) are the standard widening moves when one worst path is not enough information.

## Knobs

| Knob            | Where | Default | Effect / tradeoff                                |
| --------------- | ----- | ------- | ------------------------------------------------ |
| `CLK_PERIOD_NS` | make  | 1.0     | The reference period; WNS is measured against it |
| `NETLIST_DIR`   | make  | —       | Which netlist to analyze                         |

## Notes and caveats

- **Zero-wire optimism**: no SPEF and no `set_wire_rc` are loaded here, so nets are ideal; reported WNS is a lower bound on the real critical path.
- **The high-fanout artifact**: synthesized netlists carry unbuffered register-driven broadcast nets ([01_syn.md](01_syn.md)); on large flat or blackbox-linked netlists those nets show grotesque slews and dominate WNS. They are a real property of *this netlist* but not of the eventual implementation (P&R's `repair_design` buffers them immediately) — pre-layout WNS of such netlists must not be used as a frequency claim. Component-level netlists, self-contained by construction, give the meaningful pre-layout numbers.
- Because analysis is linear in the period, one run at any period gives the minimum: `min_period = period − WNS`.
- Blackbox-linked netlists analyze fine (the linked modules carry real gates), but cross-boundary paths were never co-optimized — expect them pessimistic.

## Commercial perspective

PrimeTime and Tempus are the signoff members of this tool class; OpenSTA implements the same analysis model (and is itself the timer inside OpenROAD). What signoff adds: multi-corner-multi-mode analysis managed as scenarios, OCV/POCV variation modeling, SI-aware delay (crosstalk), and ECO loops driven from the timing database. The reports and their reading are identical in kind.

Source: [run.tcl](../../post-syn-sta/run.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
