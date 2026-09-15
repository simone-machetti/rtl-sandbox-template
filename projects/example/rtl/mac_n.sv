// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Parameterized multi-lane multiply-accumulate. Multiplies LANES operand
//   pairs in parallel (one mul_n per lane, WIDTH_A x WIDTH_B bits) and
//   accumulates the LANES products into a single result with an add_tree_n,
//   so out_o = sum over the lanes of a_i[k] * b_i[k]. Both operands share a
//   runtime signedness flag across the lanes, and the result is exact: each
//   product is WIDTH_A + WIDTH_B + 1 bits, the tree adds ceil(log2(LANES))
//   bits of growth on top. Fully combinational; it is the datapath core that
//   top_example wraps between its input and output registers.
//
// Parameters:
//   LANES   - number of multiply lanes accumulated into the result
//   WIDTH_A - bit width of each a operand
//   WIDTH_B - bit width of each b operand
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module mac_n #(
    parameter int LANES   = 4,
    parameter int WIDTH_A = 8,
    parameter int WIDTH_B = 8,

    localparam int P_WIDTH   = WIDTH_A + WIDTH_B + 1,
    localparam int OUT_WIDTH = P_WIDTH + $clog2(LANES)
)(
    input  logic [  WIDTH_A-1:0] a_i [0:LANES-1],
    input  logic [  WIDTH_B-1:0] b_i [0:LANES-1],
    input  logic                 is_signed_a_i,
    input  logic                 is_signed_b_i,
    output logic [OUT_WIDTH-1:0] out_o
);

    logic [P_WIDTH-1:0] p [0:LANES-1];

    genvar i;

    generate
        for (i = 0; i < LANES; i++) begin : gen_lane
            mul_n #(
                .WIDTH_A(WIDTH_A),
                .WIDTH_B(WIDTH_B)
            ) mul_n_i (
                .a_i          (a_i[i]),
                .b_i          (b_i[i]),
                .is_signed_a_i(is_signed_a_i),
                .is_signed_b_i(is_signed_b_i),
                .p_o          (p[i])
            );
        end
    endgenerate

    add_tree_n #(
        .WIDTH    (P_WIDTH),
        .SIZE     (LANES),
        .IS_SIGNED(1'b1)
    ) add_tree_n_i (
        .in_i (p),
        .out_o(out_o)
    );

endmodule
