// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Self-checking, full-throughput testbench for top_example, the registered
//   multiply-accumulate flow-validation vehicle. Streams a fresh corner-biased
//   random operand set (with random per-operand signedness) into the input
//   registers on every clock and checks the registered result against a
//   one-iteration delayed golden (the 2-cycle latency of top_example means the
//   result sampled after the posedge of iteration t belongs to the operands
//   driven in iteration t-1). The golden is the exact sum of the LANES
//   products, computed in 64-bit arithmetic with each operand read as signed
//   or unsigned per its flag. Ends with directed extreme-value sweeps, each
//   under all four signedness combinations. Reports a fatal error on any
//   mismatch. Dumps activity.vcd when compiled with VCD. The DUT instance is
//   named dut and a POST_SYN_SIM branch instantiates the synthesized/routed
//   netlist with its flattened array ports.
//
// Parameters:
//   NUM_RAND - number of random streamed vectors
//   LANES    - number of multiply lanes (must match the DUT)
//   WIDTH_A  - bit width of each a operand (must match the DUT)
//   WIDTH_B  - bit width of each b operand (must match the DUT)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

`ifndef CLK_PERIOD_NS
`define CLK_PERIOD_NS 10
`endif

/* verilator lint_off UNUSEDSIGNAL */

module tb_top_example #(
    parameter int NUM_RAND = 2000,
    parameter int LANES    = 4,
    parameter int WIDTH_A  = 8,
    parameter int WIDTH_B  = 8
);

    localparam real CLK_PERIOD = `CLK_PERIOD_NS;
    localparam real CLK_HALF   = CLK_PERIOD / 2.0;
    localparam real T_SETTLE   = CLK_PERIOD / 10.0;

    localparam int OUT_WIDTH = WIDTH_A + WIDTH_B + 1 + $clog2(LANES);

    localparam logic [WIDTH_A-1:0] A_ZERO     = '0;
    localparam logic [WIDTH_A-1:0] A_ALL_ONES = {WIDTH_A{1'b1}};
    localparam logic [WIDTH_A-1:0] A_MAX_POS  = {1'b0, {(WIDTH_A-1){1'b1}}};
    localparam logic [WIDTH_A-1:0] A_MIN_NEG  = {1'b1, {(WIDTH_A-1){1'b0}}};
    localparam logic [WIDTH_B-1:0] B_ZERO     = '0;
    localparam logic [WIDTH_B-1:0] B_ALL_ONES = {WIDTH_B{1'b1}};
    localparam logic [WIDTH_B-1:0] B_MAX_POS  = {1'b0, {(WIDTH_B-1){1'b1}}};
    localparam logic [WIDTH_B-1:0] B_MIN_NEG  = {1'b1, {(WIDTH_B-1){1'b0}}};

    logic                 clk_i;
    logic                 rst_ni;
    logic [  WIDTH_A-1:0] a_v [0:LANES-1];
    logic [  WIDTH_B-1:0] b_v [0:LANES-1];
    logic                 is_signed_a;
    logic                 is_signed_b;
    logic [OUT_WIDTH-1:0] out;

    longint exp_prev;
    int     have_prev;

`ifdef POST_SYN_SIM
    logic [LANES*WIDTH_A-1:0] a_flat;
    logic [LANES*WIDTH_B-1:0] b_flat;

    always_comb begin
        for (int i = 0; i < LANES; i++) begin
            a_flat[(LANES-1-i)*WIDTH_A +: WIDTH_A] = a_v[i];
            b_flat[(LANES-1-i)*WIDTH_B +: WIDTH_B] = b_v[i];
        end
    end

    top_example dut (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .a_i          (a_flat),
        .b_i          (b_flat),
        .is_signed_a_i(is_signed_a),
        .is_signed_b_i(is_signed_b),
        .out_o        (out)
    );
`else
    top_example #(
        .LANES  (LANES),
        .WIDTH_A(WIDTH_A),
        .WIDTH_B(WIDTH_B)
    ) dut (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .a_i          (a_v),
        .b_i          (b_v),
        .is_signed_a_i(is_signed_a),
        .is_signed_b_i(is_signed_b),
        .out_o        (out)
    );
`endif

    initial clk_i = 1'b0;
    always #(CLK_HALF) clk_i = ~clk_i;

    function automatic longint golden();
        longint e;
        longint a_val;
        longint b_val;
        e = 0;
        for (int i = 0; i < LANES; i++) begin
            a_val = is_signed_a ? longint'($signed(a_v[i])) : longint'($unsigned(a_v[i]));
            b_val = is_signed_b ? longint'($signed(b_v[i])) : longint'($unsigned(b_v[i]));
            e    += a_val * b_val;
        end
        return e;
    endfunction

    task automatic check_out(input longint exp);
        longint got;
        got = longint'($signed(out));
        if (got !== exp) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("MISMATCH exp=%0d got=%0d (is_signed_a=%0b is_signed_b=%0b)",
                   exp, got, is_signed_a, is_signed_b);
            $fatal;
        end
    endtask

    task automatic step_check;
        longint exp_now;
        exp_now = golden();
        @(posedge clk_i);
        #(T_SETTLE);
        if (have_prev) begin
            check_out(exp_prev);
        end
        have_prev = 1;
        exp_prev  = exp_now;
    endtask

    task automatic rand_vec;
        int pa, pb;
        for (int i = 0; i < LANES; i++) begin
            pa = $urandom % 5;
            pb = $urandom % 5;
            a_v[i] = (pa == 0) ? A_MIN_NEG : (pa == 1) ? A_MAX_POS : WIDTH_A'($urandom);
            b_v[i] = (pb == 0) ? B_MIN_NEG : (pb == 1) ? B_MAX_POS : WIDTH_B'($urandom);
        end
        is_signed_a = 1'($urandom % 2);
        is_signed_b = 1'($urandom % 2);
    endtask

    task automatic set_vec(input logic [WIDTH_A-1:0] av, input logic [WIDTH_B-1:0] bv);
        for (int i = 0; i < LANES; i++) begin
            a_v[i] = av;
            b_v[i] = bv;
        end
    endtask

    task automatic sweep_signs;
        is_signed_a = 1'b0; is_signed_b = 1'b0; step_check;
        is_signed_a = 1'b0; is_signed_b = 1'b1; step_check;
        is_signed_a = 1'b1; is_signed_b = 1'b0; step_check;
        is_signed_a = 1'b1; is_signed_b = 1'b1; step_check;
    endtask

    initial begin
        $display("\nStarting top_example verification (LANES=%0d WIDTH_A=%0d WIDTH_B=%0d OUT_WIDTH=%0d)...\n",
                 LANES, WIDTH_A, WIDTH_B, OUT_WIDTH);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, dut);
`endif

        rst_ni      = 1'b0;
        is_signed_a = 1'b0;
        is_signed_b = 1'b0;
        have_prev   = 0;
        set_vec(A_ZERO, B_ZERO);
        repeat (3) @(posedge clk_i);
        #(T_SETTLE);
        rst_ni = 1'b1;

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_vec;
            step_check;
        end

        set_vec(A_ZERO, B_ZERO);
        sweep_signs;
        set_vec(A_MAX_POS, B_MAX_POS);
        sweep_signs;
        set_vec(A_MIN_NEG, B_MIN_NEG);
        sweep_signs;
        set_vec(A_MAX_POS, B_MIN_NEG);
        sweep_signs;
        set_vec(A_MIN_NEG, B_MAX_POS);
        sweep_signs;
        set_vec(A_ALL_ONES, B_ALL_ONES);
        sweep_signs;

        set_vec(A_ZERO, B_ZERO);
        is_signed_a = 1'b0;
        is_signed_b = 1'b0;
        step_check;

`ifdef VCD
        $dumpoff;
`endif
        $display("top_example: all %0d random + corner tests PASSED!\n", NUM_RAND);
        $finish;
    end

endmodule
