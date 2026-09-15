# Multiply-Accumulate N Testbench

## Purpose

`tb_mac_n` verifies [mac_n](../modules/mac_n.md), the combinational multi-lane multiply-accumulate core, on its own — the block that is later hardened as a macro. It drives random corner-biased operand sets and directed extremes, checks each one under all four signedness combinations, and compares `out_o` with an exact 64-bit golden. There is no clock: every check drives the inputs, waits for the logic to settle, and samples the output.

## Parameters

| Parameter  | Default | Description                                                             |
| ---------- | ------- | ----------------------------------------------------------------------- |
| `NUM_RAND` | `2000`  | Number of random operand sets; each is checked four ways.               |
| `LANES`    | `4`     | Number of lanes; passed to the DUT in RTL mode, must match the netlist. |
| `WIDTH_A`  | `8`     | Width of `a`; passed to the DUT in RTL mode, must match the netlist.    |
| `WIDTH_B`  | `8`     | Width of `b`; passed to the DUT in RTL mode, must match the netlist.    |

## Run

```bash
make sim PROJECT=example TOP_LEVEL=mac_n CLK_PERIOD_NS=1.5 OUT_DIR=sim_mac_n
```

`CLK_PERIOD_NS` is required by the flow but unused by this clockless bench.

## What it checks

| Property | Check                                                                    |
| -------- | ------------------------------------------------------------------------ |
| Value    | `$signed(out_o)` sign-extended to 64 bits equals `Σ_k a_k · b_k` exactly |

Every vector is checked under `(is_signed_a, is_signed_b) ∈ {00, 01, 10, 11}`; any mismatch is **fatal**.

## How it checks

### Stimulus generation

Same corner-biased `rand_vec` as [tb_top_example](./tb_top_example.md), minus the flags (the sweep applies them): each lane is roughly 20 % most-negative, 20 % max-positive, 60 % uniform. After the random loop, `set_vec` pins every lane to the six directed corners.

### The signedness sweep and the compare

`check` drives the two flags, waits `#1` for the combinational logic to settle, computes the golden from the operands re-interpreted per the flags, and compares:

```systemverilog
task automatic check(input logic sgn_a, input logic sgn_b);
    is_signed_a = sgn_a;
    is_signed_b = sgn_b;
    #1;
    exp = golden();
    got = longint'($signed(out));
    if (got !== exp) begin $error(...); $fatal; end
endtask

task automatic check_all;
    check(1'b0, 1'b0); check(1'b0, 1'b1); check(1'b1, 1'b0); check(1'b1, 1'b1);
endtask
```

### Gate-level branch

Under `POST_SYN_SIM` the bench packs the lanes into flat vectors (lane 0 in the top bits) and instantiates `mac_n` without parameters, so the same bench simulates the synthesized or routed netlist of the hardened core. The DUT instance is named `dut`.

If every vector passes, the bench prints `mac_n: all N random + corner tests PASSED!` and calls `$finish`.

Source: [tb_mac_n.sv](../../tb/tb_mac_n.sv) — DUT: [mac_n](../modules/mac_n.md)
