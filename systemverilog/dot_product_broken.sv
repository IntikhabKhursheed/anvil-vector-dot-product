// =============================================================================
// Vector Dot-Product Accelerator — SystemVerilog Implementation (CLEAN)
// Architecture : 4 parallel multiply lanes, shared multi-cycle accumulator
// Interface    : ready/valid handshake for input and output backpressure
// All Verilator WIDTHTRUNC and WIDTHEXPAND warnings resolved.
// =============================================================================

module dot_product #(
    parameter DATA_W  = 8,    // bit-width of each input element (A and B)
    parameter LANES   = 4,    // number of parallel multiply lanes
    parameter MAX_LEN = 16    // maximum supported vector length
) (
    input  logic                  clk,        // clock — all registers update on rising edge
    input  logic                  rst_n,      // active-low synchronous reset

    // ------------------------------------------------------------------
    // Command interface — caller sends a new dot-product job here
    // ------------------------------------------------------------------
    input  logic                  cmd_valid,  // caller asserts: "I have a new command"
    output logic                  cmd_ready,  // chip asserts: "I can accept a command now"
    input  logic [7:0]            cmd_length, // how many element pairs to process
    input  logic [3:0]            cmd_tag,    // identifier tag to match result to command

    // ------------------------------------------------------------------
    // Input stream interface — element pairs arrive here one per cycle
    // ------------------------------------------------------------------
    input  logic                  in_valid,   // caller asserts: "element pair is valid"
    output logic                  in_ready,   // chip asserts: "I can accept an element now"
    input  logic [DATA_W-1:0]     a_data,     // A vector element
    input  logic [DATA_W-1:0]     b_data,     // B vector element

    // ------------------------------------------------------------------
    // Output interface — result is held here until downstream accepts it
    // ------------------------------------------------------------------
    output logic                  out_valid,       // chip asserts: "result is ready"
    input  logic                  out_ready,       // caller asserts: "I can accept the result"
    output logic [2*DATA_W+3:0]   result,          // final dot-product sum (wide to avoid overflow)
    output logic [3:0]            out_tag          // tag copied from the accepted command
);

    // ==========================================================================
    // STATE MACHINE TYPE
    // The chip moves through four states for every dot-product command.
    // ==========================================================================
    typedef enum logic [1:0] {
        IDLE   = 2'b00,   // waiting for a new command
        LOAD   = 2'b01,   // loading element pairs into lane registers
        REDUCE = 2'b10,   // adding lane products into the accumulator, one per cycle
        OUTPUT = 2'b11    // holding result stable until downstream accepts it
    } state_t;

    state_t state_q;   // current state register — updates on clock edge
    state_t state_d;   // next state — combinational, computed every cycle

    // ==========================================================================
    // COMMAND REGISTERS — saved when a command is accepted
    // ==========================================================================
    logic [7:0] length_q;   // total number of element pairs for this command
    logic [3:0] tag_q;      // tag for this command — copied to output when done

    // ==========================================================================
    // ELEMENT COUNTER
    // Counts how many elements have been loaded so far for the current command.
    // ==========================================================================
    logic [7:0] elem_count_q;   // increments every time an element is accepted in LOAD

    // ==========================================================================
    // LANE REGISTERS — one slot per lane, filled during LOAD state
    // ==========================================================================
    logic [DATA_W-1:0] lane_a_q   [LANES];   // A element stored for each lane
    logic [DATA_W-1:0] lane_b_q   [LANES];   // B element stored for each lane
    logic              lane_valid_q[LANES];   // 1 = this lane has valid data; 0 = inactive (partial group)

    // ==========================================================================
    // LANE PRODUCTS — combinational wires, computed continuously from registers
    // All 4 multiplications happen in parallel every clock cycle.
    // Width is 2*DATA_W to hold the full product without overflow.
    // ==========================================================================
    logic [2*DATA_W-1:0] lane_prod[LANES];

    // ==========================================================================
    // ACCUMULATOR
    // Wider than lane_prod to safely accumulate up to MAX_LEN products.
    // 2*DATA_W+4 bits = 20 bits, enough for 16 x 255 x 255 = 1,040,400.
    // ==========================================================================
    logic [2*DATA_W+3:0] accum_q;   // running sum; reset to zero on every new command

    // ==========================================================================
    // OUTPUT REGISTERS — latched when computation finishes, held stable under backpressure
    // ==========================================================================
    logic [2*DATA_W+3:0] result_q;    // final sum copied from accum_q
    logic [3:0]          tag_out_q;   // tag copied from tag_q

    // ==========================================================================
    // FILL COUNTER
    // Tracks how many lane slots have been filled in the current group.
    // Resets to 0 at the start of every new group.
    // Uses 2-bit index for lane array (LANES=4, needs index 0-3 = 2 bits).
    // Declared 3-bit to count 0 through LANES (0 through 4) without overflow.
    // ==========================================================================
    logic [2:0] fill_q;   // current fill count; 0..LANES

    // ==========================================================================
    // REDUCE STEP COUNTER
    // Counts which lane is being added to the accumulator in REDUCE state.
    // Also 3-bit to count 0 through LANES (0 through 4) without overflow.
    // ==========================================================================
    logic [2:0] reduce_step_q;   // 0..LANES; when it reaches LANES, all lanes processed

    // ==========================================================================
    // LANE PRODUCT GENERATION — parallel combinational multipliers
    // generate..for creates 4 separate multiply circuits, all running simultaneously.
    // ==========================================================================
    genvar i;
    generate
        for (i = 0; i < LANES; i++) begin : lane_mult
            // Each lane continuously computes its product from stored registers.
            // This is real hardware parallelism — 4 multipliers active every cycle.
            assign lane_prod[i] = lane_a_q[i] * lane_b_q[i];
        end
    endgenerate

    // ==========================================================================
    // LANE FILL LOGIC
    // Captures incoming element pairs into lane register slots during LOAD state.
    // Uses fill_q[1:0] to index the 4-element array — suppresses WIDTHTRUNC.
    // ==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // On reset: clear all lane registers and fill counter
            fill_q <= 3'd0;
            for (int j = 0; j < LANES; j++) begin
                lane_a_q[j]      <= '0;   // clear A register for lane j
                lane_b_q[j]      <= '0;   // clear B register for lane j
                lane_valid_q[j]  <= 1'b0; // mark lane j as invalid
            end

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
            // New command accepted: reset fill counter and invalidate all lanes
            fill_q <= 3'd0;
            for (int j = 0; j < LANES; j++) begin
                lane_valid_q[j] <= 1'b0; // all lanes inactive at start of new command
            end

        end else if (state_q == LOAD && in_valid && in_ready) begin
            // Element accepted: write into the lane slot pointed to by fill_q
            // fill_q[1:0] — explicit 2-bit slice used to index the 4-element array
            // This eliminates the WIDTHTRUNC warning without changing behavior.
            lane_a_q    [fill_q[1:0]] <= a_data;  // store A element in this lane
            lane_b_q    [fill_q[1:0]] <= b_data;  // store B element in this lane
            lane_valid_q[fill_q[1:0]] <= 1'b1;    // mark this lane as valid
            fill_q                    <= fill_q + 3'd1; // advance to next lane slot

        end else if (state_q == REDUCE && reduce_step_q == LANES) begin
            // All lanes processed: clear lanes and fill counter for the next group
            fill_q <= 3'd0;
            for (int j = 0; j < LANES; j++) begin
                lane_valid_q[j] <= 1'b0; // clear validity so inactive lanes in next group start at 0
            end
        end
    end

    // ==========================================================================
    // ACCUMULATOR AND REDUCE STEP COUNTER
    // In REDUCE state: one lane product added to accumulator per cycle.
    // Explicit zero-extension of lane_prod to accumulator width eliminates WIDTHEXPAND.
    // ==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // On reset: clear accumulator and step counter
            accum_q       <= '0;
            reduce_step_q <= 3'd0;

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
    // BUG INTRODUCED: accumulator not reset on new command
    // Leftover sum from previous command corrupts next result
    reduce_step_q <= 3'd0;

        end else if (state_q == REDUCE) begin
            if (reduce_step_q < LANES[2:0]) begin
                // Only process valid lanes — inactive lanes (partial group) contribute nothing
                if (lane_valid_q[reduce_step_q[1:0]]) begin
                    // Explicit zero-extend lane_prod from 2*DATA_W to 2*DATA_W+4 bits
                    // This eliminates the WIDTHEXPAND warning cleanly.
                    accum_q <= accum_q + {{4{1'b0}}, lane_prod[reduce_step_q[1:0]]};
                end
            end
            // Advance to next lane every cycle in REDUCE state
            reduce_step_q <= reduce_step_q + 3'd1;

        end else begin
            // Outside REDUCE: hold step counter at zero ready for next group
            reduce_step_q <= 3'd0;
        end
    end

    // ==========================================================================
    // ELEMENT COUNTER
    // Counts accepted elements across all groups for the current command.
    // ==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            elem_count_q <= 8'd0; // reset on power-up

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
            elem_count_q <= 8'd0; // reset at start of every new command

        end else if (state_q == LOAD && in_valid && in_ready) begin
            elem_count_q <= elem_count_q + 8'd1; // one more element accepted
        end
    end

    // ==========================================================================
    // OUTPUT REGISTER
    // Captures final result when the last lane of the last group is processed.
    // Held stable in OUTPUT state regardless of backpressure on out_ready.
    // ==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_q  <= '0;  // clear result on reset
            tag_out_q <= '0;  // clear tag on reset

        end else if (state_q == REDUCE && reduce_step_q == LANES[2:0]) begin
            // All lanes processed for this group — check if this is the final group
            if (elem_count_q == length_q) begin
                result_q  <= accum_q; // latch the final accumulated sum
                tag_out_q <= tag_q;   // latch the command tag alongside the result
            end
        end
    end

    // ==========================================================================
    // COMMAND REGISTERS
    // Latched when a command handshake occurs (cmd_valid && cmd_ready).
    // ==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            length_q <= 8'd0; // clear on reset
            tag_q    <= 4'd0; // clear on reset

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
            length_q <= cmd_length; // save the requested vector length
            tag_q    <= cmd_tag;    // save the command tag
        end
    end

    // ==========================================================================
    // NEXT STATE LOGIC — combinational
    // Computes state_d (next state) based on current state and conditions.
    // state_q is updated from state_d on the next clock edge.
    // ==========================================================================
    always_comb begin
        state_d = state_q; // default: stay in current state

        case (state_q)

            IDLE: begin
                // Leave IDLE as soon as a command handshake completes
                if (cmd_valid && cmd_ready)
                    state_d = LOAD;
            end

            LOAD: begin
                // Move to REDUCE when:
                //   (a) all LANES slots are filled (full group), OR
                //   (b) the last element of the command has just been accepted (partial group)
                if (fill_q == LANES[2:0] || elem_count_q == length_q)
                    state_d = REDUCE;
            end

            REDUCE: begin
                // Move out of REDUCE after all lane steps are done (reduce_step_q reaches LANES)
                if (reduce_step_q == LANES[2:0]) begin
                    if (elem_count_q == length_q)
                        state_d = OUTPUT; // all elements consumed — result is ready
                    else
                        state_d = LOAD;   // more element groups remain — go load next group
                end
            end

            OUTPUT: begin
                // Leave OUTPUT only when downstream accepts the result
                if (out_valid && out_ready)
                    state_d = IDLE;
            end

            default: state_d = IDLE; // safety catch-all
        endcase
    end

    // ==========================================================================
    // STATE REGISTER — clocked update of state_q from state_d
    // ==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= IDLE; // reset to idle
        else        state_q <= state_d; // advance to next state
    end

    // ==========================================================================
    // OUTPUT ASSIGNMENTS — continuous assignments from internal registers to ports
    // ==========================================================================
    assign cmd_ready = (state_q == IDLE);    // accept commands only when idle
    assign in_ready  = (state_q == LOAD);    // accept elements only during LOAD
    assign out_valid = (state_q == OUTPUT);  // result valid only during OUTPUT
    assign result    = result_q;             // expose latched result to output port
    assign out_tag   = tag_out_q;            // expose latched tag to output port

endmodule