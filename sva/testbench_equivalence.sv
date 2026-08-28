`timescale 1ns/1ps

// Differential testbench for Part C.
//
// Paste BOTH RTL sources into EDA Playground's Design pane, in this order:
//   1. systemverilog/dot_product.sv
//   2. anvil/generated/dot_product_anvil.sv
// Paste this file into the Testbench pane and use Verilator with --assert.
//
// The two implementations have different microarchitectures (four-lane versus
// sequential), so their cycle-by-cycle ready/ack and accumulator timing is not
// expected to match.  This testbench sends the same ordered transactions to
// both DUTs, checks the six property intents on both, and compares results at
// transaction boundaries.
module dot_product_equivalence_tb;
    localparam int MAX_WAIT = 200;

    logic clk, rst_n;

    // Common transaction source, fanned out through the two protocol adapters.
    logic [7:0] src_length, src_a, src_b;
    logic [3:0] src_tag;
    int sv_command_handshakes, an_command_handshakes;
    int sv_element_handshakes, an_element_handshakes;

    // Handwritten SystemVerilog DUT ports.
    logic sv_cmd_valid, sv_cmd_ready, sv_in_valid, sv_in_ready;
    logic sv_out_valid, sv_out_ready;
    logic [19:0] sv_result;
    logic [3:0] sv_out_tag;

    // Anvil-generated DUT ports.
    logic an_cmd_valid, an_cmd_ack;
    logic [11:0] an_cmd_data;
    logic an_cmd_res_ack, an_cmd_res_valid, an_cmd_res_data;
    logic an_elem_valid, an_elem_ack;
    logic [15:0] an_elem_data;
    logic an_elem_res_ack, an_elem_res_valid, an_elem_res_data;
    logic an_out_ack, an_out_valid;
    logic [23:0] an_out_data;
    logic an_out_res_valid, an_out_res_ack, an_out_res_data;

    dot_product #(.DATA_W(8), .LANES(4)) sv_dut (
        .clk, .rst_n,
        .cmd_valid(sv_cmd_valid), .cmd_ready(sv_cmd_ready),
        .cmd_length(src_length), .cmd_tag(src_tag),
        .in_valid(sv_in_valid), .in_ready(sv_in_ready),
        .a_data(src_a), .b_data(src_b),
        .out_valid(sv_out_valid), .out_ready(sv_out_ready),
        .result(sv_result), .out_tag(sv_out_tag)
    );

    DotProduct anvil_dut (
        .clk_i(clk), .rst_ni(rst_n),
        ._cmd_cmd_req_ack(an_cmd_ack), ._cmd_cmd_req_valid(an_cmd_valid),
        ._cmd_cmd_req_0(an_cmd_data),
        ._cmd_cmd_res_ack(an_cmd_res_ack), ._cmd_cmd_res_valid(an_cmd_res_valid),
        ._cmd_cmd_res_0(an_cmd_res_data),
        ._elem_in_req_ack(an_elem_ack), ._elem_in_req_valid(an_elem_valid),
        ._elem_in_req_0(an_elem_data),
        ._elem_in_res_ack(an_elem_res_ack), ._elem_in_res_valid(an_elem_res_valid),
        ._elem_in_res_0(an_elem_res_data),
        ._res_out_req_ack(an_out_ack), ._res_out_req_valid(an_out_valid),
        ._res_out_req_0(an_out_data),
        ._res_out_res_ack(an_out_res_ack), ._res_out_res_valid(an_out_res_valid),
        ._res_out_res_0(an_out_res_data)
    );

    always #5 clk = ~clk;

    // =============================================================
    // Part B property suite: P1--P6 on handwritten SystemVerilog.
    // =============================================================
    wire sv_cmd_accepted = sv_cmd_valid && sv_cmd_ready;

    property sv_p1_output_stable;
        @(posedge clk) disable iff (!rst_n)
        (sv_out_valid && !sv_out_ready) |=> ($stable(sv_result) && $stable(sv_out_tag));
    endproperty
    assert property (sv_p1_output_stable) else $error("SV FAIL P1: output changed under backpressure");

    property sv_p2_inactive_lane;
        @(posedge clk) disable iff (!rst_n)
        (sv_dut.state_q == sv_dut.REDUCE && sv_dut.reduce_step_q < 4 &&
         !sv_dut.lane_valid_q[sv_dut.reduce_step_q[1:0]]) |=> $stable(sv_dut.accum_q);
    endproperty
    assert property (sv_p2_inactive_lane) else $error("SV FAIL P2: inactive lane changed accumulator");

    property sv_p3_accumulator_reset;
        @(posedge clk) disable iff (!rst_n) sv_cmd_accepted |=> (sv_dut.accum_q == '0);
    endproperty
    assert property (sv_p3_accumulator_reset) else $error("SV FAIL P3: accumulator not reset");

    property sv_p4_output_state;
        @(posedge clk) disable iff (!rst_n) sv_out_valid |-> (sv_dut.state_q == sv_dut.OUTPUT);
    endproperty
    assert property (sv_p4_output_state) else $error("SV FAIL P4: output valid outside OUTPUT");

    property sv_p5_no_command_overlap;
        @(posedge clk) disable iff (!rst_n) sv_out_valid |-> !sv_cmd_ready;
    endproperty
    assert property (sv_p5_no_command_overlap) else $error("SV FAIL P5: command ready with pending result");

    property sv_p6_input_state;
        @(posedge clk) disable iff (!rst_n) sv_in_ready |-> (sv_dut.state_q == sv_dut.LOAD);
    endproperty
    assert property (sv_p6_input_state) else $error("SV FAIL P6: input ready outside LOAD");

    // =============================================================
    // Same six property intents on the sequential Anvil implementation.
    // P2 is the valid sequential equivalent: no element can be accepted after
    // its requested count is exhausted.  A lane-valid assertion is impossible
    // literally because the Anvil design has no inactive lanes.
    // =============================================================
    logic an_cmd_d1, an_cmd_d2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin an_cmd_d1 <= 1'b0; an_cmd_d2 <= 1'b0; end
        else begin an_cmd_d1 <= an_cmd_valid && an_cmd_ack; an_cmd_d2 <= an_cmd_d1; end
    end

    property an_p1_output_stable;
        @(posedge clk) disable iff (!rst_n)
        (an_out_valid && !an_out_ack) |=> (an_out_valid && $stable(an_out_data));
    endproperty
    assert property (an_p1_output_stable) else $error("ANVIL FAIL P1: output changed under backpressure");

    property an_p2_count_guard;
        @(posedge clk) disable iff (!rst_n)
        (an_elem_valid && an_elem_ack) |-> (anvil_dut.remaining_q != 8'd0);
    endproperty
    assert property (an_p2_count_guard) else $error("ANVIL FAIL P2: extra element accepted");

    property an_p3_accumulator_reset;
        @(posedge clk) disable iff (!rst_n) an_cmd_d2 |-> (anvil_dut.accum_q == '0);
    endproperty
    assert property (an_p3_accumulator_reset) else $error("ANVIL FAIL P3: accumulator not reset");

    property an_p4_output_state;
        @(posedge clk) disable iff (!rst_n) an_out_valid |-> (anvil_dut.state_q == 2'd2);
    endproperty
    assert property (an_p4_output_state) else $error("ANVIL FAIL P4: output valid outside OUTPUT");

    property an_p5_no_command_overlap;
        @(posedge clk) disable iff (!rst_n) an_out_valid |-> !an_cmd_ack;
    endproperty
    assert property (an_p5_no_command_overlap) else $error("ANVIL FAIL P5: command ack with pending result");

    property an_p6_input_state;
        @(posedge clk) disable iff (!rst_n)
        an_elem_ack |-> ((anvil_dut.state_q == 2'd1) && (anvil_dut.remaining_q != 8'd0));
    endproperty
    assert property (an_p6_input_state) else $error("ANVIL FAIL P6: element ack outside calculation");

    task automatic wait_high(ref logic signal, input string name);
        int cycles;
        begin
            cycles = 0;
            while (!signal) begin
                @(posedge clk);
                cycles++;
                if (cycles > MAX_WAIT) $fatal(1, "Timeout waiting for %s", name);
            end
        end
    endtask

    // These four tasks are the protocol adapters from one source transaction
    // into each DUT's native interface.
    task automatic send_command_to_sv(input logic [7:0] length, input logic [3:0] tag);
        begin
            @(negedge clk);
            src_length = length; src_tag = tag; sv_cmd_valid = 1'b1;
            wait_high(sv_cmd_ready, "SV cmd_ready");
            @(posedge clk);
            @(negedge clk);
            sv_cmd_valid = 1'b0;
            sv_command_handshakes++;
        end
    endtask

    task automatic send_command_to_anvil(input logic [7:0] length, input logic [3:0] tag);
        begin
            @(negedge clk);
            if ((src_length !== length) || (src_tag !== tag))
                $fatal(1, "Stimulus mismatch before Anvil command");
            an_cmd_data = {src_length, src_tag}; an_cmd_valid = 1'b1;
            wait_high(an_cmd_ack, "Anvil cmd_req_ack");
            @(negedge clk);
            an_cmd_valid = 1'b0;
            an_cmd_res_ack = 1'b1;
            wait_high(an_cmd_res_valid, "Anvil cmd_res_valid");
            @(negedge clk);
            an_cmd_res_ack = 1'b0;
            an_command_handshakes++;
        end
    endtask

    task automatic send_element_to_sv(input logic [7:0] a, input logic [7:0] b);
        begin
            @(negedge clk);
            src_a = a; src_b = b; sv_in_valid = 1'b1;
            wait_high(sv_in_ready, "SV in_ready");
            @(posedge clk);
            @(negedge clk);
            sv_in_valid = 1'b0;
            sv_element_handshakes++;
        end
    endtask

    task automatic send_element_to_anvil(input logic [7:0] a, input logic [7:0] b);
        begin
            @(negedge clk);
            if ((src_a !== a) || (src_b !== b))
                $fatal(1, "Stimulus mismatch before Anvil element");
            an_elem_data = {src_a, src_b}; an_elem_valid = 1'b1;
            wait_high(an_elem_ack, "Anvil elem_req_ack");
            @(negedge clk);
            an_elem_valid = 1'b0;
            an_elem_res_ack = 1'b1;
            wait_high(an_elem_res_valid, "Anvil elem_res_valid");
            @(negedge clk);
            an_elem_res_ack = 1'b0;
            an_element_handshakes++;
        end
    endtask

    task automatic receive_sv_result(
        input logic [19:0] expected, input logic [3:0] tag, input int stalls,
        output logic [19:0] observed
    );
        begin
            @(negedge clk);
            sv_out_ready = 1'b0;
            wait_high(sv_out_valid, "SV out_valid");
            repeat (stalls) @(posedge clk);
            observed = sv_result;
            if ((observed !== expected) || (sv_out_tag !== tag))
                $fatal(1, "SV result mismatch: got %0d/tag%0d expected %0d/tag%0d",
                       observed, sv_out_tag, expected, tag);
            @(negedge clk);
            sv_out_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            sv_out_ready = 1'b0;
        end
    endtask

    task automatic receive_anvil_result(
        input logic [19:0] expected, input logic [3:0] tag, input int stalls,
        output logic [19:0] observed
    );
        logic [3:0] observed_tag;
        begin
            @(negedge clk);
            an_out_ack = 1'b0;
            wait_high(an_out_valid, "Anvil out_req_valid");
            repeat (stalls) @(posedge clk);
            observed = an_out_data[23:4]; observed_tag = an_out_data[3:0];
            if ((observed !== expected) || (observed_tag !== tag))
                $fatal(1, "Anvil result mismatch: got %0d/tag%0d expected %0d/tag%0d",
                       observed, observed_tag, expected, tag);
            @(negedge clk);
            an_out_ack = 1'b1;
            wait_high(an_out_valid, "Anvil out_req_valid acknowledgement");
            @(negedge clk);
            an_out_ack = 1'b0;
            an_out_res_data = 1'b1; an_out_res_valid = 1'b1;
            wait_high(an_out_res_ack, "Anvil out_res_ack");
            @(negedge clk);
            an_out_res_valid = 1'b0;
        end
    endtask

    task automatic run_matched_case(
        input string name, input logic [7:0] length, input logic [3:0] tag,
        input logic [19:0] expected, input int stalls,
        input logic [7:0] a0, input logic [7:0] b0,
        input logic [7:0] a1, input logic [7:0] b1,
        input logic [7:0] a2, input logic [7:0] b2,
        input logic [7:0] a3, input logic [7:0] b3
    );
        logic [19:0] sv_observed, an_observed;
        int sv_cmd_start, an_cmd_start, sv_elem_start, an_elem_start;
        begin
            $display("\n=== %s ===", name);
            // One common logical source transaction is adapted to each native
            // protocol.  Record handshakes so equality is checked explicitly.
            src_length = length;
            src_tag = tag;
            sv_cmd_start = sv_command_handshakes;
            an_cmd_start = an_command_handshakes;
            sv_elem_start = sv_element_handshakes;
            an_elem_start = an_element_handshakes;
            send_command_to_sv(length, tag);
            send_command_to_anvil(length, tag);
            if ((sv_command_handshakes - sv_cmd_start != 1) ||
                (an_command_handshakes - an_cmd_start != 1))
                $fatal(1, "Command handshake mismatch: SV=%0d Anvil=%0d",
                       sv_command_handshakes - sv_cmd_start,
                       an_command_handshakes - an_cmd_start);

            if (length > 0) begin
                src_a = a0; src_b = b0; send_element_to_sv(a0,b0); send_element_to_anvil(a0,b0);
            end
            if (length > 1) begin
                src_a = a1; src_b = b1; send_element_to_sv(a1,b1); send_element_to_anvil(a1,b1);
            end
            if (length > 2) begin
                src_a = a2; src_b = b2; send_element_to_sv(a2,b2); send_element_to_anvil(a2,b2);
            end
            if (length > 3) begin
                src_a = a3; src_b = b3; send_element_to_sv(a3,b3); send_element_to_anvil(a3,b3);
            end

            if ((sv_element_handshakes - sv_elem_start != int'(length)) ||
                (an_element_handshakes - an_elem_start != int'(length)))
                $fatal(1, "Element handshake mismatch: expected=%0d SV=%0d Anvil=%0d",
                       length, sv_element_handshakes - sv_elem_start,
                       an_element_handshakes - an_elem_start);

            receive_sv_result(expected, tag, stalls, sv_observed);
            receive_anvil_result(expected, tag, stalls, an_observed);
            if (sv_observed !== an_observed)
                $fatal(1, "DIFFERENTIAL FAIL: SV result=%0d, Anvil result=%0d",
                       sv_observed, an_observed);
            $display("PASS: SV=%0d, Anvil=%0d, expected=%0d, tag=%0d", 
                     sv_observed, an_observed, expected, tag);
        end
    endtask

    initial begin
        clk = 1'b0; rst_n = 1'b0;
        src_length = '0; src_tag = '0; src_a = '0; src_b = '0;
        sv_command_handshakes = 0; an_command_handshakes = 0;
        sv_element_handshakes = 0; an_element_handshakes = 0;
        sv_cmd_valid = 1'b0; sv_in_valid = 1'b0; sv_out_ready = 1'b0;
        an_cmd_valid = 1'b0; an_cmd_data = '0; an_cmd_res_ack = 1'b0;
        an_elem_valid = 1'b0; an_elem_data = '0; an_elem_res_ack = 1'b0;
        an_out_ack = 1'b0; an_out_res_valid = 1'b0; an_out_res_data = '0;

        repeat (5) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;

        run_matched_case("TEST 1: length 1", 8'd1, 4'd1, 20'd63, 0,
                         8'd9,8'd7, 8'd0,8'd0, 8'd0,8'd0, 8'd0,8'd0);
        run_matched_case("TEST 2: length 2 with zero operands", 8'd2, 4'd2, 20'd0, 0,
                         8'd0,8'd17, 8'd13,8'd0, 8'd0,8'd0, 8'd0,8'd0);
        run_matched_case("TEST 3: partial group (length 3)", 8'd3, 4'd3, 20'd32, 0,
                         8'd1,8'd4, 8'd2,8'd5, 8'd3,8'd6, 8'd0,8'd0);
        run_matched_case("TEST 4: length 4", 8'd4, 4'd4, 20'd70, 0,
                         8'd1,8'd5, 8'd2,8'd6, 8'd3,8'd7, 8'd4,8'd8);
        run_matched_case("TEST 5A: multiple commands", 8'd4, 4'd5, 20'd30, 0,
                         8'd1,8'd1, 8'd2,8'd2, 8'd3,8'd3, 8'd4,8'd4);
        run_matched_case("TEST 5B: multiple commands", 8'd2, 4'd6, 20'd50, 0,
                         8'd10,8'd1, 8'd20,8'd2, 8'd0,8'd0, 8'd0,8'd0);
        run_matched_case("TEST 6: maximum operands with backpressure", 8'd4, 4'd7, 20'd260100, 3,
                         8'hff,8'hff, 8'hff,8'hff, 8'hff,8'hff, 8'hff,8'hff);

        $display("\nPASS: matched stimulus, both property suites, and differential comparison passed.");
        #20 $finish;
    end

    initial begin
        repeat (5000) @(posedge clk);
        $fatal(1, "Global differential-test timeout");
    end
endmodule
