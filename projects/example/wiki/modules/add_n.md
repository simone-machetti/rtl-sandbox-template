# Adder N

`add_n` — Parameterized two-input adder: `out_o = in_0_i + in_1_i` modulo `2^WIDTH`. The node of [add_tree_n](./add_tree_n.md).

## Purpose

The one-line primitive that keeps the tree readable and gives synthesis a module boundary per node when `KEEP_HIERARCHY=1`. It carries no signedness: a two's-complement sum is bit-identical to an unsigned one at the same width, so the caller chooses the interpretation and sizes `WIDTH` so that the true result fits — which is exactly what `add_tree_n` does by extending its leaves before the first node.

## Parameters

| Parameter | Default | Description                               |
| --------- | ------- | ----------------------------------------- |
| `WIDTH`   | 8       | Bit width of the operands and of the sum. |

## Interface

| Signal   | Dir | Width   | Description                         |
| -------- | --- | ------- | ----------------------------------- |
| `in_0_i` | in  | `WIDTH` | First operand.                      |
| `in_1_i` | in  | `WIDTH` | Second operand.                     |
| `out_o`  | out | `WIDTH` | `in_0_i + in_1_i` modulo `2^WIDTH`. |

## Instantiation

```systemverilog
add_n #(.WIDTH(19)) add_n_i (
    .in_0_i(x),                   // logic [18:0]
    .in_1_i(y),                   // logic [18:0]
    .out_o (s)                    // logic [18:0]
);
```

## Internal logic

```systemverilog
assign out_o = in_0_i + in_1_i;
```

A single continuous assignment; the carry out of the top bit is dropped, which is harmless whenever the caller has provided the growth bit above the operands' range.

Source: [add_n.sv](../../rtl/add_n.sv)
