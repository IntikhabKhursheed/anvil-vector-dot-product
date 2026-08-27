`timescale 1ns/1ps

// Testbench for the Anvil-generated DotProduct module.
// Dynamic Anvil channels transfer on a rising edge when valid and ack are high.
// Controls are driven on falling edges, so there is no testbench/DUT race.
module tb_dot_product_anvil;

    localparam int MAX_WAIT_CYCLES = 100;

    logic clk_i;
    logic rst_ni;

    logic        _cmd_cmd_req_ack;
    logic        _cmd_cmd_req_valid;
    logic [11:0] _cmd_cmd_req_0;
    logic        _cmd_cmd_res_ack;
    logic        _cmd_cmd_res_valid;
    logic        _cmd_cmd_res_0;

    logic        _elem_in_req_ack;
    logic        _elem_in_req_valid;
    logic [15:0] _elem_in_req_0;
    logic        _elem_in_res_ack;
    logic        _elem_in_res_valid;
    logic        _elem_in_res_0;

    logic        _res_out_req_ack;
    logic        _res_out_req_valid;
    logic [23:0] _res_out_req_0;
    logic        _res_out_res_ack;
    logic        _res_out_res_valid;
    logic        _res_out_res_0;

    DotProduct dut (
        .clk_i, .rst_ni,
        ._cmd_cmd_req_ack, ._cmd_cmd_req_valid, ._cmd_cmd_req_0,
        ._cmd_cmd_res_ack, ._cmd_cmd_res_valid, ._cmd_cmd_res_0,
        ._elem_in_req_ack, ._elem_in_req_valid, ._elem_in_req_0,
        ._elem_in_res_ack, ._elem_in_res_valid, ._elem_in_res_0,
        ._res_out_req_ack, ._res_out_req_valid, ._res_out_req_0,
        ._res_out_res_ack, ._res_out_res_valid, ._res_out_res_0
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

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
            _cmd_cmd_req_0     = {length, tag};
            _cmd_cmd_req_valid = 1'b1;
            wait_for_ack(_cmd_cmd_req_ack, "_cmd_cmd_req_ack");
            @(negedge clk_i);
            _cmd_cmd_req_valid = 1'b0;

            _cmd_cmd_res_ack = 1'b1;
            wait_for_valid(_cmd_cmd_res_valid, "_cmd_cmd_res_valid");
            if (_cmd_cmd_res_0 !== 1'b1) $fatal(1, "Command response payload was not 1");
            @(negedge clk_i);
            _cmd_cmd_res_ack = 1'b0;
        end
    endtask

    task automatic send_element(input logic [7:0] a, input logic [7:0] b);
        begin
            @(negedge clk_i);
            _elem_in_req_0     = {a, b};
            _elem_in_req_valid = 1'b1;
            wait_for_ack(_elem_in_req_ack, "_elem_in_req_ack");
            @(negedge clk_i);
            _elem_in_req_valid = 1'b0;

            _elem_in_res_ack = 1'b1;
            wait_for_valid(_elem_in_res_valid, "_elem_in_res_valid");
            if (_elem_in_res_0 !== 1'b1) $fatal(1, "Element response payload was not 1");
            @(negedge clk_i);
            _elem_in_res_ack = 1'b0;
        end
    endtask

    task automatic receive_and_check_result(
        input logic [19:0] expected_value,
        input logic [3:0] expected_tag
    );
        logic [19:0] value;
        logic [3:0] tag;
        begin
            @(negedge clk_i);
            _res_out_req_ack = 1'b1;
            wait_for_valid(_res_out_req_valid, "_res_out_req_valid");
            value = _res_out_req_0[23:4];
            tag = _res_out_req_0[3:0];

        $display("Result: value=%0d, tag=%0d (expected %0d, %0d)", 
                 value, tag, expected_value, expected_tag);

            if ((value !== expected_value) || (tag !== expected_tag))
                $fatal(1, "Bad result: got value=%0d tag=%0d, expected value=%0d tag=%0d",
                       value, tag, expected_value, expected_tag);
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
        _cmd_cmd_req_valid = 1'b0;
        _cmd_cmd_req_0 = '0;
        _cmd_cmd_res_ack = 1'b0;
        _elem_in_req_valid = 1'b0;
        _elem_in_req_0 = '0;
        _elem_in_res_ack = 1'b0;
        _res_out_req_ack = 1'b0;
        _res_out_res_valid = 1'b0;
        _res_out_res_0 = '0;

        rst_ni = 1'b0;
        repeat (5) @(posedge clk_i);
        @(negedge clk_i);
        rst_ni = 1'b1;
        repeat (2) @(posedge clk_i);

        // 1*5 + 2*6 + 3*7 + 4*8 = 70
        send_command(8'd4, 4'd1);
        send_element(8'd1, 8'd5);
        send_element(8'd2, 8'd6);
        send_element(8'd3, 8'd7);
        send_element(8'd4, 8'd8);
        receive_and_check_result(20'd70, 4'd1);

        // 3*4 + 5*6 + 7*8 = 98
        send_command(8'd3, 4'd2);
        send_element(8'd3, 8'd4);
        send_element(8'd5, 8'd6);
        send_element(8'd7, 8'd8);
        receive_and_check_result(20'd98, 4'd2);

        // Zero length and a full-width product check.
        send_command(8'd0, 4'hf);
        receive_and_check_result(20'd0, 4'hf);

        // 255*255 + 16*17 = 65297
        send_command(8'd2, 4'd3);
        send_element(8'hff, 8'hff);
        send_element(8'd16, 8'd17);
        receive_and_check_result(20'd65297, 4'd3);

        $display("PASS: all dot-product tests completed.");
        #20;
        $finish;
    end

    initial begin
        repeat (2000) @(posedge clk_i);
        $fatal(1, "Global testbench timeout");
    end

endmodule
