# Multiply-Accumulate N

`mac_n` — Parameterized multi-lane multiply-accumulate: `LANES` parallel [mul_n](./mul_n.md) products accumulated by one [add_tree_n](./add_tree_n.md) into a single exact result, `out_o = Σ_{k} a_i[k] · b_i[k]`. Both operands share a runtime signedness flag across the lanes. Fully combinational; it is the datapath core that [top_example](../architectures/top_example.md) wraps between its registers and the block hardened as a macro in the hierarchical place-and-route.

## Purpose

The smallest arithmetic block with real hierarchy below it (`mac_n → mul_n`, `mac_n → add_tree_n → add_n`), so a synthesis run with `KEEP_HIERARCHY=1` or `KEEP_MODULES="mac_n"` shows module boundaries, `BLACKBOX_MODULES="mac_n"` links a separately synthesized netlist, and `make pnr` can harden it on its own. The result is exact by construction — no truncation, no saturation — so the testbenches compare against a 64-bit golden on the nose.

## Parameters

| Parameter | Default | Description                                           |
| --------- | ------- | ----------------------------------------------------- |
| `LANES`   | 4       | Number of multiply lanes accumulated into the result. |
| `WIDTH_A` | 8       | Bit width of each `a` operand.                        |
| `WIDTH_B` | 8       | Bit width of each `b` operand.                        |

Derived `localparam`s: `P_WIDTH = WIDTH_A + WIDTH_B + 1` (17 by default, the exact product width), `OUT_WIDTH = P_WIDTH + $clog2(LANES)` (19 by default).

## Interface

| Signal           | Dir | Width          | Description                                             |
| ---------------- | --- | -------------- | ------------------------------------------------------- |
| `a_i[0:LANES-1]` | in  | `WIDTH_A` each | Operand `a` of each lane.                               |
| `b_i[0:LANES-1]` | in  | `WIDTH_B` each | Operand `b` of each lane.                               |
| `is_signed_a_i`  | in  | 1              | `a` signedness: `1` = two's complement, `0` = unsigned. |
| `is_signed_b_i`  | in  | 1              | `b` signedness: `1` = two's complement, `0` = unsigned. |
| `out_o`          | out | `OUT_WIDTH`    | `Σ a_i[k] · b_i[k]`, two's complement, exact.           |

## Instantiation

```systemverilog
mac_n #(.LANES(4), .WIDTH_A(8), .WIDTH_B(8)) mac_n_i (
    .a_i          (a),            // logic [7:0] a [0:3]
    .b_i          (b),            // logic [7:0] b [0:3]
    .is_signed_a_i(is_signed_a),
    .is_signed_b_i(is_signed_b),
    .out_o        (out)           // logic [18:0]
);
```

## Internal logic

One multiplier per lane, all sharing the two signedness flags, then one adder tree:

```systemverilog
for (i = 0; i < LANES; i++) begin : gen_lane
    mul_n #(.WIDTH_A(WIDTH_A), .WIDTH_B(WIDTH_B)) mul_n_i (
        .a_i(a_i[i]), .b_i(b_i[i]),
        .is_signed_a_i(is_signed_a_i), .is_signed_b_i(is_signed_b_i),
        .p_o(p[i])
    );
end

add_tree_n #(.WIDTH(P_WIDTH), .SIZE(LANES), .IS_SIGNED(1'b1)) add_tree_n_i (
    .in_i (p),
    .out_o(out_o)
);
```

- **Products** — each `p[i]` is a `P_WIDTH`-bit two's-complement word that is exact for every signedness combination (see [mul_n](./mul_n.md) for why one extra bit suffices).
- **Accumulation** — the tree always sign-extends (`IS_SIGNED = 1`): even when both operands are unsigned the products are non-negative two's-complement words, so a signed sum is correct in every case. `$clog2(LANES)` bits of growth hold the sum of `LANES` products exactly.
- **Range at the default shape** — from `4 · (−128 · 255) = −130560` (signed × unsigned) to `4 · 255 · 255 = 260100` (unsigned × unsigned), inside the 19-bit signed range `[−262144, 262143]`.

Source: [mac_n.sv](../../rtl/mac_n.sv) — Testbench: [tb_mac_n.sv](../../tb/tb_mac_n.sv)
