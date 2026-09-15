// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Parameterized N-input adder tree. Sums SIZE input words, each WIDTH bits
//   wide, into one OUT_WIDTH = WIDTH + ceil(log2(SIZE)) bit result with a
//   balanced binary tree of add_n nodes, so the depth is ceil(log2(SIZE))
//   adders. Every input is first extended to OUT_WIDTH (sign-extended when
//   IS_SIGNED, otherwise zero-extended); at that width no partial sum can
//   overflow, so the nodes are plain modular adders. The tree is stored in
//   heap order: leaf k sits at node[N_PAD + k], the parent of node[i] is
//   node[i / 2], and node[1] is the root. When SIZE is not a power of two the
//   missing leaves are tied to zero.
//
// Parameters:
//   WIDTH     - bit width of each input word
//   SIZE      - number of input words
//   IS_SIGNED - input extension: 1 = sign-extend, 0 = zero-extend
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module add_tree_n #(
    parameter int WIDTH     = 8,
    parameter int SIZE      = 4,
    parameter bit IS_SIGNED = 1'b1,

    localparam int LEVELS    = $clog2(SIZE),
    localparam int OUT_WIDTH = WIDTH + LEVELS
)(
    input  logic [    WIDTH-1:0] in_i [0:SIZE-1],
    output logic [OUT_WIDTH-1:0] out_o
);

    localparam int N_PAD = 1 << LEVELS;

    logic [OUT_WIDTH-1:0] node [1:2*N_PAD-1];

    genvar i;

    generate
        for (i = 0; i < N_PAD; i++) begin : gen_leaf
            if (i >= SIZE) begin : gen_pad
                assign node[N_PAD+i] = '0;
            end else if (IS_SIGNED) begin : gen_sext
                assign node[N_PAD+i] = OUT_WIDTH'($signed(in_i[i]));
            end else begin : gen_zext
                assign node[N_PAD+i] = OUT_WIDTH'(in_i[i]);
            end
        end
    endgenerate

    generate
        for (i = 1; i < N_PAD; i++) begin : gen_node
            add_n #(
                .WIDTH(OUT_WIDTH)
            ) add_n_i (
                .in_0_i(node[2*i]),
                .in_1_i(node[2*i+1]),
                .out_o (node[i])
            );
        end
    endgenerate

    assign out_o = node[1];

endmodule
