# Multiplier N

`mul_n` — Parameterized `WIDTH_A × WIDTH_B` multiplier with runtime signedness per operand, returning the exact product as a `WIDTH_A + WIDTH_B + 1`-bit two's-complement word. The per-lane multiplier inside [mac_n](./mac_n.md).

## Purpose

Multiply two operands whose interpretation (signed or unsigned) is a runtime signal rather than a parameter, so one instance serves all four combinations. The trick is to widen each operand by one bit before a single **signed** multiplication: the extra bit is a copy of the MSB when the operand is signed (sign extension, value unchanged) and zero when it is unsigned (the word is now a non-negative two's-complement number). The product of the two widened words is then correct in every case.

## Parameters

| Parameter | Default | Description               |
| --------- | ------- | ------------------------- |
| `WIDTH_A` | 8       | Bit width of operand `a`. |
| `WIDTH_B` | 8       | Bit width of operand `b`. |

Derived `localparam`: `P_WIDTH = WIDTH_A + WIDTH_B + 1` (17 by default).

## Interface

| Signal          | Dir | Width     | Description                                             |
| --------------- | --- | --------- | ------------------------------------------------------- |
| `a_i`           | in  | `WIDTH_A` | Operand `a`.                                            |
| `b_i`           | in  | `WIDTH_B` | Operand `b`.                                            |
| `is_signed_a_i` | in  | 1         | `a` signedness: `1` = two's complement, `0` = unsigned. |
| `is_signed_b_i` | in  | 1         | `b` signedness: `1` = two's complement, `0` = unsigned. |
| `p_o`           | out | `P_WIDTH` | `a · b`, two's complement, exact.                       |

## Instantiation

```systemverilog
mul_n #(.WIDTH_A(8), .WIDTH_B(8)) mul_n_i (
    .a_i          (a),            // logic [7:0]
    .b_i          (b),            // logic [7:0]
    .is_signed_a_i(is_signed_a),
    .is_signed_b_i(is_signed_b),
    .p_o          (p)             // logic [16:0]
);
```

## Internal logic

```systemverilog
logic signed [WIDTH_A:0] a_ext;
logic signed [WIDTH_B:0] b_ext;
logic signed [P_WIDTH:0] p_full;

assign a_ext  = {is_signed_a_i & a_i[WIDTH_A-1], a_i};
assign b_ext  = {is_signed_b_i & b_i[WIDTH_B-1], b_i};
assign p_full = a_ext * b_ext;
assign p_o    = p_full[P_WIDTH-1:0];
```

- **Widening** — `a_ext` is `WIDTH_A + 1` bits: its top bit is `a_i`'s MSB when `is_signed_a_i` is set (so `$signed(a_ext) == $signed(a_i)`) and `0` otherwise (so `$signed(a_ext) == $unsigned(a_i)`). Same for `b_ext`.
- **One signed multiply** — both extended words are declared `signed`, so `*` is a signed multiplication and the result is the mathematically exact product for all four flag combinations. Synthesis sees a plain `(WIDTH_A + 1) × (WIDTH_B + 1)` signed multiplier.
- **Output width** — the full product has `WIDTH_A + WIDTH_B + 2` bits, but its top bit is always a copy of the one below it: the largest magnitude, `(2^WIDTH_A − 1)(2^WIDTH_B − 1)` for unsigned × unsigned, is below `2^(WIDTH_A + WIDTH_B)`, and the most negative product, `−2^(WIDTH_A − 1) · (2^WIDTH_B − 1)`, is above `−2^(WIDTH_A + WIDTH_B − 1)`. Dropping that redundant bit gives the `P_WIDTH`-bit `p_o` with no loss.

Source: [mul_n.sv](../../rtl/mul_n.sv)
