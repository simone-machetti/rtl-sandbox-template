// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Behavioural replacements for the ASAP7 sequential cells, used instead of the
//   PDK models during post-synthesis simulation.
//
//   The PDK models build their flip-flops from 1995 UDP tables (altos_dff,
//   altos_latch). Verilator does not implement UDP tables, and the failure is
//   silent rather than an error: a single flop behaves correctly, but two flops
//   in series race - the second samples the first's NEW value within the same
//   clock edge, and only for part of the word, so a pipeline collapses by one
//   stage and the data corrupts. OpenROAD-flow-scripts hits the same wall and
//   ships its own dff.v for the same reason (verilator issue 5243), but only
//   covers the DFFHQN cells; the flow here maps to DFFASRHQNx1, so every
//   sequential cell dfflibmap and the latch map can emit is modelled below.
//
//   These are function-only models: no timing checks and no specify blocks,
//   which post-synthesis simulation does not use anyway.
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

module DFFHQNx1_ASAP7_75t_R (QN, D, CLK);
    output reg QN;
    input  D, CLK;
    always @(posedge CLK) QN <= ~D;
endmodule

module DFFHQNx2_ASAP7_75t_R (QN, D, CLK);
    output reg QN;
    input  D, CLK;
    always @(posedge CLK) QN <= ~D;
endmodule

module DFFLQNx1_ASAP7_75t_R (QN, D, CLK);
    output reg QN;
    input  D, CLK;
    always @(negedge CLK) QN <= ~D;
endmodule

module DFFASRHQNx1_ASAP7_75t_R (QN, D, RESETN, SETN, CLK);
    output reg QN;
    input  D, RESETN, SETN, CLK;
    always @(posedge CLK or negedge RESETN or negedge SETN) begin
        if (!RESETN)     QN <= 1'b1;
        else if (!SETN)  QN <= 1'b0;
        else             QN <= ~D;
    end
endmodule

module DHLx1_ASAP7_75t_R (Q, D, CLK);
    output reg Q;
    input  D, CLK;
    always @* if (CLK) Q = D;
endmodule

module DLLx1_ASAP7_75t_R (Q, D, CLK);
    output reg Q;
    input  D, CLK;
    always @* if (!CLK) Q = D;
endmodule

module ICGx1_ASAP7_75t_R (GCLK, ENA, SE, CLK);
    output GCLK;
    input  ENA, SE, CLK;
    reg    en_latched;
    always @* if (!CLK) en_latched = ENA | SE;
    assign GCLK = CLK & en_latched;
endmodule
