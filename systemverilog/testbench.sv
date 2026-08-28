// Part A functional smoke test for the handwritten four-lane accelerator.
// The matched-stimulus comparison with generated Anvil SV is in
// sva/testbench_equivalence.sv.

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

    // Generate clock
    always #5 clk = ~clk;

    // Main test sequence
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

        // Wait for reset to finish
        #10 rst_n = 1;
        #10;

        // Test 1: Full group of 4 elements
        // [1,2,3,4] · [5,6,7,8] = 1*5 + 2*6 + 3*7 + 4*8 = 70
        $display("\n=== TEST 1: Normal operation (length=4) ===");

        // Send command
        cmd_valid = 1;
        cmd_length = 4;
        cmd_tag = 1;
        #10;
        cmd_valid = 0;

        // Send elements
        in_valid = 1;
        a_data = 1; b_data = 5; #10;  // elem 0
        a_data = 2; b_data = 6; #10;  // elem 1
        a_data = 3; b_data = 7; #10;  // elem 2
        a_data = 4; b_data = 8; #10;  // elem 3
        in_valid = 0;

        // Wait for result
        while (!out_valid) #10;
        $display("Result for tag %d = %d (expected 70)", out_tag, result);
        #10;

        // Test 2: Partial group of 3 elements
        // [1,2,3] · [4,5,6] = 1*4 + 2*5 + 3*6 = 4+10+18 = 32
        $display("\n=== TEST 2: Partial group (length=3) ===");

        // Wait for the DUT to accept the command
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

        // Second command
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

        // Wait for output valid
        while (!out_valid) #10;
        $display("Result valid asserted for tag %d", out_tag);
        
        // Apply backpressure (hold out_ready low for 3 cycles)
        out_ready = 0;
        #30;
        out_ready = 1;
        #10;
        $display("Result for tag %d = %d (expected 30) - released after backpressure", out_tag, result);
        #10;

        $display("\n=== All tests complete ===");
        // Done
        $display("\n=== Tests complete ===");
        $finish;
    end

endmodule
