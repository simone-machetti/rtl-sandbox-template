// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Parameterized two-input adder. Adds two WIDTH-bit words and returns the
//   WIDTH-bit sum modulo 2^WIDTH. The operands carry no signedness of their
//   own: a two's-complement sum is bit-identical to an unsigned one at the
//   same width, so the caller decides the interpretation and sizes WIDTH so
//   that the true result fits. It is the node of the add_tree_n reduction tree.
//
// Parameters:
//   WIDTH - bit width of the operands and of the sum
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module add_n #(
    parameter int WIDTH = 8
)(
    input  logic [WIDTH-1:0] in_0_i,
    input  logic [WIDTH-1:0] in_1_i,
    output logic [WIDTH-1:0] out_o
);

    assign out_o = in_0_i + in_1_i;

endmodule
