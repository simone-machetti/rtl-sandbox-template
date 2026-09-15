# Example Top Testbench

## Purpose

`tb_top_example` verifies [top_example](../architectures/top_example.md), the registered multiply-accumulate vehicle, at **full throughput**: a fresh operand set with random per-operand signedness is driven into the input registers on every clock, and the registered result is checked against an exact golden delayed by the DUT's 2-cycle latency. Lanes are biased toward the extreme values so the sign corners of the multiplier and the tree are reached within a few thousand vectors. It is also the bench the gate-level flows run: compiled with `POST_SYN_SIM` it instantiates the synthesized or routed netlist through its flattened array ports, and with `VCD` it dumps the `activity.vcd` the power flows annotate.

## Parameters

| Parameter  | Default | Description                                                             |
| ---------- | ------- | ----------------------------------------------------------------------- |
| `NUM_RAND` | `2000`  | Number of random streamed vectors before the directed sweeps.           |
| `LANES`    | `4`     | Number of lanes; passed to the DUT in RTL mode, must match the netlist. |
| `WIDTH_A`  | `8`     | Width of `a`; passed to the DUT in RTL mode, must match the netlist.    |
| `WIDTH_B`  | `8`     | Width of `b`; passed to the DUT in RTL mode, must match the netlist.    |

The clock period comes from the flow's `CLK_PERIOD_NS` define (default 10 ns when compiled by hand); the settle delay after each edge is a tenth of it.

## Run

```bash
make sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_top_example
make sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_top_example_8x4 PARAMS="LANES=8 WIDTH_B=4"
make post-syn-sim PROJECT=example TOP_LEVEL=top_example CLK_PERIOD_NS=1.5 OUT_DIR=sim_post_syn_top_example NETLIST_DIR=syn_top_example VCD=1
```

The `PARAMS` overrides reach both the bench and, through it, the DUT; in a gate-level run the netlist has a fixed shape, so leave the parameters at the values it was synthesized with.

## What it checks

| Property | Check                                                                                     |
| -------- | ----------------------------------------------------------------------------------------- |
| Value    | `$signed(out_o)` sign-extended to 64 bits equals `Σ_k a_k · b_k` exactly, every cycle     |
| Latency  | the result sampled after the rising edge of iteration `t` matches the operands of `t − 1` |

All four `is_signed_a × is_signed_b` combinations occur (randomly during the stream, exhaustively in the sweeps). Any mismatch is **fatal** and stops the run with the expected and observed values and the flags.

## How it checks

### Stimulus generation

`rand_vec` fills each lane with roughly 20 % most-negative, 20 % max-positive, 60 % uniform values and draws both signedness flags at random:

```systemverilog
task automatic rand_vec;
    int pa, pb;
    for (int i = 0; i < LANES; i++) begin
        pa = $urandom % 5;
        pb = $urandom % 5;
        a_v[i] = (pa == 0) ? A_MIN_NEG : (pa == 1) ? A_MAX_POS : WIDTH_A'($urandom);
        b_v[i] = (pb == 0) ? B_MIN_NEG : (pb == 1) ? B_MAX_POS : WIDTH_B'($urandom);
    end
    is_signed_a = 1'($urandom % 2);
    is_signed_b = 1'($urandom % 2);
endtask
```

After the stream, `set_vec` pins every lane to a directed corner (all-zero, both max-positive, both min-negative, the two mixed pairs, all-ones) and `sweep_signs` runs each under the four flag combinations.

### The golden reference

Computed outside the DUT in a 64-bit `longint`, from the operands re-interpreted per the flags:

```systemverilog
a_val = is_signed_a ? longint'($signed(a_v[i])) : longint'($unsigned(a_v[i]));
b_val = is_signed_b ? longint'($signed(b_v[i])) : longint'($unsigned(b_v[i]));
e    += a_val * b_val;
```

### Pipeline alignment

`step_check` computes the golden for the operands currently driven, waits one rising edge plus the settle delay, and then checks the output against the golden of the *previous* iteration — the 2-cycle latency means each result belongs to the operands driven one iteration earlier. The first iteration after reset only primes `exp_prev`.

```systemverilog
task automatic step_check;
    longint exp_now;
    exp_now = golden();
    @(posedge clk_i);
    #(T_SETTLE);
    if (have_prev) check_out(exp_prev);
    have_prev = 1;
    exp_prev  = exp_now;
endtask
```

### Gate-level branch

Synthesis flattens the unpacked array ports into vectors and drops the parameters, so under `POST_SYN_SIM` the bench packs the lanes itself — lane 0 in the top bits, matching the netlist — and instantiates `top_example` without a parameter list:

```systemverilog
a_flat[(LANES-1-i)*WIDTH_A +: WIDTH_A] = a_v[i];
```

The DUT instance is named `dut` in both branches, which is the scope `make post-syn-dpa` / `make post-pnr-dpa` annotate the VCD on.

If every vector passes, the bench prints `top_example: all N random + corner tests PASSED!` and calls `$finish`.

Source: [tb_top_example.sv](../../tb/tb_top_example.sv) — DUT: [top_example](../architectures/top_example.md)
