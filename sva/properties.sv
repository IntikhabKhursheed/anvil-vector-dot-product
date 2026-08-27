// Formal verification properties for the dot-product accelerator
// These catch bugs if the design misbehaves

module properties (
    input logic                 clk,
    input logic                 rst_n,

    // Command interface
    input logic                 cmd_valid,
    input logic                 cmd_ready,
    input logic [3:0]           cmd_tag,
    input logic [7:0]           cmd_length,

    // Input stream
    input logic                 in_valid,
    input logic                 in_ready,

    // Output interface
    input logic                 out_valid,
    input logic                 out_ready,
    input logic [19:0]          result,
    input logic [3:0]           out_tag,

    // Internal signals (bound from DUT)
    input logic [19:0]          accum_q,
    input logic [3:0]           state_q,
    input logic [2:0]           reduce_step_q,
    input logic [3:0]           lane_valid_q [4]
);

    // Helpers for readability
    wire cmd_accepted = (state_q == 2'b00) && cmd_valid && cmd_ready;  // new command just accepted
    wire elem_accepted = (state_q == 2'b01) && in_valid && in_ready;    // element just accepted
    wire result_accepted = out_valid && out_ready;                       // result just accepted


    // P1: Result stays the same if downstream isn't ready
    property output_stable_under_backpressure;
        @(posedge clk) disable iff (!rst_n)
        (out_valid && !out_ready)
        |=> ($stable(result) && $stable(out_tag));
    endproperty

    assert_output_stable:
        assert property (output_stable_under_backpressure)
        else $error("FAIL P1: result or tag changed while out_valid=1 and out_ready=0");


    // P2: Unused lanes don't mess up the sum
    property inactive_lane_no_contribution;
        @(posedge clk) disable iff (!rst_n)
        (state_q == 2'b10 &&
         reduce_step_q < 4 &&
         !lane_valid_q[reduce_step_q[1:0]])
        |=> ($stable(accum_q));
    endproperty

    assert_inactive_lane:
        assert property (inactive_lane_no_contribution)
        else $error("FAIL P2: accumulator changed on an inactive lane step");


    // P3: Fresh start for each command
    // No leftover garbage from the previous command
    property accumulator_resets_on_new_command;
        @(posedge clk) disable iff (!rst_n)
        cmd_accepted
        |=> (accum_q == '0);
    endproperty

    assert_accumulator_reset:
        assert property (accumulator_resets_on_new_command)
        else $error("FAIL P3: accumulator not zero after new command accepted");


    // P4: Result only signals when actually ready
    // (not by accident during other states)
    property out_valid_only_in_output_state;
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> (state_q == 2'b11);
    endproperty

    assert_out_valid_state:
        assert property (out_valid_only_in_output_state)
        else $error("FAIL P4: out_valid asserted outside OUTPUT state");


    // P5: Can't accept new commands while sending result
    // Prevents state corruption
    property no_new_command_while_result_pending;
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> !cmd_ready;
    endproperty

    assert_no_overlap:
        assert property (no_new_command_while_result_pending)
        else $error("FAIL P5: cmd_ready asserted while out_valid is high");


    // P6: Elements only accepted when chip is ready for them
    property in_ready_only_in_load_state;
        @(posedge clk) disable iff (!rst_n)
        in_ready |-> (state_q == 2'b01);
    endproperty

    assert_in_ready_state:
        assert property (in_ready_only_in_load_state)
        else $error("FAIL P6: in_ready asserted outside LOAD state");


endmodule