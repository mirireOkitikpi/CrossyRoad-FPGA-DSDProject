`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      lane_manager.v (v2 — log riding support)
// Description:
//   Procedurally generates and manages the Crossy Road lane map.
//   Now includes a combinational query interface so game_top can
//   look up direction and speed for the chicken's current lane
//   (needed for log-riding mechanics).
//
//   River lanes use wider logs (128px) placed at well-spaced intervals
//   to ensure the player can land on them and ride across.
//////////////////////////////////////////////////////////////////////////////////

module lane_manager (
    input             clk,
    input             rst,
    input             game_active,
    input      [10:0] world_y,

    // ── Lane type outputs (14 lanes) ──
    output reg [1:0]  lane_type_0,  lane_type_1,  lane_type_2,
    output reg [1:0]  lane_type_3,  lane_type_4,  lane_type_5,
    output reg [1:0]  lane_type_6,  lane_type_7,  lane_type_8,
    output reg [1:0]  lane_type_9,  lane_type_10, lane_type_11,
    output reg [1:0]  lane_type_12, lane_type_13,

    // ── Obstacle 1 X positions per lane ──
    output reg [10:0] obs_x_0,  obs_x_1,  obs_x_2,  obs_x_3,
    output reg [10:0] obs_x_4,  obs_x_5,  obs_x_6,  obs_x_7,
    output reg [10:0] obs_x_8,  obs_x_9,  obs_x_10, obs_x_11,
    output reg [10:0] obs_x_12, obs_x_13,

    // ── Obstacle 2 X positions per lane ──
    output reg [10:0] obs2_x_0,  obs2_x_1,  obs2_x_2,  obs2_x_3,
    output reg [10:0] obs2_x_4,  obs2_x_5,  obs2_x_6,  obs2_x_7,
    output reg [10:0] obs2_x_8,  obs2_x_9,  obs2_x_10, obs2_x_11,
    output reg [10:0] obs2_x_12, obs2_x_13,

    // ── Query interface: look up direction/speed for any lane ──
    input      [3:0]  query_lane,       // Lane index to query
    output reg        query_dir,        // 0=right, 1=left
    output reg [3:0]  query_speed       // Pixels per game tick
);

    localparam NUM_LANES    = 14;
    localparam SCREEN_WIDTH = 11'd1440;
    localparam LANE_GRASS   = 2'd0;
    localparam LANE_ROAD    = 2'd1;
    localparam LANE_RIVER   = 2'd2;
    localparam LANE_START   = 2'd3;

    // ──────────────────────────────────────────────────────────
    // Internal storage
    // ──────────────────────────────────────────────────────────
    reg [1:0]  lane_types  [0:NUM_LANES-1];
    reg [10:0] lane_obs_x  [0:NUM_LANES-1];
    reg [10:0] lane_obs2_x [0:NUM_LANES-1];
    reg        lane_dir    [0:NUM_LANES-1];
    reg [3:0]  lane_speed  [0:NUM_LANES-1];

    // ── 16-bit LFSR: x^16+x^14+x^13+x^11+1 ──
    reg [15:0] lfsr;
    wire lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    // ── Fairness counter ──
    reg [1:0] consecutive_danger;

    function [1:0] gen_lane_type;
        input [1:0] bits;
        input [1:0] consec;
        begin
            if (consec >= 2'd3)
                gen_lane_type = LANE_GRASS;
            else case (bits)
                2'b00: gen_lane_type = LANE_GRASS;
                2'b01: gen_lane_type = LANE_ROAD;
                2'b10: gen_lane_type = LANE_ROAD;
                2'b11: gen_lane_type = LANE_RIVER;
            endcase
        end
    endfunction

    // ── Scroll tracking ──
    reg [10:0] prev_world_y;
    wire world_scrolled = (world_y != prev_world_y) && game_active;

    integer i;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            lfsr <= 16'hACE1;
            consecutive_danger <= 2'd0;
            prev_world_y <= 11'd0;

            // Fixed starting layout
            lane_types[0]  <= LANE_START;
            lane_types[1]  <= LANE_GRASS;
            lane_types[2]  <= LANE_ROAD;
            lane_types[3]  <= LANE_ROAD;
            lane_types[4]  <= LANE_GRASS;
            lane_types[5]  <= LANE_RIVER;
            lane_types[6]  <= LANE_RIVER;
            lane_types[7]  <= LANE_GRASS;
            lane_types[8]  <= LANE_ROAD;
            lane_types[9]  <= LANE_ROAD;
            lane_types[10] <= LANE_ROAD;
            lane_types[11] <= LANE_GRASS;
            lane_types[12] <= LANE_RIVER;
            lane_types[13] <= LANE_GRASS;

            // Initialise obstacles/logs
            // River lanes (5, 6, 12): well-spaced logs
            // Road lanes: spread cars
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                lane_dir[i]   <= i[0];          // Alternate directions
                lane_speed[i] <= 4'd2 + i[1:0]; // Speed 2-5
            end

            // Road lane positions (spread across screen)
            lane_obs_x[0]  <= 11'd400;  lane_obs2_x[0]  <= 11'd1000;
            lane_obs_x[1]  <= 11'd200;  lane_obs2_x[1]  <= 11'd800;
            lane_obs_x[2]  <= 11'd100;  lane_obs2_x[2]  <= 11'd750;
            lane_obs_x[3]  <= 11'd500;  lane_obs2_x[3]  <= 11'd1100;
            lane_obs_x[4]  <= 11'd300;  lane_obs2_x[4]  <= 11'd900;

            // River lane logs — placed so there's always one on-screen
            // Logs are 128px wide, screen is 1440px
            // Place logs ~500px apart so one is always visible
            lane_obs_x[5]  <= 11'd100;  lane_obs2_x[5]  <= 11'd650;
            lane_speed[5]  <= 4'd2;  // Slow river
            lane_obs_x[6]  <= 11'd300;  lane_obs2_x[6]  <= 11'd850;
            lane_speed[6]  <= 4'd3;
            lane_obs_x[7]  <= 11'd200;  lane_obs2_x[7]  <= 11'd800;

            lane_obs_x[8]  <= 11'd150;  lane_obs2_x[8]  <= 11'd800;
            lane_obs_x[9]  <= 11'd400;  lane_obs2_x[9]  <= 11'd1050;
            lane_obs_x[10] <= 11'd50;   lane_obs2_x[10] <= 11'd700;
            lane_obs_x[11] <= 11'd250;  lane_obs2_x[11] <= 11'd850;

            lane_obs_x[12] <= 11'd200;  lane_obs2_x[12] <= 11'd750;
            lane_speed[12] <= 4'd2;  // Slow river
            lane_obs_x[13] <= 11'd350;  lane_obs2_x[13] <= 11'd950;

        end else begin
            prev_world_y <= world_y;

            // ── World scroll: discard bottom lane, shift everything down, new lane at top ──
            if (world_scrolled) begin
                // Shift all lanes DOWN by one (lane 13 = bottom is discarded)
                for (i = NUM_LANES - 1; i > 0; i = i - 1) begin
                    lane_types[i]   <= lane_types[i - 1];
                    lane_obs_x[i]   <= lane_obs_x[i - 1];
                    lane_obs2_x[i]  <= lane_obs2_x[i - 1];
                    lane_dir[i]     <= lane_dir[i - 1];
                    lane_speed[i]   <= lane_speed[i - 1];
                end

                // Generate new lane at position 0 (top of screen)
                lane_types[0] <= gen_lane_type(lfsr[1:0], consecutive_danger);

                if (gen_lane_type(lfsr[1:0], consecutive_danger) == LANE_GRASS ||
                    gen_lane_type(lfsr[1:0], consecutive_danger) == LANE_START)
                    consecutive_danger <= 2'd0;
                else
                    consecutive_danger <= consecutive_danger + 2'd1;

                // New lane obstacle positions
                // River: well-spaced logs; Road: random start positions
                if (gen_lane_type(lfsr[1:0], consecutive_danger) == LANE_RIVER) begin
                    lane_obs_x[0]  <= {4'd0, lfsr[6:0]} + 11'd50;
                    lane_obs2_x[0] <= {4'd0, lfsr[6:0]} + 11'd550;
                    lane_speed[0]  <= {2'b00, lfsr[9:8]} + 4'd2;
                end else begin
                    lane_obs_x[0]  <= {lfsr[10:0]};
                    lane_obs2_x[0] <= {lfsr[10:0]} + 11'd500;
                    lane_speed[0]  <= {1'b0, lfsr[14:12]} + 4'd2;
                end

                lane_dir[0] <= lfsr[11];

                // Advance LFSR
                lfsr <= {lfsr[14:0], lfsr_fb};
            end

            // ── Obstacle scrolling ──
            if (game_active) begin
                for (i = 0; i < NUM_LANES; i = i + 1) begin
                    if (lane_types[i] == LANE_ROAD || lane_types[i] == LANE_RIVER) begin
                        if (lane_dir[i] == 1'b0) begin
                            // Scroll right — wrap around
                            if (lane_obs_x[i] >= SCREEN_WIDTH)
                                lane_obs_x[i] <= 11'd0;
                            else
                                lane_obs_x[i] <= lane_obs_x[i] + {7'd0, lane_speed[i]};

                            if (lane_obs2_x[i] >= SCREEN_WIDTH)
                                lane_obs2_x[i] <= 11'd0;
                            else
                                lane_obs2_x[i] <= lane_obs2_x[i] + {7'd0, lane_speed[i]};
                        end else begin
                            // Scroll left — wrap around
                            if (lane_obs_x[i] > SCREEN_WIDTH)
                                lane_obs_x[i] <= SCREEN_WIDTH;
                            else if (lane_obs_x[i] < {7'd0, lane_speed[i]})
                                lane_obs_x[i] <= SCREEN_WIDTH;
                            else
                                lane_obs_x[i] <= lane_obs_x[i] - {7'd0, lane_speed[i]};

                            if (lane_obs2_x[i] > SCREEN_WIDTH)
                                lane_obs2_x[i] <= SCREEN_WIDTH;
                            else if (lane_obs2_x[i] < {7'd0, lane_speed[i]})
                                lane_obs2_x[i] <= SCREEN_WIDTH;
                            else
                                lane_obs2_x[i] <= lane_obs2_x[i] - {7'd0, lane_speed[i]};
                        end
                    end
                end
            end
        end
    end

    // ──────────────────────────────────────────────────────────
    // Query interface (combinational)
    // game_top uses this to get direction/speed for the chicken's lane
    // ──────────────────────────────────────────────────────────
    always @(*) begin
        case (query_lane)
            4'd0:  begin query_dir = lane_dir[0];  query_speed = lane_speed[0];  end
            4'd1:  begin query_dir = lane_dir[1];  query_speed = lane_speed[1];  end
            4'd2:  begin query_dir = lane_dir[2];  query_speed = lane_speed[2];  end
            4'd3:  begin query_dir = lane_dir[3];  query_speed = lane_speed[3];  end
            4'd4:  begin query_dir = lane_dir[4];  query_speed = lane_speed[4];  end
            4'd5:  begin query_dir = lane_dir[5];  query_speed = lane_speed[5];  end
            4'd6:  begin query_dir = lane_dir[6];  query_speed = lane_speed[6];  end
            4'd7:  begin query_dir = lane_dir[7];  query_speed = lane_speed[7];  end
            4'd8:  begin query_dir = lane_dir[8];  query_speed = lane_speed[8];  end
            4'd9:  begin query_dir = lane_dir[9];  query_speed = lane_speed[9];  end
            4'd10: begin query_dir = lane_dir[10]; query_speed = lane_speed[10]; end
            4'd11: begin query_dir = lane_dir[11]; query_speed = lane_speed[11]; end
            4'd12: begin query_dir = lane_dir[12]; query_speed = lane_speed[12]; end
            4'd13: begin query_dir = lane_dir[13]; query_speed = lane_speed[13]; end
            default: begin query_dir = 1'b0; query_speed = 4'd0; end
        endcase
    end

    // ──────────────────────────────────────────────────────────
    // Output fan-out
    // ──────────────────────────────────────────────────────────
    always @(*) begin
        lane_type_0  = lane_types[0];   lane_type_1  = lane_types[1];
        lane_type_2  = lane_types[2];   lane_type_3  = lane_types[3];
        lane_type_4  = lane_types[4];   lane_type_5  = lane_types[5];
        lane_type_6  = lane_types[6];   lane_type_7  = lane_types[7];
        lane_type_8  = lane_types[8];   lane_type_9  = lane_types[9];
        lane_type_10 = lane_types[10];  lane_type_11 = lane_types[11];
        lane_type_12 = lane_types[12];  lane_type_13 = lane_types[13];

        obs_x_0  = lane_obs_x[0];   obs_x_1  = lane_obs_x[1];
        obs_x_2  = lane_obs_x[2];   obs_x_3  = lane_obs_x[3];
        obs_x_4  = lane_obs_x[4];   obs_x_5  = lane_obs_x[5];
        obs_x_6  = lane_obs_x[6];   obs_x_7  = lane_obs_x[7];
        obs_x_8  = lane_obs_x[8];   obs_x_9  = lane_obs_x[9];
        obs_x_10 = lane_obs_x[10];  obs_x_11 = lane_obs_x[11];
        obs_x_12 = lane_obs_x[12];  obs_x_13 = lane_obs_x[13];

        obs2_x_0  = lane_obs2_x[0];   obs2_x_1  = lane_obs2_x[1];
        obs2_x_2  = lane_obs2_x[2];   obs2_x_3  = lane_obs2_x[3];
        obs2_x_4  = lane_obs2_x[4];   obs2_x_5  = lane_obs2_x[5];
        obs2_x_6  = lane_obs2_x[6];   obs2_x_7  = lane_obs2_x[7];
        obs2_x_8  = lane_obs2_x[8];   obs2_x_9  = lane_obs2_x[9];
        obs2_x_10 = lane_obs2_x[10];  obs2_x_11 = lane_obs2_x[11];
        obs2_x_12 = lane_obs2_x[12];  obs2_x_13 = lane_obs2_x[13];
    end

endmodule
