# Adder Tree N

`add_tree_n` — Parameterized N-input adder tree: sums `SIZE` words of `WIDTH` bits into one `OUT_WIDTH = WIDTH + ceil(log2(SIZE))`-bit result with a balanced binary tree of [add_n](./add_n.md) nodes, `ceil(log2(SIZE))` adders deep. The accumulation stage of [mac_n](./mac_n.md).

## Purpose

Reduce many words to one with logarithmic depth. The design decision is *where* the width grows: every leaf is extended to the final `OUT_WIDTH` once, up front, so all nodes are plain `OUT_WIDTH`-bit modular adders that can never overflow — every partial sum of the inputs is bounded by the full sum's bound. This keeps the node trivial and the wiring regular at the cost of a few extra low-order adder bits that synthesis largely optimizes away.

## Parameters

| Parameter   | Default | Description                                            |
| ----------- | ------- | ------------------------------------------------------ |
| `WIDTH`     | 8       | Bit width of each input word.                          |
| `SIZE`      | 4       | Number of input words.                                 |
| `IS_SIGNED` | 1       | Input extension: `1` = sign-extend, `0` = zero-extend. |

Derived `localparam`s: `LEVELS = $clog2(SIZE)`, `OUT_WIDTH = WIDTH + LEVELS`, `N_PAD = 2^LEVELS` (the padded leaf count).

## Interface

| Signal           | Dir | Width        | Description                       |
| ---------------- | --- | ------------ | --------------------------------- |
| `in_i[0:SIZE-1]` | in  | `WIDTH` each | Input words.                      |
| `out_o`          | out | `OUT_WIDTH`  | `Σ in_i[k]`, exact at this width. |

## Instantiation

```systemverilog
add_tree_n #(.WIDTH(17), .SIZE(4), .IS_SIGNED(1'b1)) add_tree_n_i (
    .in_i (p),                    // logic [16:0] p [0:3]
    .out_o(sum)                   // logic [18:0]
);
```

## Internal logic

The tree is stored in **heap order** in one array: leaf `k` sits at `node[N_PAD + k]`, the parent of `node[i]` is `node[i / 2]`, and `node[1]` is the root. Index 0 is unused, so the array is declared `[1 : 2·N_PAD − 1]` and every element is driven exactly once.

```systemverilog
logic [OUT_WIDTH-1:0] node [1:2*N_PAD-1];

for (i = 0; i < N_PAD; i++) begin : gen_leaf
    if (i >= SIZE) begin : gen_pad
        assign node[N_PAD+i] = '0;
    end else if (IS_SIGNED) begin : gen_sext
        assign node[N_PAD+i] = OUT_WIDTH'($signed(in_i[i]));
    end else begin : gen_zext
        assign node[N_PAD+i] = OUT_WIDTH'(in_i[i]);
    end
end

for (i = 1; i < N_PAD; i++) begin : gen_node
    add_n #(.WIDTH(OUT_WIDTH)) add_n_i (
        .in_0_i(node[2*i]), .in_1_i(node[2*i+1]), .out_o(node[i])
    );
end

assign out_o = node[1];
```

- **Leaves** — each input is widened to `OUT_WIDTH` by a size cast: `OUT_WIDTH'($signed(x))` sign-extends, `OUT_WIDTH'(x)` zero-extends. When `SIZE` is not a power of two the missing leaves are tied to zero, so the tree stays balanced.
- **Nodes** — `N_PAD − 1` instances of `add_n`, node `i` adding its two children `2i` and `2i + 1`. Level `l` (root = level 0) holds `2^l` nodes; the depth is `LEVELS`.
- **No overflow** — with `SIZE ≤ 2^LEVELS` signed inputs in `[−2^(WIDTH−1), 2^(WIDTH−1) − 1]`, any partial sum lies in `[−2^(OUT_WIDTH−1), 2^(OUT_WIDTH−1) − 1]`; the unsigned case is bounded by `2^OUT_WIDTH − 1` likewise. Modular addition at `OUT_WIDTH` is therefore exact at every node.
- **`SIZE = 1`** — `LEVELS = 0`, no node is generated, and `out_o` is the (unextended) single input.

Source: [add_tree_n.sv](../../rtl/add_tree_n.sv)
