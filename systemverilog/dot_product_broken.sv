// Vector Dot-Product Accelerator
// Uses 4 parallel multiply lanes with a shared accumulator
// Handles backpressure on both input and output with ready/valid signals
// Cleaned up to avoid SystemVerilog width warnings

module dot_product #(
    parameter DATA_W  = 8,    // element width (8 bits for A and B)
    parameter LANES   = 4,    // how many lanes to compute in parallel
    parameter MAX_LEN = 16    // max vector length we can handle
) (
    input  logic                  clk,        // clock
    input  logic                  rst_n,      // reset (active low)

    // Command interface
    input  logic                  cmd_valid,  // caller: "I have a command"
    output logic                  cmd_ready,  // chip: "Ready to accept command"
    input  logic [7:0]            cmd_length, // number of pairs to process
    input  logic [3:0]            cmd_tag,    // tag to match result with this command

    // Input stream interface (one pair per cycle)
    input  logic                  in_valid,   // caller: "element pair is ready"
    output logic                  in_ready,   // chip: "I can accept the element"
    input  logic [DATA_W-1:0]     a_data,     // first element
    input  logic [DATA_W-1:0]     b_data,     // second element

    // Output interface
    output logic                  out_valid,       // chip: "Result is ready"
    input  logic                  out_ready,       // caller: "I'm ready to accept"
    output logic [2*DATA_W+3:0]   result,          // the final sum
    output logic [3:0]            out_tag          // tag from the command
);

    // State machine: IDLE -> LOAD -> REDUCE -> OUTPUT -> IDLE
    typedef enum logic [1:0] {
        IDLE   = 2'b00,   // wait for command
        LOAD   = 2'b01,   // fill the lanes with elements
        REDUCE = 2'b10,   // sum up the products
        OUTPUT = 2'b11    // send result
    } state_t;

    state_t state_q;   // what state we're in now
    state_t state_d;   // what state comes next

    // Remember the command details
    logic [7:0] length_q;   // how many pairs for this command
    logic [3:0] tag_q;      // command tag (sent back with result)

    // Track how many elements we've seen so far
    logic [7:0] elem_count_q;   // count of accepted elements

    // Storage for the 4 parallel lanes
    logic [DATA_W-1:0] lane_a_q   [LANES];   // store A elements
    logic [DATA_W-1:0] lane_b_q   [LANES];   // store B elements
    logic              lane_valid_q[LANES];   // which lanes have data

    // Multiply results (computed every cycle)
    logic [2*DATA_W-1:0] lane_prod[LANES];   // all 4 products in parallel

    // Running sum (wide enough for 16 products)
    logic [2*DATA_W+3:0] accum_q;   // accumulator

    // Final result and tag (held until downstream reads it)
    logic [2*DATA_W+3:0] result_q;    // final answer
    logic [3:0]          tag_out_q;   // result tag

    // Track which lane to fill next (0-3)
    logic [2:0] fill_q;   // which lane slot to fill next

    // Track which lane we're summing right now
    logic [2:0] reduce_step_q;   // which lane product to add next

    // Create 4 multipliers (all work at once)
    genvar i;
    generate
        for (i = 0; i < LANES; i++) begin : lane_mult
            assign lane_prod[i] = lane_a_q[i] * lane_b_q[i];  // multiply in parallel
        end
    endgenerate

    // Store incoming elements into lane registers (LOAD state)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_q <= 3'd0;
            for (int j = 0; j < LANES; j++) begin
                lane_a_q[j]      <= '0;
                lane_b_q[j]      <= '0;
                lane_valid_q[j]  <= 1'b0;
            end

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
            fill_q <= 3'd0;
            for (int j = 0; j < LANES; j++) begin
                lane_valid_q[j] <= 1'b0;
            end

        end else if (state_q == LOAD && in_valid && in_ready) begin
            lane_a_q    [fill_q[1:0]] <= a_data;
            lane_b_q    [fill_q[1:0]] <= b_data;
            lane_valid_q[fill_q[1:0]] <= 1'b1;
            fill_q                    <= fill_q + 3'd1;

        end else if (state_q == REDUCE && reduce_step_q == LANES) begin
            fill_q <= 3'd0;
            for (int j = 0; j < LANES; j++) begin
                lane_valid_q[j] <= 1'b0;
            end
        end
    end

    // Sum up the products (REDUCE state)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_q       <= '0;
            reduce_step_q <= 3'd0;

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
            accum_q       <= '0;
            reduce_step_q <= 3'd0;

        end else if (state_q == REDUCE) begin
            if (reduce_step_q < LANES[2:0]) begin
                if (lane_valid_q[reduce_step_q[1:0]]) begin
                    accum_q <= accum_q + {{4{1'b0}}, lane_prod[reduce_step_q[1:0]]};
                end
            end
            reduce_step_q <= reduce_step_q + 3'd1;

        end else begin
            reduce_step_q <= 3'd0;
        end
    end

    // ==========================================================================
    // ELEMENT COUNTER
    // Counts accepted elements across all groups for the current command.
    // ==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            elem_count_q <= 8'd0;

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
            elem_count_q <= 8'd0;

        end else if (state_q == LOAD && in_valid && in_ready) begin
            elem_count_q <= elem_count_q + 8'd1;
        end
    end

    // Latch the result when done
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_q  <= '0;
            tag_out_q <= '0;

        end else if (state_q == REDUCE && reduce_step_q == LANES[2:0]) begin
            if (elem_count_q == length_q) begin
                result_q  <= accum_q;
                tag_out_q <= tag_q;
            end
        end
    end

    // Store command details
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            length_q <= 8'd0;
            tag_q    <= 4'd0;

        end else if (state_q == IDLE && cmd_valid && cmd_ready) begin
            length_q <= cmd_length;
            tag_q    <= cmd_tag;
        end
    end

    // Determine next state
    always_comb begin
        state_d = state_q;  // default: stay

        case (state_q)
            IDLE: begin
                if (cmd_valid && cmd_ready)
                    state_d = LOAD;
            end

            LOAD: begin
                // Go to REDUCE when all lanes full or we've got all elements
                if (fill_q == LANES[2:0] || elem_count_q == length_q)
                    state_d = REDUCE;
            end

            REDUCE: begin
                // Done with this group of lanes
                if (reduce_step_q == LANES[2:0]) begin
                    if (elem_count_q == length_q)
                        state_d = OUTPUT;  // we're done
                    else
                        state_d = LOAD;    // more elements to process
                end
            end

            OUTPUT: begin
                // Send result when accepted
                if (out_valid && out_ready)
                    state_d = IDLE;
            end

            default: state_d = IDLE;
        endcase
    end

    // Update state on clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= IDLE;
        else        state_q <= state_d;
    end

    // Connect internal signals to ports
    assign cmd_ready = (state_q == IDLE);    // ready for commands when idle
    assign in_ready  = (state_q == LOAD);    // ready for input during LOAD
    assign out_valid = (state_q == OUTPUT);  // result valid during OUTPUT
    assign result    = result_q;
    assign out_tag   = tag_out_q;

endmodule