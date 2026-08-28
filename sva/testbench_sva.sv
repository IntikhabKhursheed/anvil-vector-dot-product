// =============================================================================
// Part B all-in-one test: handwritten RTL plus the six SVA properties.
// It targets four-lane internals, unlike the interface-level Part C test.
// =============================================================================

module dot_product_tb();

    parameter DATA_W = 8;
    parameter LANES  = 4;

    logic clk, rst_n;
    logic cmd_valid, cmd_ready;
    logic [7:0] cmd_length;
    logic [3:0] cmd_tag;
    logic in_valid, in_ready;
    logic [DATA_W-1:0] a_data, b_data;
    logic out_valid, out_ready;
    logic [2*DATA_W+3:0] result;
    logic [3:0] out_tag;

    // DUT
    dot_product #(
        .DATA_W(DATA_W),
        .LANES(LANES)
    ) dut (
        .clk, .rst_n,
        .cmd_valid, .cmd_ready, .cmd_length, .cmd_tag,
        .in_valid, .in_ready, .a_data, .b_data,
        .out_valid, .out_ready, .result, .out_tag
    );

    // Clock
    always #5 clk = ~clk;

    // =============================================================
    // SVA PROPERTIES — Embedded directly in testbench
    // =============================================================

    // Shorthand: command accepted
    wire cmd_accepted = (dut.state_q == dut.IDLE) && cmd_valid && cmd_ready;

    // PROPERTY 1: Output stable under backpressure
    property output_stable_under_backpressure;
        @(posedge clk) disable iff (!rst_n)
        (out_valid && !out_ready)
        |=> ($stable(result) && $stable(out_tag));
    endproperty

    assert_output_stable:
        assert property (output_stable_under_backpressure)
        else $error("FAIL P1: result or tag changed while out_valid=1 and out_ready=0");

    // PROPERTY 2: Inactive lanes contribute zero
    property inactive_lane_no_contribution;
        @(posedge clk) disable iff (!rst_n)
        (dut.state_q == dut.REDUCE &&
         dut.reduce_step_q < 4 &&
         !dut.lane_valid_q[dut.reduce_step_q[1:0]])
        |=> ($stable(dut.accum_q));
    endproperty

    assert_inactive_lane:
        assert property (inactive_lane_no_contribution)
        else $error("FAIL P2: accumulator changed on an inactive lane step");

    // PROPERTY 3: Accumulator resets on new command
    property accumulator_resets_on_new_command;
        @(posedge clk) disable iff (!rst_n)
        cmd_accepted
        |=> (dut.accum_q == '0);
    endproperty

    assert_accumulator_reset:
        assert property (accumulator_resets_on_new_command)
        else $error("FAIL P3: accumulator not zero after new command accepted");

    // PROPERTY 4: out_valid only in OUTPUT state
    property out_valid_only_in_output_state;
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> (dut.state_q == dut.OUTPUT);
    endproperty

    assert_out_valid_state:
        assert property (out_valid_only_in_output_state)
        else $error("FAIL P4: out_valid asserted outside OUTPUT state");

    // PROPERTY 5: No new command while result pending
    property no_new_command_while_result_pending;
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> !cmd_ready;
    endproperty

    assert_no_overlap:
        assert property (no_new_command_while_result_pending)
        else $error("FAIL P5: cmd_ready asserted while out_valid is high");

    // PROPERTY 6: in_ready only in LOAD state
    property in_ready_only_in_load_state;
        @(posedge clk) disable iff (!rst_n)
        in_ready |-> (dut.state_q == dut.LOAD);
    endproperty

    assert_in_ready_state:
        assert property (in_ready_only_in_load_state)
        else $error("FAIL P6: in_ready asserted outside LOAD state");

    // =============================================================
    // TEST SEQUENCE
    // =============================================================
    initial begin
        // Initialize
        clk = 0;
        rst_n = 0;
        cmd_valid = 0;
        in_valid = 0;
        out_ready = 1;
        cmd_length = 0;
        cmd_tag = 0;
        a_data = 0;
        b_data = 0;

        // Reset
        #10 rst_n = 1;
        #10;

        // =============================================================
        // TEST 1: Normal operation (length = 4)
        // =============================================================
        $display("\n=== TEST 1: Normal operation (length=4) ===");

        cmd_valid = 1;
        cmd_length = 4;
        cmd_tag = 1;
        #10;
        cmd_valid = 0;

        in_valid = 1;
        a_data = 1; b_data = 5; #10;
        a_data = 2; b_data = 6; #10;
        a_data = 3; b_data = 7; #10;
        a_data = 4; b_data = 8; #10;
        in_valid = 0;

        while (!out_valid) #10;
        $display("Result for tag %d = %d (expected 70)", out_tag, result);
        #10;

        // =============================================================
        // TEST 2: Partial group (length = 3)
        // =============================================================
        $display("\n=== TEST 2: Partial group (length=3) ===");

        while (!cmd_ready) #10;

        cmd_valid = 1;
        cmd_length = 3;
        cmd_tag = 2;
        #10;
        cmd_valid = 0;

        in_valid = 1;
        a_data = 1; b_data = 4; #10;
        a_data = 2; b_data = 5; #10;
        a_data = 3; b_data = 6; #10;
        in_valid = 0;

        while (!out_valid) #10;
        $display("Result for tag %d = %d (expected 32)", out_tag, result);
        #10;

        // =============================================================
        // TEST 3: Multiple commands
        // =============================================================
        $display("\n=== TEST 3: Multiple commands ===");

        while (!cmd_ready) #10;
        cmd_valid = 1; cmd_length = 4; cmd_tag = 3; #10; cmd_valid = 0;
        in_valid = 1;
        a_data = 1; b_data = 1; #10;
        a_data = 2; b_data = 2; #10;
        a_data = 3; b_data = 3; #10;
        a_data = 4; b_data = 4; #10;
        in_valid = 0;
        while (!out_valid) #10;
        $display("Result for tag %d = %d (expected 30)", out_tag, result);
        #10;

        while (!cmd_ready) #10;
        cmd_valid = 1; cmd_length = 2; cmd_tag = 4; #10; cmd_valid = 0;
        in_valid = 1;
        a_data = 10; b_data = 1; #10;
        a_data = 20; b_data = 2; #10;
        in_valid = 0;
        while (!out_valid) #10;
        $display("Result for tag %d = %d (expected 50)", out_tag, result);
        #10;

        // =============================================================
        // TEST 4: Backpressure Test
        // =============================================================
        $display("\n=== TEST 4: Backpressure Test ===");

        while (!cmd_ready) #10;
        cmd_valid = 1; cmd_length = 4; cmd_tag = 5; #10; cmd_valid = 0;
        in_valid = 1;
        a_data = 1; b_data = 1; #10;
        a_data = 2; b_data = 2; #10;
        a_data = 3; b_data = 3; #10;
        a_data = 4; b_data = 4; #10;
        in_valid = 0;

        while (!out_valid) #10;
        $display("Result valid asserted for tag %d", out_tag);
        
        out_ready = 0;
        #30;
        out_ready = 1;
        #10;
        $display("Result for tag %d = %d (expected 30) - released after backpressure", out_tag, result);
        #10;

        $display("\n=== All tests complete ===");
        $finish;
    end

endmodule
