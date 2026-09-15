# Constraints — clocks, I/O timing, and the shared scheme

Constraints tell the timing engine what "fast enough" means: without them a netlist has no failing or passing paths, only delays. This flow generates its constraints inline, from a single make parameter, with one identical scheme used by every analysis step and by place-and-route — this document explains both the theory and that scheme.

## Inputs and outputs

- **Inputs**: `CLK_PERIOD_NS` (converted to ps) and `CLK_UNCERTAINTY_PS` (P&R only); the linked design's port list.
- **Outputs**: clocks and I/O constraints in the timing engine's memory (and, from P&R, the as-implemented `output/design.sdc`).

## Theory

### SDC in one page

**SDC** (Synopsys Design Constraints) is the industry-standard Tcl vocabulary for timing intent. The essential commands:

- `create_clock -period T [get_ports p]` — declares a clock of period `T` entering at port `p`. Every register clocked by it gets **setup checks** (data must arrive before the *next* edge minus setup time — the speed limit) and **hold checks** (data must not arrive so early it corrupts the *current* edge — a race, independent of period).
- A **virtual clock** is a clock created without a source port: it exists only as a timing reference for the world outside the block.
- `set_input_delay D -clock C [ports]` — models the outside world on an input: "data arrives `D` after clock `C`'s edge". Together with the period this constrains the input-to-register path. `set_output_delay` is the mirror for outputs (register-to-output paths).
- `set_false_path` — excludes paths from analysis; with `-hold`/`-setup` it excludes only that check type.
- `set_clock_uncertainty` — margin subtracted from every check, representing jitter and modeling pessimism.

Path classes covered by a complete constraint set: register→register (period-constrained), input→register and register→output (period plus I/O delays), input→output (purely combinational, both I/O delays). Unconstrained paths are *invisible* to optimization and reporting — the classic silent failure of a minimal constraint set.

### Ideal vs propagated clocks

Before a clock tree exists, clocks are **ideal**: they arrive everywhere at t = 0. After CTS the flow switches to **propagated** clocks: arrival at each register includes the real, measured tree delay (the *insertion delay*, typically ~100 ps in blocks this size). Setup slack is largely insensitive to shared insertion delay (both launch and capture shift), but **hold becomes real** — skew between two registers' arrivals is exactly what hold checks fight — which is why hold repair happens only after CTS.

## Implementation walkthrough

The canonical copy, `scripts/pnr/constraints.tcl`, in full:

```tcl
set CLK_PERIOD_PS [expr {$::env(SEL_CLK_PERIOD_NS) * 1000}]

if {[llength [get_ports -quiet clk_i]] > 0} {
    create_clock -name clk_i -period $CLK_PERIOD_PS [get_ports clk_i]
}
create_clock -name vclk -period $CLK_PERIOD_PS
```

The ns→ps conversion happens here, once ([01_technology.md](technology.md): liberty is in ps). The real clock is created **only if the port `clk_i` exists** — the flow's convention for "the clock input" — so purely combinational blocks pass through the same scripts without error (`-quiet` suppresses the not-found complaint). The **virtual clock** `vclk` is always created, same period, and serves as the reference for all I/O timing: it stands for the registers of the surrounding system that launch our inputs and capture our outputs.

```tcl
set data_in {}
foreach port [all_inputs] {
    if {[lsearch -exact {clk_i rst_ni} [get_property $port full_name]] < 0} {
        lappend data_in $port
    }
}
```

Collects every input port except the clock and the reset (`rst_ni` — asynchronous, its timing is not data timing). Written as a plain Tcl filter because OpenSTA does not implement the `remove_from_collection` command found in commercial SDC dialects.

```tcl
if {[llength $data_in] > 0} {
    set_input_delay 0 -clock vclk $data_in
    set_false_path -hold -from $data_in
}
if {[llength [all_outputs]] > 0} {
    set_output_delay 0 -clock vclk [all_outputs]
    set_false_path -hold -to [all_outputs]
}
```

Zero-valued I/O delays against the virtual clock constrain **all four path classes** by exactly one clock period — the neutral choice when the integration context is unknown: it makes boundary paths visible, optimizable and reported, without asserting anything about the neighbors.

The two `set_false_path -hold` lines are the subtle part. A hold check on an input path compares an **ideal-launch** edge (vclk, no clock tree, t = 0) against a **propagated-capture** edge (the real tree, ~100 ps later at the flop). The launch side's missing insertion delay makes every input path look like a hold violation of roughly the insertion delay — an artifact of the model, not of the design: any real driver sits behind its own clock tree with comparable latency. Left constrained, hold *repair* in routing chases these phantoms with delay buffers (hundreds of them, until the repair engine gives up). Block-level practice is exactly this exclusion: hold at the boundary is decided at integration time, by the parent's analysis, with real latencies on both sides. Setup on I/O paths — the meaningful part — remains fully constrained; internal register→register hold also remains fully checked and repaired.

```tcl
if {$::env(SEL_CLK_UNCERTAINTY_PS) > 0} {
    set_clock_uncertainty $::env(SEL_CLK_UNCERTAINTY_PS) [all_clocks]
}
```

Optional margin (default 0 = off), applied to all clocks so I/O and internal checks stay consistent.

Two placement details of the scheme: in P&R the file is re-sourced after every checkpoint load because the ODB database does not persist SDC ([05_pnr_overview.md](../steps/05_pnr_overview.md)); and `set_propagated_clock [all_clocks]` is issued by the stages/steps that own a real clock tree — CTS onwards and the post-P&R analyses (a virtual clock cannot be propagated; the tool notes it with a benign warning).

## Design space

- **Non-zero I/O budgets.** `set_input_delay 0` gives boundary paths the full period; a real integration splits the period between producer and consumer (e.g. 60/40). Making the delays a knob would let a block be pre-hardened against its planned context.
- **Real reset constraints.** `rst_ni` is left unconstrained (asynchronous); a signoff flow would add recovery/removal analysis or an explicitly false-pathed synchronized reset.
- **Multiple clocks.** The scheme is single-clock by convention; more clocks mean more `create_clock` lines plus `set_clock_groups -asynchronous` between unrelated domains — the analysis machinery is already capable.
- **Environment realism.** `set_driving_cell` (input slew from a real driver instead of an ideal edge) and `set_load` (output pin capacitance) are the standard next-step refinements; without them boundary timing is slightly optimistic.
- **Uncertainty policy.** Production flows use larger pre-CTS uncertainty (covering unknown skew) and shrink it post-CTS; the flow's single number is a simplification.
- **Overconstraining** (`set_max_delay`, tighter-than-real periods) is a common tactic to bank margin during optimization; unused here — the delay target equals the analysis clock.

## Knobs

| Knob                 | Where | Default | Effect / tradeoff                                                     |
| -------------------- | ----- | ------- | --------------------------------------------------------------------- |
| `CLK_PERIOD_NS`      | make  | 1.0     | The one timing target: every setup check, and P&R's optimization goal |
| `CLK_UNCERTAINTY_PS` | make  | 0       | Safety margin; ↑ = more pessimism, more repair effort, more area      |

## Notes and caveats

- The clock port name `clk_i` is a flow-wide convention, hardcoded in the scheme; a design using another name gets treated as clockless.
- Values are **picoseconds** in every command downstream of the one conversion.
- The hold-false-path exclusion applies to I/O only; internal hold is fully analyzed and repaired after CTS.
- The identical block is deliberately duplicated across the five consumer scripts (repository style favors self-contained scripts); a change to the scheme must be applied to all copies.
- P&R writes the effective constraints out as `output/design.sdc` — the ground truth of what a run was actually optimized against.

## Commercial perspective

SDC is the lingua franca — the same commands drive Design Compiler, PrimeTime and Innovus. Production constraint decks add what integration demands: per-mode constraint sets (functional/test/scan) with mode merging, exhaustive exceptions (multicycle paths, logically-exclusive clock groups), I/O budgets negotiated per interface, and OCV/POCV derating in place of a single uncertainty number. The virtual-clock I/O scheme and the boundary-hold deferral used here are standard block-level practice in those flows too.

Source: [constraints.tcl](../../pnr/constraints.tcl) — Reference: [asic_flow.md](../../asic_flow.md) — Index: [index.md](../index.md)
