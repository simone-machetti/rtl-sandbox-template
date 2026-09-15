// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Example top-level used as a fast vehicle to exercise the complete EDA flow
//   (simulation, synthesis, place-and-route and every post-synthesis /
//   post-place-and-route analysis). Wraps a single mac_n multiply-accumulate
//   core with reg_n input registers (operands and signedness flags) and a
//   reg_n output register (result), so the design is one clean reg-to-reg
//   pipeline stage through a real multiplier and adder-tree datapath. Latency
//   is 2 cycles: inputs are captured on the first rising edge, the registered
//   result appears after the second. The shape is parameterized so the same
//   top-level also demonstrates the flow's PARAMS elaboration overrides.
//
// Parameters:
//   LANES   - number of multiply lanes accumulated into the result
//   WIDTH_A - bit width of each a operand
//   WIDTH_B - bit width of each b operand
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module top_example #(
    parameter int LANES   = 4,
    parameter int WIDTH_A = 8,
    parameter int WIDTH_B = 8,

    localparam int OUT_WIDTH = WIDTH_A + WIDTH_B + 1 + $clog2(LANES)
)(
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic [  WIDTH_A-1:0] a_i [0:LANES-1],
    input  logic [  WIDTH_B-1:0] b_i [0:LANES-1],
    input  logic                 is_signed_a_i,
    input  logic                 is_signed_b_i,
    output logic [OUT_WIDTH-1:0] out_o
);

    logic [  WIDTH_A-1:0] a_q   [0:LANES-1];
    logic [  WIDTH_B-1:0] b_q   [0:LANES-1];
    logic                 sgn_d [      0:1];
    logic                 sgn_q [      0:1];
    logic [OUT_WIDTH-1:0] out_d [      0:0];
    logic [OUT_WIDTH-1:0] out_q [      0:0];

    reg_n #(.WIDTH(WIDTH_A), .SIZE(LANES)) reg_a_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(a_i), .q_o(a_q)
    );

    reg_n #(.WIDTH(WIDTH_B), .SIZE(LANES)) reg_b_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(b_i), .q_o(b_q)
    );

    assign sgn_d[0] = is_signed_a_i;
    assign sgn_d[1] = is_signed_b_i;

    reg_n #(.WIDTH(1), .SIZE(2)) reg_sgn_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(sgn_d), .q_o(sgn_q)
    );

    mac_n #(
        .LANES  (LANES),
        .WIDTH_A(WIDTH_A),
        .WIDTH_B(WIDTH_B)
    ) mac_n_i (
        .a_i          (a_q),
        .b_i          (b_q),
        .is_signed_a_i(sgn_q[0]),
        .is_signed_b_i(sgn_q[1]),
        .out_o        (out_d[0])
    );

    reg_n #(.WIDTH(OUT_WIDTH), .SIZE(1)) reg_out_i (
        .clk_i(clk_i), .rst_ni(rst_ni), .d_i(out_d), .q_o(out_q)
    );

    assign out_o = out_q[0];

endmodule
