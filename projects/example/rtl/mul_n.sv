// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Parameterized multiplier with runtime signedness. Multiplies a WIDTH_A-bit
//   operand by a WIDTH_B-bit operand and returns the exact product as a
//   (WIDTH_A + WIDTH_B + 1)-bit two's-complement word. Each operand is read as
//   signed or unsigned according to its own flag: it is widened by one bit (a
//   copy of its MSB when signed, zero when unsigned) so that a single signed
//   multiplication covers all four signedness combinations. The extra output
//   bit is what an unsigned x unsigned product needs to stay non-negative in
//   two's complement.
//
// Parameters:
//   WIDTH_A - bit width of operand a
//   WIDTH_B - bit width of operand b
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module mul_n #(
    parameter int WIDTH_A = 8,
    parameter int WIDTH_B = 8,

    localparam int P_WIDTH = WIDTH_A + WIDTH_B + 1
)(
    input  logic [WIDTH_A-1:0] a_i,
    input  logic [WIDTH_B-1:0] b_i,
    input  logic               is_signed_a_i,
    input  logic               is_signed_b_i,
    output logic [P_WIDTH-1:0] p_o
);

    logic signed [WIDTH_A:0] a_ext;
    logic signed [WIDTH_B:0] b_ext;
    logic signed [P_WIDTH:0] p_full;

    assign a_ext  = {is_signed_a_i & a_i[WIDTH_A-1], a_i};
    assign b_ext  = {is_signed_b_i & b_i[WIDTH_B-1], b_i};
    assign p_full = a_ext * b_ext;
    assign p_o    = p_full[P_WIDTH-1:0];

endmodule
