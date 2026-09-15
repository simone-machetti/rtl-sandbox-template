// -----------------------------------------------------------------------------
// Author: Simone Machetti
// SPDX-License-Identifier: Apache-2.0
//
// Description:
//   Self-checking testbench for mac_n, the combinational multi-lane
//   multiply-accumulate core. Drives random corner-biased operand sets and
//   directed extreme-value vectors, each under all four signedness
//   combinations, and checks out_o against the exact sum of the LANES products
//   computed in 64-bit arithmetic with each operand read as signed or unsigned
//   per its flag. There is no clock: every check drives the inputs, waits for
//   the logic to settle and samples the output. Reports a fatal error on any
//   mismatch. Dumps activity.vcd when compiled with VCD. The DUT instance is
//   named dut and a POST_SYN_SIM branch instantiates the synthesized/routed
//   netlist with its flattened array ports.
//
// Parameters:
//   NUM_RAND - number of random operand sets
//   LANES    - number of multiply lanes (must match the DUT)
//   WIDTH_A  - bit width of each a operand (must match the DUT)
//   WIDTH_B  - bit width of each b operand (must match the DUT)
// -----------------------------------------------------------------------------

`timescale 1 ns/1 ps

/* verilator lint_off UNUSEDSIGNAL */

module tb_mac_n #(
    parameter int NUM_RAND = 2000,
    parameter int LANES    = 4,
    parameter int WIDTH_A  = 8,
    parameter int WIDTH_B  = 8
);

    localparam int OUT_WIDTH = WIDTH_A + WIDTH_B + 1 + $clog2(LANES);

    localparam logic [WIDTH_A-1:0] A_ZERO     = '0;
    localparam logic [WIDTH_A-1:0] A_ALL_ONES = {WIDTH_A{1'b1}};
    localparam logic [WIDTH_A-1:0] A_MAX_POS  = {1'b0, {(WIDTH_A-1){1'b1}}};
    localparam logic [WIDTH_A-1:0] A_MIN_NEG  = {1'b1, {(WIDTH_A-1){1'b0}}};
    localparam logic [WIDTH_B-1:0] B_ZERO     = '0;
    localparam logic [WIDTH_B-1:0] B_ALL_ONES = {WIDTH_B{1'b1}};
    localparam logic [WIDTH_B-1:0] B_MAX_POS  = {1'b0, {(WIDTH_B-1){1'b1}}};
    localparam logic [WIDTH_B-1:0] B_MIN_NEG  = {1'b1, {(WIDTH_B-1){1'b0}}};

    logic [  WIDTH_A-1:0] a_v [0:LANES-1];
    logic [  WIDTH_B-1:0] b_v [0:LANES-1];
    logic                 is_signed_a;
    logic                 is_signed_b;
    logic [OUT_WIDTH-1:0] out;

`ifdef POST_SYN_SIM
    logic [LANES*WIDTH_A-1:0] a_flat;
    logic [LANES*WIDTH_B-1:0] b_flat;

    always_comb begin
        for (int i = 0; i < LANES; i++) begin
            a_flat[(LANES-1-i)*WIDTH_A +: WIDTH_A] = a_v[i];
            b_flat[(LANES-1-i)*WIDTH_B +: WIDTH_B] = b_v[i];
        end
    end

    mac_n dut (
        .a_i          (a_flat),
        .b_i          (b_flat),
        .is_signed_a_i(is_signed_a),
        .is_signed_b_i(is_signed_b),
        .out_o        (out)
    );
`else
    mac_n #(
        .LANES  (LANES),
        .WIDTH_A(WIDTH_A),
        .WIDTH_B(WIDTH_B)
    ) dut (
        .a_i          (a_v),
        .b_i          (b_v),
        .is_signed_a_i(is_signed_a),
        .is_signed_b_i(is_signed_b),
        .out_o        (out)
    );
`endif

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

    task automatic check(input logic sgn_a, input logic sgn_b);
        longint exp;
        longint got;
        is_signed_a = sgn_a;
        is_signed_b = sgn_b;
        #1;
        exp = golden();
        got = longint'($signed(out));
        if (got !== exp) begin
`ifdef VCD
            $dumpoff;
`endif
            $error("MISMATCH exp=%0d got=%0d (is_signed_a=%0b is_signed_b=%0b)",
                   exp, got, sgn_a, sgn_b);
            $fatal;
        end
    endtask

    task automatic check_all;
        check(1'b0, 1'b0);
        check(1'b0, 1'b1);
        check(1'b1, 1'b0);
        check(1'b1, 1'b1);
    endtask

    task automatic rand_vec;
        int pa, pb;
        for (int i = 0; i < LANES; i++) begin
            pa = $urandom % 5;
            pb = $urandom % 5;
            a_v[i] = (pa == 0) ? A_MIN_NEG : (pa == 1) ? A_MAX_POS : WIDTH_A'($urandom);
            b_v[i] = (pb == 0) ? B_MIN_NEG : (pb == 1) ? B_MAX_POS : WIDTH_B'($urandom);
        end
    endtask

    task automatic set_vec(input logic [WIDTH_A-1:0] av, input logic [WIDTH_B-1:0] bv);
        for (int i = 0; i < LANES; i++) begin
            a_v[i] = av;
            b_v[i] = bv;
        end
    endtask

    initial begin
        $display("\nStarting mac_n verification (LANES=%0d WIDTH_A=%0d WIDTH_B=%0d OUT_WIDTH=%0d)...\n",
                 LANES, WIDTH_A, WIDTH_B, OUT_WIDTH);
`ifdef VCD
        $dumpfile("activity.vcd");
        $dumpvars(0, dut);
`endif

        is_signed_a = 1'b0;
        is_signed_b = 1'b0;
        set_vec(A_ZERO, B_ZERO);
        #1;

        for (int t = 0; t < NUM_RAND; t++) begin
            rand_vec;
            check_all;
        end

        set_vec(A_ZERO, B_ZERO);
        check_all;
        set_vec(A_MAX_POS, B_MAX_POS);
        check_all;
        set_vec(A_MIN_NEG, B_MIN_NEG);
        check_all;
        set_vec(A_MAX_POS, B_MIN_NEG);
        check_all;
        set_vec(A_MIN_NEG, B_MAX_POS);
        check_all;
        set_vec(A_ALL_ONES, B_ALL_ONES);
        check_all;

`ifdef VCD
        $dumpoff;
`endif
        $display("mac_n: all %0d random + corner tests PASSED!\n", NUM_RAND);
        $finish;
    end

endmodule
