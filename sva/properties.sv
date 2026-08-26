// =============================================================
// SVA Properties — Vector Dot-Product Accelerator
// These assertions check that the design behaves correctly.
// Run alongside the testbench in simulation.
// A failed assertion means the design broke a rule.
// =============================================================

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

    // Shorthand: a command handshake just happened
    // Both sides agreed — chip accepted the command this cycle
    wire cmd_accepted = (state_q == 2'b00) && cmd_valid && cmd_ready;

    // Shorthand: an element was accepted this cycle
    wire elem_accepted = (state_q == 2'b01) && in_valid && in_ready;

    // Shorthand: result was accepted this cycle
    wire result_accepted = out_valid && out_ready;


    // =========================================================
    // PROPERTY 1: Output stability under backpressure
    //
    // Rule: If result is ready (out_valid=1) but downstream is not ready (out_ready=0), then result and tag must
    // not change on the next clock cycle.
    //
    // What it protects: Ensures the caller can safely read the result even if it takes multiple cycles to accept it.
    //
    // Bug it catches: A design that overwrites result_q before the caller reads it would lose data silently.
    //
    // Violation looks like: result changes value while out_valid=1 and out_ready=0 — caller reads wrong data.
    // =========================================================
    property output_stable_under_backpressure;
        @(posedge clk) disable iff (!rst_n)
        (out_valid && !out_ready)
        |=> ($stable(result) && $stable(out_tag));
    endproperty

    assert_output_stable:
        assert property (output_stable_under_backpressure)
        else $error("FAIL P1: result or tag changed while out_valid=1 and out_ready=0");


    // =========================================================
    // PROPERTY 2: Inactive lanes contribute zero to accumulator
    //
    // Rule: In REDUCE state, if a lane's valid flag is 0, the accumulator must not change on that step.
    //
    // What it protects: Ensures partial final groups are handled correctly — only active lanes affect the result.
    //
    // Bug it catches: If an inactive lane's garbage value (leftover from a previous command) were added, the
    // result would be larger than the correct dot product.
    //
    // Violation looks like: accum_q changes on a step where the corresponding lane_valid_q is 0.
    // =========================================================
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


    // =========================================================
    // PROPERTY 3: Accumulator resets on every new command
    //
    // Rule: The cycle after a command is accepted, the accumulator must be zero.
    //
    // What it protects: Ensures each command starts with aclean accumulator — no leftover from previous commands.
    //
    // Bug it catches: This is the bug in dot_product_broken.sv. Without the reset, previous results leak into the next
    // command and produce results that grow with each command.
    //
    // Violation looks like: accum_q is non-zero one cycle
    // after a command handshake — exactly what the broken design does.
    // =========================================================
    property accumulator_resets_on_new_command;
        @(posedge clk) disable iff (!rst_n)
        cmd_accepted
        |=> (accum_q == '0);
    endproperty

    assert_accumulator_reset:
        assert property (accumulator_resets_on_new_command)
        else $error("FAIL P3: accumulator not zero after new command accepted");


    // =========================================================
    // PROPERTY 4: out_valid is only high in OUTPUT state
    //
    // Rule: out_valid must be 1 only when state is OUTPUT.
    // It must be 0 in all other states.
    //
    // What it protects: Ensures the chip never signals a result is ready when it is still computing or loading.
    //
    // Bug it catches: A glitch in state machine logic that accidentally asserts out_valid too early would give
    // the caller a garbage or partial result.
    //
    // Violation looks like: out_valid=1 seen while chip is
    // in IDLE, LOAD, or REDUCE state.
    // =========================================================
    property out_valid_only_in_output_state;
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> (state_q == 2'b11);
    endproperty

    assert_out_valid_state:
        assert property (out_valid_only_in_output_state)
        else $error("FAIL P4: out_valid asserted outside OUTPUT state");


    // =========================================================
    // PROPERTY 5: No new command accepted while result pending
    //
    // Rule: cmd_ready must be 0 whenever out_valid is 1. The chip cannot accept a new command while delivering
    // the current result.
    //
    // What it protects: Ensures command and output interfaces do not interfere — a new command cannot overwrite the
    // state needed to complete the current result delivery.
    //
    // Bug it catches: If cmd_ready were asserted during OUTPUT, a new command could corrupt tag_q, length_q, and accum_q
    // before the current result is safely delivered.
    //
    // Violation looks like: cmd_ready=1 and out_valid=1 at the same time.
    // =========================================================
    property no_new_command_while_result_pending;
        @(posedge clk) disable iff (!rst_n)
        out_valid |-> !cmd_ready;
    endproperty

    assert_no_overlap:
        assert property (no_new_command_while_result_pending)
        else $error("FAIL P5: cmd_ready asserted while out_valid is high");


    // =========================================================
    // PROPERTY 6: in_ready only high in LOAD state
    //
    // Rule: in_ready must be 1 only when state is LOAD.
    // Elements can only be accepted during LOAD.

    // What it protects: Ensures elements are never accepted while the chip is reducing or outputting — accepting
    // an element in the wrong state would write to wrong lane slots or corrupt the current computation.
    //
    // Bug it catches: A state machine bug that leaves in_ready high during REDUCE would allow stray elements to enter.
    //
    // Violation looks like: in_ready=1 while state is IDLE,
    // REDUCE, or OUTPUT.
    // =========================================================
    property in_ready_only_in_load_state;
        @(posedge clk) disable iff (!rst_n)
        in_ready |-> (state_q == 2'b01);
    endproperty

    assert_in_ready_state:
        assert property (in_ready_only_in_load_state)
        else $error("FAIL P6: in_ready asserted outside LOAD state");


endmodule