// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Parameterized register bank. Holds SIZE independent registers, each WIDTH
//   bits wide, with an active-low asynchronous reset. On every rising edge of
//   clk_i each register captures its corresponding WIDTH-bit input word; while
//   rst_ni is low all registers are cleared to zero. Used wherever a bank of
//   like-width registers is needed - pipeline stages, accumulators, and so on.
//
// Parameters:
//   WIDTH - bit width of each register
//   SIZE  - number of registers in the bank
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module reg_n #(
    parameter int WIDTH = 8,
    parameter int SIZE  = 4
)(
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [WIDTH-1:0] d_i [0:SIZE-1],
    output logic [WIDTH-1:0] q_o [0:SIZE-1]
);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < SIZE; i++) begin
                q_o[i] <= '0;
            end
        end else begin
            for (int i = 0; i < SIZE; i++) begin
                q_o[i] <= d_i[i];
            end
        end
    end

endmodule
