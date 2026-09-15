# Example Top

`top_example` — the registered flow-validation vehicle: one [mac_n](../modules/mac_n.md) multiply-accumulate core between [reg_n](../modules/reg_n.md) input registers (operands and signedness flags) and a `reg_n` output register, so the design is a single clean reg-to-reg pipeline stage through a real multiplier and adder-tree datapath. Latency is **2 cycles**: operands are captured on the first rising edge, the registered result appears after the second.

## Purpose

A design just large enough to make every step of the flow meaningful — flip-flops for clock-tree synthesis and hold checks, a multi-level arithmetic datapath for the timing and power reports, and real module hierarchy for the `KEEP_HIERARCHY` / `BLACKBOX_MODULES` synthesis modes and the hard-macro place-and-route — while running each step in seconds. The shape is parameterized so the same top-level also demonstrates the flow's `PARAMS` elaboration overrides. It is not meant as an IP block: replace it with your own design.

## Parameters

| Parameter | Default | Description                                           |
| --------- | ------- | ----------------------------------------------------- |
| `LANES`   | 4       | Number of multiply lanes accumulated into the result. |
| `WIDTH_A` | 8       | Bit width of each `a` operand.                        |
| `WIDTH_B` | 8       | Bit width of each `b` operand.                        |

Derived `localparam`: `OUT_WIDTH = WIDTH_A + WIDTH_B + 1 + $clog2(LANES)` — 19 bits at the default shape (17-bit exact product plus 2 bits of tree growth).

## Interface

| Signal           | Dir | Width          | Description                                              |
| ---------------- | --- | -------------- | -------------------------------------------------------- |
| `clk_i`          | in  | 1              | Clock.                                                   |
| `rst_ni`         | in  | 1              | Asynchronous active-low reset; clears every register.    |
| `a_i[0:LANES-1]` | in  | `WIDTH_A` each | Operand `a` of each lane.                                |
| `b_i[0:LANES-1]` | in  | `WIDTH_B` each | Operand `b` of each lane.                                |
| `is_signed_a_i`  | in  | 1              | `a` signedness: `1` = two's complement, `0` = unsigned.  |
| `is_signed_b_i`  | in  | 1              | `b` signedness: `1` = two's complement, `0` = unsigned.  |
| `out_o`          | out | `OUT_WIDTH`    | Registered `Σ a_i[k] · b_i[k]`, two's complement, exact. |

After synthesis the unpacked array ports are flattened into vectors (`a_i[LANES*WIDTH_A-1:0]`, lane 0 in the top bits), which is what the `POST_SYN_SIM` branch of [tb_top_example](../testbenches/tb_top_example.md) drives.

## Instantiation

```systemverilog
top_example #(.LANES(4), .WIDTH_A(8), .WIDTH_B(8)) top_example_i (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .a_i          (a),            // logic [7:0] a [0:3]
    .b_i          (b),            // logic [7:0] b [0:3]
    .is_signed_a_i(is_signed_a),
    .is_signed_b_i(is_signed_b),
    .out_o        (out)           // logic [18:0]
);
```

## Internal logic

Purely structural: three input register banks, the core, one output register bank.

```systemverilog
reg_n #(.WIDTH(WIDTH_A), .SIZE(LANES)) reg_a_i   (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(a_i),   .q_o(a_q));
reg_n #(.WIDTH(WIDTH_B), .SIZE(LANES)) reg_b_i   (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(b_i),   .q_o(b_q));
reg_n #(.WIDTH(1),       .SIZE(2))     reg_sgn_i (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(sgn_d), .q_o(sgn_q));

mac_n #(.LANES(LANES), .WIDTH_A(WIDTH_A), .WIDTH_B(WIDTH_B)) mac_n_i (
    .a_i(a_q), .b_i(b_q), .is_signed_a_i(sgn_q[0]), .is_signed_b_i(sgn_q[1]), .out_o(out_d[0])
);

reg_n #(.WIDTH(OUT_WIDTH), .SIZE(1)) reg_out_i (.clk_i(clk_i), .rst_ni(rst_ni), .d_i(out_d), .q_o(out_q));
assign out_o = out_q[0];
```

- **Input stage** — `reg_a_i` and `reg_b_i` capture the `LANES` operands; `reg_sgn_i` captures the two signedness flags in the same cycle, so the flags always travel with the operands they qualify.
- **Core** — `mac_n_i` is combinational; the whole multiply-and-accumulate is the single reg-to-reg path the timing reports measure. In the hierarchical run this instance is the hard macro placed by [floorplan_top_example.tcl](../../scripts/floorplan_top_example.tcl).
- **Output stage** — `reg_out_i` registers the result; `out_o` is state, never a combinational path from the inputs.
- **Latency** — a result sampled after the rising edge of cycle `t` belongs to the operands driven in cycle `t − 1`, which is how [tb_top_example](../testbenches/tb_top_example.md) aligns its golden.

Source: [top_example.sv](../../rtl/top_example.sv) — Testbench: [tb_top_example.sv](../../tb/tb_top_example.sv)
