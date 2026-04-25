`timescale 1ns / 1ps
// Module: lane_manager.v
// Purpose: Manages the six visible game lanes — their types, scroll positions,
//          and per-lane obstacle X coordinates. When the player advances far
//          enough to trigger a world scroll, the lane array shifts by one
//          position (oldest lane drops off the bottom, a new procedurally
//          generated lane enters at the top) and obstacle positions are
//          re-initialised from the LFSR output.
//
// Obstacle coordinates are signed 12-bit to allow smooth off-screen entry and
// exit. SCREEN_LEFT = -200 gives a full 192-px log time to enter before its
// left edge becomes visible; SCREEN_RIGHT = 1440 is the right wrap boundary.
//
// LFSR-based procedural generation:
//   A 16-bit Fibonacci LFSR with taps at positions 16, 14, 13, 11 (standard
//   maximal-length polynomial, period = 2^16 - 1 = 65,535) provides the
//   pseudo-random bits used to select lane type, obstacle X, speed, direction.
//
// Safety constraint: gen_lane_type caps consecutive dangerous lanes at three
//   in a row and blocks river-after-chasm and chasm-after-river/chasm sequences
//   to keep the layout completable.
//
// Reset vs game_reset_pulse:
//   !rst              — asynchronous hardware reset; also resets the LFSR seed.
//   game_reset_pulse  — synchronous soft-reset on restart; preserves LFSR state
//                       so each play-through generates different content.

module lane_manager (
    input             clk,
    input             rst,
    input             game_reset_pulse,  // One-cycle pulse on game start/restart
    input             game_active,
    input      [10:0] logical_world_y,   // Incremented by player_ctrl on each forward hop

    output reg [2:0]  lane_type_0,  lane_type_1,  lane_type_2,
    output reg [2:0]  lane_type_3,  lane_type_4,  lane_type_5,

    // Signed 12-bit obstacle X positions allow smooth off-screen entry/exit
    // without unsigned wrap-around artefacts in drawcon's bounding-box tests.
    output reg signed [11:0] obs_x_0,  obs_x_1,  obs_x_2,  obs_x_3,  obs_x_4,  obs_x_5,
    output reg signed [11:0] obs2_x_0, obs2_x_1, obs2_x_2, obs2_x_3, obs2_x_4, obs2_x_5,

    input      [3:0]  query_lane,   // Index for log-riding speed/direction query from game_top
    output reg        query_dir,
    output reg [3:0]  query_speed,

    output            lane_dir_0, lane_dir_1, lane_dir_2,
    output            lane_dir_3, lane_dir_4, lane_dir_5,

    output reg        grass_spawn_pulse, // One-cycle pulse when a grass lane enters (triggers goose spawn)
    output reg [10:0] new_lane_y,        // Y coordinate of the incoming lane for goose spawn
    output     [15:0] prng_val           // Exposed LFSR state consumed by goose_manager
);

    localparam NUM_LANES = 6;

    // Signed screen boundaries for obstacle scrolling.
    // SCREEN_LEFT = -200 is wide enough to fully hide a 192-px log before
    // it wraps back to SCREEN_RIGHT, preventing a visible pop-in artefact.
    localparam signed [11:0] SCREEN_RIGHT = 12'sd1440;
    localparam signed [11:0] SCREEN_LEFT  = -12'sd200;

    localparam LANE_GRASS = 3'd0;
    localparam LANE_ROAD  = 3'd1;
    localparam LANE_RIVER = 3'd2;
    localparam LANE_START = 3'd3; // Safe starting lane, rendered identically to grass
    localparam LANE_CHASM = 3'd4;

    // Internal lane state arrays (unpacked registers, not inferred as BRAM)
    reg [2:0]  lane_types  [0:NUM_LANES-1];
    reg signed [11:0] lane_obs_x  [0:NUM_LANES-1]; // Obstacle 1 X position
    reg signed [11:0] lane_obs2_x [0:NUM_LANES-1]; // Obstacle 2 X position
    reg        lane_dir    [0:NUM_LANES-1]; // 0 = left-to-right, 1 = right-to-left
    reg [3:0]  lane_speed  [0:NUM_LANES-1]; // Pixels per game tick

    // 16-bit Fibonacci LFSR
    // Feedback polynomial: x^16 + x^14 + x^13 + x^11 + 1 (taps 16,14,13,11).
    // Maximal-length: period 65,535 before repeating.
    // Advances every clock tick regardless of game_active so the first game
    // is not always identical to a prior session.
    reg [15:0] lfsr;
    wire lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    assign prng_val = lfsr;

    reg [1:0] consecutive_danger; // Counts consecutive non-grass lanes (capped at 3)

    // gen_lane_type: weighted LFSR-to-lane-type mapping with safety rules.
    // The 3 LFSR input bits give 8 equally likely values mapped as:
    //   00x → GRASS  (2/8)
    //   01x → ROAD   (2/8)
    //   10x → RIVER  (2/8, blocked after CHASM)
    //   11x → CHASM  (2/8, blocked after RIVER or CHASM)
    // If three consecutive danger lanes have already appeared, GRASS is forced
    // regardless of the LFSR output to guarantee a safe gap.
    function [2:0] gen_lane_type;
        input [2:0] bits;
        input [1:0] consec;    // Current consecutive danger count
        input [2:0] prev_lane; // Most recently generated lane type
        begin
            if (consec >= 2'd3)
                gen_lane_type = LANE_GRASS; // Safety cap — force a rest lane
            else case (bits)
                3'b000, 3'b001: gen_lane_type = LANE_GRASS;
                3'b010, 3'b011: gen_lane_type = LANE_ROAD;
                3'b100, 3'b101: begin
                    // Disallow river immediately after chasm
                    if (prev_lane == LANE_CHASM) gen_lane_type = LANE_GRASS;
                    else                         gen_lane_type = LANE_RIVER;
                end
                3'b110, 3'b111: begin
                    // Disallow chasm after river or consecutive chasms
                    if (prev_lane == LANE_RIVER || prev_lane == LANE_CHASM)
                                                 gen_lane_type = LANE_GRASS;
                    else                         gen_lane_type = LANE_CHASM;
                end
            endcase
        end
    endfunction

    // World scroll detection
    // logical_world_y is incremented by 128 by player_ctrl on each forward hop.
    // world_scrolled fires for one tick when the value changes while game_active,
    // triggering the lane-shift pipeline below.
    reg [10:0] prev_world_y;
    wire world_scrolled = (logical_world_y != prev_world_y) && game_active;

    // Pre-compute the type for the lane entering at index 0
    wire [2:0] new_type = gen_lane_type(lfsr[2:0], consecutive_danger, lane_types[0]);

    integer i;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // Hardware reset: initialise LFSR and default lane layout.
            lfsr               <= 16'hACE1; // Non-zero seed (all-zero LFSR is degenerate)
            consecutive_danger <= 2'd0;
            prev_world_y       <= 11'd0;
            grass_spawn_pulse  <= 1'b0;
            new_lane_y         <= 11'd0;

            // Default layout: START (safe) at index 0, then GRASS/ROAD/RIVER/ROAD/GRASS
            lane_types[0] <= LANE_START;
            lane_types[1] <= LANE_GRASS;
            lane_types[2] <= LANE_ROAD;
            lane_types[3] <= LANE_RIVER;
            lane_types[4] <= LANE_ROAD;
            lane_types[5] <= LANE_GRASS;

            for (i = 0; i < NUM_LANES; i = i + 1) begin
                lane_dir[i]    <= i[0];           // Alternate directions per lane
                lane_speed[i]  <= 4'd2 + i[1:0];  // Graduated starting speeds
                lane_obs_x[i]  <= 12'sd2000;      // Off-screen — not visible on first frame
                lane_obs2_x[i] <= 12'sd2000;
            end

            // Preset obstacle positions for initially active lanes so traffic
            // is visible immediately without waiting for the first scroll.
            lane_obs_x[2] <= 12'sd100;  lane_obs2_x[2] <= 12'sd750;
            lane_obs_x[3] <= 12'sd100;  lane_obs2_x[3] <= 12'sd650;
            lane_obs_x[4] <= 12'sd300;  lane_obs2_x[4] <= 12'sd900;
            lane_speed[3]  <= 4'd2;

        end else if (game_reset_pulse) begin
            // Soft reset on restart: mirrors !rst but preserves LFSR so each
            // game generates different procedural content.
            // prev_world_y is zeroed to prevent world_scrolled firing spuriously
            // on the first tick of the new game.
            consecutive_danger <= 2'd0;
            prev_world_y       <= 11'd0;
            grass_spawn_pulse  <= 1'b0;
            new_lane_y         <= 11'd0;

            lane_types[0] <= LANE_START;
            lane_types[1] <= LANE_GRASS;
            lane_types[2] <= LANE_ROAD;
            lane_types[3] <= LANE_RIVER;
            lane_types[4] <= LANE_ROAD;
            lane_types[5] <= LANE_GRASS;

            for (i = 0; i < NUM_LANES; i = i + 1) begin
                lane_dir[i]    <= i[0];
                lane_speed[i]  <= 4'd2 + i[1:0];
                lane_obs_x[i]  <= 12'sd2000;
                lane_obs2_x[i] <= 12'sd2000;
            end

            lane_obs_x[2] <= 12'sd100;  lane_obs2_x[2] <= 12'sd750;
            lane_obs_x[3] <= 12'sd100;  lane_obs2_x[3] <= 12'sd650;
            lane_obs_x[4] <= 12'sd300;  lane_obs2_x[4] <= 12'sd900;
            lane_speed[3]  <= 4'd2;

        end else begin
            // LFSR advances unconditionally to prevent game 1 always being identical
            if (lfsr == 16'd0) lfsr <= 16'hACE1; // Escape the all-zero lock-up state
            else               lfsr <= {lfsr[14:0], lfsr_fb};

            if (world_scrolled) begin
                // Update scroll cursor so world_scrolled does not re-fire
                prev_world_y <= prev_world_y + 11'd128;

                // Signal goose_manager to attempt a spawn if a grass lane is entering
                if (new_type == LANE_GRASS) begin
                    grass_spawn_pulse <= 1'b1;
                    new_lane_y        <= logical_world_y - (11'd128 * 3);
                end else begin
                    grass_spawn_pulse <= 1'b0;
                end

                // Shift the lane array down: lane[i] = lane[i-1], i running high-to-low.
                // This inserts new_type at index 0 (top of visible area) and discards
                // lane[NUM_LANES-1] (bottom of visible area).
                for (i = NUM_LANES - 1; i > 0; i = i - 1) begin
                    lane_types[i]  <= lane_types[i-1];
                    lane_obs_x[i]  <= lane_obs_x[i-1];
                    lane_obs2_x[i] <= lane_obs2_x[i-1];
                    lane_dir[i]    <= lane_dir[i-1];
                    lane_speed[i]  <= lane_speed[i-1];
                end

                lane_types[0] <= new_type;

                // Update consecutive danger counter
                if (new_type == LANE_GRASS || new_type == LANE_START)
                    consecutive_danger <= 2'd0;
                else
                    consecutive_danger <= consecutive_danger + 2'd1;

                // Initialise obstacle positions for the incoming lane from LFSR bits.
                // River logs get a minimum 500-px gap and a lower starting X so at
                // least one log is reachable from spawn. Road cars use a wider range.
                if (new_type == LANE_RIVER) begin
                    lane_obs_x[0]  <= {5'd0, lfsr[6:0]} + 12'sd50;   // [50, 177]
                    lane_obs2_x[0] <= {5'd0, lfsr[6:0]} + 12'sd550;  // [550, 677]
                    lane_speed[0]  <= {2'b00, lfsr[9:8]} + 4'd2;     // [2, 5] px/tick
                end else begin
                    lane_obs_x[0]  <= {2'b00, lfsr[9:0]};            // [0, 1023]
                    lane_obs2_x[0] <= {2'b00, lfsr[9:0]} + 12'sd500; // [500, 1523]
                    lane_speed[0]  <= {1'b0, lfsr[14:12]} + 4'd2;    // [2, 9] px/tick
                end
                lane_dir[0] <= lfsr[11]; // Random direction from LFSR bit 11

            end else if (game_active) begin
                // Per-tick obstacle scrolling — no lane shift this tick
                grass_spawn_pulse <= 1'b0;

                for (i = 0; i < NUM_LANES; i = i + 1) begin
                    if (lane_types[i] == LANE_ROAD || lane_types[i] == LANE_RIVER) begin

                        // Signed wrap: obstacles move in lane_dir direction.
                        // dir=0: left-to-right; wraps from SCREEN_RIGHT back to SCREEN_LEFT.
                        // dir=1: right-to-left; wraps from SCREEN_LEFT back to SCREEN_RIGHT.
                        // Using signed arithmetic and negative SCREEN_LEFT allows the full
                        // 192-px log width to exit before reappearing, avoiding visible pops.
                        if (lane_dir[i] == 1'b0) begin
                            if (lane_obs_x[i] >= SCREEN_RIGHT)  lane_obs_x[i]  <= SCREEN_LEFT;
                            else                                 lane_obs_x[i]  <= lane_obs_x[i]  + $signed({8'd0, lane_speed[i]});

                            if (lane_obs2_x[i] >= SCREEN_RIGHT) lane_obs2_x[i] <= SCREEN_LEFT;
                            else                                 lane_obs2_x[i] <= lane_obs2_x[i] + $signed({8'd0, lane_speed[i]});
                        end else begin
                            if (lane_obs_x[i] <= SCREEN_LEFT)   lane_obs_x[i]  <= SCREEN_RIGHT;
                            else                                 lane_obs_x[i]  <= lane_obs_x[i]  - $signed({8'd0, lane_speed[i]});

                            if (lane_obs2_x[i] <= SCREEN_LEFT)  lane_obs2_x[i] <= SCREEN_RIGHT;
                            else                                 lane_obs2_x[i] <= lane_obs2_x[i] - $signed({8'd0, lane_speed[i]});
                        end
                    end
                end
            end
        end
    end

    // Query interface for log-riding (used by player_ctrl via game_top)
    // Returns direction and speed for whatever lane index game_top requests.
    always @(*) begin
        case (query_lane)
            4'd0:    begin query_dir = lane_dir[0]; query_speed = lane_speed[0]; end
            4'd1:    begin query_dir = lane_dir[1]; query_speed = lane_speed[1]; end
            4'd2:    begin query_dir = lane_dir[2]; query_speed = lane_speed[2]; end
            4'd3:    begin query_dir = lane_dir[3]; query_speed = lane_speed[3]; end
            4'd4:    begin query_dir = lane_dir[4]; query_speed = lane_speed[4]; end
            4'd5:    begin query_dir = lane_dir[5]; query_speed = lane_speed[5]; end
            default: begin query_dir = 1'b0;        query_speed = 4'd0;          end
        endcase
    end

    // Flatten internal arrays to flat output ports
    // Verilog-2001 does not allow array ports, so each lane is driven individually.
    always @(*) begin
        lane_type_0 = lane_types[0]; lane_type_1 = lane_types[1];
        lane_type_2 = lane_types[2]; lane_type_3 = lane_types[3];
        lane_type_4 = lane_types[4]; lane_type_5 = lane_types[5];

        obs_x_0  = lane_obs_x[0];  obs_x_1  = lane_obs_x[1];
        obs_x_2  = lane_obs_x[2];  obs_x_3  = lane_obs_x[3];
        obs_x_4  = lane_obs_x[4];  obs_x_5  = lane_obs_x[5];

        obs2_x_0 = lane_obs2_x[0]; obs2_x_1 = lane_obs2_x[1];
        obs2_x_2 = lane_obs2_x[2]; obs2_x_3 = lane_obs2_x[3];
        obs2_x_4 = lane_obs2_x[4]; obs2_x_5 = lane_obs2_x[5];
    end

    assign lane_dir_0 = lane_dir[0]; assign lane_dir_1 = lane_dir[1];
    assign lane_dir_2 = lane_dir[2]; assign lane_dir_3 = lane_dir[3];
    assign lane_dir_4 = lane_dir[4]; assign lane_dir_5 = lane_dir[5];

endmodule
