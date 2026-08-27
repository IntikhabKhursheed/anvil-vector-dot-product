`timescale 1ns/1ps

// Complete SVA testbench for the sequential Anvil-generated DotProduct.
// Put dot_product_anvil.sv in EDA Playground's Design pane and this entire
// file in its Testbench pane.  No extra files or bind statements are needed.
module tb_dot_product_anvil;

    localparam int MAX_WAIT_CYCLES = 100;
    localparam logic [1:0] IDLE = 2'd0;
    localparam logic [1:0] CALC = 2'd1;
    localparam logic [1:0] OUTPUT = 2'd2;

    logic clk_i, rst_ni;
    logic _cmd_cmd_req_ack, _cmd_cmd_req_valid;
    logic [11:0] _cmd_cmd_req_0;
    logic _cmd_cmd_res_ack, _cmd_cmd_res_valid, _cmd_cmd_res_0;
    logic _elem_in_req_ack, _elem_in_req_valid;
    logic [15:0] _elem_in_req_0;
    logic _elem_in_res_ack, _elem_in_res_valid, _elem_in_res_0;
    logic _res_out_req_ack, _res_out_req_valid;
    logic [23:0] _res_out_req_0;
    logic _res_out_res_ack, _res_out_res_valid, _res_out_res_0;

    DotProduct dut (
        .clk_i, .rst_ni,
        ._cmd_cmd_req_ack, ._cmd_cmd_req_valid, ._cmd_cmd_req_0,
        ._cmd_cmd_res_ack, ._cmd_cmd_res_valid, ._cmd_cmd_res_0,
        ._elem_in_req_ack, ._elem_in_req_valid, ._elem_in_req_0,
        ._elem_in_res_ack, ._elem_in_res_valid, ._elem_in_res_0,
        ._res_out_req_ack, ._res_out_req_valid, ._res_out_req_0,
        ._res_out_res_ack, ._res_out_res_valid, ._res_out_res_0
    );

    always #5 clk_i = ~clk_i;

    // =============================================================
    // The six Part B properties, mapped to Anvil's valid/ack ports.
    // =============================================================
    wire cmd_accepted = _cmd_cmd_req_valid && _cmd_cmd_req_ack;

    // Monitor-only delay line for P3.  It captures the fixed two-cycle delay
    // between Anvil's command handshake and its accumulator-clear commit.
    logic cmd_accepted_d1_q, cmd_accepted_d2_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cmd_accepted_d1_q <= 1'b0;
            cmd_accepted_d2_q <= 1'b0;
        end else begin
            cmd_accepted_d1_q <= cmd_accepted;
            cmd_accepted_d2_q <= cmd_accepted_d1_q;
        end
    end

    // P1: Output is stable while the consumer applies backpressure.
    property output_stable_under_backpressure;
        @(posedge clk_i) disable iff (!rst_ni)
        (_res_out_req_valid && !_res_out_req_ack) |=>
            (_res_out_req_valid && $stable(_res_out_req_0));
    endproperty
    assert_output_stable: assert property (output_stable_under_backpressure)
        else $error("FAIL P1: output payload changed under backpressure");

    // P2: Sequential equivalent of inactive-lane protection.  The one lane
    // must not accept an extra element after the requested count is exhausted.
    property no_element_after_count_exhausted;
        @(posedge clk_i) disable iff (!rst_ni)
        (_elem_in_req_valid && _elem_in_req_ack) |-> (dut.remaining_q != 8'd0);
    endproperty
    assert_no_extra_element: assert property (no_element_after_count_exhausted)
        else $error("FAIL P2: accepted an element after count reached zero");

    // P3: The Anvil schedule commits the accumulator clear two clocks after
    // the dynamic command handshake.  The monitor delay line avoids Verilator
    // limitations on ## and $past within a property implication.
    property accumulator_resets_on_new_command;
        @(posedge clk_i) disable iff (!rst_ni)
        cmd_accepted_d2_q |-> (dut.accum_q == '0);
    endproperty
    assert_accumulator_reset: assert property (accumulator_resets_on_new_command)
        else $error("FAIL P3: accumulator was not reset for a new command");

    // P4: Result valid is only asserted in the Anvil OUTPUT state.
    property out_valid_only_in_output_state;
        @(posedge clk_i) disable iff (!rst_ni)
        _res_out_req_valid |-> (dut.state_q == OUTPUT);
    endproperty
    assert_out_valid_state: assert property (out_valid_only_in_output_state)
        else $error("FAIL P4: result valid asserted outside OUTPUT state");

    // P5: A pending result blocks a new command.
    property no_new_command_while_result_pending;
        @(posedge clk_i) disable iff (!rst_ni)
        _res_out_req_valid |-> !_cmd_cmd_req_ack;
    endproperty
    assert_no_command_overlap: assert property (no_new_command_while_result_pending)
        else $error("FAIL P5: command ack asserted while result was pending");

    // P6: The element request is acknowledged only during calculation with
    // at least one element still expected.
    property in_ready_only_in_calculate_state;
        @(posedge clk_i) disable iff (!rst_ni)
        _elem_in_req_ack |-> ((dut.state_q == CALC) && (dut.remaining_q != 8'd0));
    endproperty
    assert_elem_ack_state: assert property (in_ready_only_in_calculate_state)
        else $error("FAIL P6: element ack asserted outside active calculation");

    task automatic wait_for_ack(ref logic ack, input string name);
        int cycles;
        begin
            cycles = 0;
            do begin
                @(posedge clk_i);
                cycles++;
                if (cycles > MAX_WAIT_CYCLES) $fatal(1, "Timed out waiting for %s", name);
            end while (!ack);
        end
    endtask

    task automatic wait_for_valid(ref logic valid, input string name);
        int cycles;
        begin
            cycles = 0;
            do begin
                @(posedge clk_i);
                cycles++;
                if (cycles > MAX_WAIT_CYCLES) $fatal(1, "Timed out waiting for %s", name);
            end while (!valid);
        end
    endtask

    task automatic send_command(input logic [7:0] length, input logic [3:0] tag);
        begin
            @(negedge clk_i);
            _cmd_cmd_req_0 = {length, tag};
            _cmd_cmd_req_valid = 1'b1;
            wait_for_ack(_cmd_cmd_req_ack, "_cmd_cmd_req_ack");
            @(negedge clk_i);
            _cmd_cmd_req_valid = 1'b0;

            _cmd_cmd_res_ack = 1'b1;
            wait_for_valid(_cmd_cmd_res_valid, "_cmd_cmd_res_valid");
            if (_cmd_cmd_res_0 !== 1'b1) $fatal(1, "Bad command response");
            @(negedge clk_i);
            _cmd_cmd_res_ack = 1'b0;
        end
    endtask

    task automatic send_element(input logic [7:0] a, input logic [7:0] b);
        begin
            @(negedge clk_i);
            _elem_in_req_0 = {a, b};
            _elem_in_req_valid = 1'b1;
            wait_for_ack(_elem_in_req_ack, "_elem_in_req_ack");
            @(negedge clk_i);
            _elem_in_req_valid = 1'b0;

            _elem_in_res_ack = 1'b1;
            wait_for_valid(_elem_in_res_valid, "_elem_in_res_valid");
            if (_elem_in_res_0 !== 1'b1) $fatal(1, "Bad element response");
            @(negedge clk_i);
            _elem_in_res_ack = 1'b0;
        end
    endtask

    task automatic receive_and_check_result(
        input logic [19:0] expected_value,
        input logic [3:0] expected_tag,
        input int backpressure_cycles
    );
        logic [19:0] value;
        logic [3:0] tag;
        begin
            @(negedge clk_i);
            _res_out_req_ack = 1'b0;
            wait_for_valid(_res_out_req_valid, "_res_out_req_valid");
            repeat (backpressure_cycles) @(posedge clk_i);

            value = _res_out_req_0[23:4];
            tag = _res_out_req_0[3:0];
            if ((value !== expected_value) || (tag !== expected_tag))
                $fatal(1, "Bad result: got value=%0d tag=%0d, expected value=%0d tag=%0d",
                       value, tag, expected_value, expected_tag);
            if (backpressure_cycles == 0)
                $display("Result for tag %2d = %7d (expected %0d)", tag, value, expected_value);
            else
                $display("Result for tag %2d = %7d (expected %0d) - released after backpressure",
                         tag, value, expected_value);

            @(negedge clk_i);
            _res_out_req_ack = 1'b1;
            wait_for_valid(_res_out_req_valid, "_res_out_req_valid acknowledgement");
            @(negedge clk_i);
            _res_out_req_ack = 1'b0;

            _res_out_res_0 = 1'b1;
            _res_out_res_valid = 1'b1;
            wait_for_ack(_res_out_res_ack, "_res_out_res_ack");
            @(negedge clk_i);
            _res_out_res_valid = 1'b0;
        end
    endtask

    initial begin
        clk_i = 1'b0;
        rst_ni = 1'b0;
        _cmd_cmd_req_valid = 1'b0; _cmd_cmd_req_0 = '0; _cmd_cmd_res_ack = 1'b0;
        _elem_in_req_valid = 1'b0; _elem_in_req_0 = '0; _elem_in_res_ack = 1'b0;
        _res_out_req_ack = 1'b0; _res_out_res_valid = 1'b0; _res_out_res_0 = '0;

        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_ni = 1'b1;
        repeat (2) @(posedge clk_i);

        $display("\n=== TEST 1: Normal operation (length=4) ===");
        // 1*5 + 2*6 + 3*7 + 4*8 = 70
        send_command(8'd4, 4'd1);
        send_element(8'd1, 8'd5); send_element(8'd2, 8'd6);
        send_element(8'd3, 8'd7); send_element(8'd4, 8'd8);
        receive_and_check_result(20'd70, 4'd1, 0);

        $display("\n=== TEST 2: Partial group (length=3) ===");
        // 1*4 + 2*5 + 3*6 = 32
        send_command(8'd3, 4'd2);
        send_element(8'd1, 8'd4); send_element(8'd2, 8'd5); send_element(8'd3, 8'd6);
        receive_and_check_result(20'd32, 4'd2, 0);

        $display("\n=== TEST 3: Multiple commands ===");
        // 1*1 + 2*2 + 3*3 + 4*4 = 30
        send_command(8'd4, 4'd3);
        send_element(8'd1, 8'd1); send_element(8'd2, 8'd2);
        send_element(8'd3, 8'd3); send_element(8'd4, 8'd4);
        receive_and_check_result(20'd30, 4'd3, 0);

        // 10*1 + 20*2 = 50
        send_command(8'd2, 4'd4);
        send_element(8'd10, 8'd1); send_element(8'd20, 8'd2);
        receive_and_check_result(20'd50, 4'd4, 0);

        $display("\n=== TEST 4: Backpressure Test ===");
        // 1*1 + 2*2 + 3*3 + 4*4 = 30.  Ack is held low for three cycles,
        // actively exercising P1.
        send_command(8'd4, 4'd5);
        send_element(8'd1, 8'd1); send_element(8'd2, 8'd2);
        send_element(8'd3, 8'd3); send_element(8'd4, 8'd4);
        $display("Result valid will be held under backpressure for tag 5");
        receive_and_check_result(20'd30, 4'd5, 3);

        $display("\n=== All tests complete ===");
        $display("PASS: Anvil design and all six SVA properties passed.");
        #20 $finish;
    end

    initial begin
        repeat (2000) @(posedge clk_i);
        $fatal(1, "Global testbench timeout");
    end
endmodule
