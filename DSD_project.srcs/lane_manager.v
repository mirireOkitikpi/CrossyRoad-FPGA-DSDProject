`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      lane_manager.v  (patched)
//
// Fix vs previous revision:
//   - Added game_reset_pulse input. On a pulse, the 6-lane array is reloaded
//     to the start-of-game configuration (START/GRASS/ROAD/RIVER/ROAD/GRASS),
//     obstacle positions are reset to their initial offsets, and prev_world_y
//     is zeroed so the next tick does not spuriously trigger world_scrolled.
//   - This means restart picks up a clean, collision-free layout instead of
//     whatever dangerous lane happened to be at chk_lane=5 at the moment of
//     death.
//////////////////////////////////////////////////////////////////////////////////

module lane_manager (
    input             clk,
    input             rst,
    input             game_reset_pulse,   // NEW - synchronous state reload
    input             game_active,
    input      [10:0] logical_world_y,
    output reg [2:0]  lane_type_0,  lane_type_1,  lane_type_2,
    output reg [2:0]  lane_type_3,  lane_type_4,  lane_type_5,
    output reg [10:0] obs_x_0,  obs_x_1,  obs_x_2,  obs_x_3,  obs_x_4,  obs_x_5,
    output reg [10:0] obs2_x_0, obs2_x_1, obs2_x_2, obs2_x_3, obs2_x_4, obs2_x_5,
    input      [3:0]  query_lane,
    output reg        query_dir,
    output reg [3:0]  query_speed,
    output            lane_dir_0, lane_dir_1, lane_dir_2,
    output            lane_dir_3, lane_dir_4, lane_dir_5,
    output reg        grass_spawn_pulse,
    output reg [10:0] new_lane_y,
    output     [15:0] prng_val
);

    localparam NUM_LANES    = 6;
    localparam SCREEN_WIDTH = 11'd1440;
    localparam LANE_GRASS   = 3'd0;
    localparam LANE_ROAD    = 3'd1;
    localparam LANE_RIVER   = 3'd2;
    localparam LANE_START   = 3'd3;
    localparam LANE_CHASM   = 3'd4;

    reg [2:0]  lane_types  [0:NUM_LANES-1];
    reg [10:0] lane_obs_x  [0:NUM_LANES-1];
    reg [10:0] lane_obs2_x [0:NUM_LANES-1];
    reg        lane_dir    [0:NUM_LANES-1];
    reg [3:0]  lane_speed  [0:NUM_LANES-1];

    // 16-bit Fibonacci LFSR, taps at 16/14/13/11 (standard maximal-length
    // polynomial for pseudo-random lane/obstacle generation).
    reg [15:0] lfsr;
    wire lfsr_fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    assign prng_val = lfsr;

    reg [1:0] consecutive_danger;

    function [2:0] gen_lane_type;
        input [2:0] bits;
        input [1:0] consec;
        input [2:0] prev_lane;
        begin
            if (consec >= 2'd3)
                gen_lane_type = LANE_GRASS;
            else case (bits)
                3'b000, 3'b001: gen_lane_type = LANE_GRASS;
                3'b010, 3'b011: gen_lane_type = LANE_ROAD;
                3'b100, 3'b101: begin
                    if (prev_lane == LANE_CHASM) gen_lane_type = LANE_GRASS;
                    else                         gen_lane_type = LANE_RIVER;
                end
                3'b110, 3'b111: begin
                    if (prev_lane == LANE_RIVER || prev_lane == LANE_CHASM)
                                                 gen_lane_type = LANE_GRASS;
                    else                         gen_lane_type = LANE_CHASM;
                end
            endcase
        end
    endfunction

    reg [10:0] prev_world_y;
    wire world_scrolled = (logical_world_y != prev_world_y) && game_active;

    wire [2:0] new_type = gen_lane_type(lfsr[2:0], consecutive_danger, lane_types[0]);

    integer i;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            lfsr               <= 16'hACE1;
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
                lane_obs_x[i]  <= 11'd2000;
                lane_obs2_x[i] <= 11'd2000;
            end

            lane_obs_x[2] <= 11'd100;  lane_obs2_x[2] <= 11'd750;
            lane_obs_x[3] <= 11'd100;  lane_obs2_x[3] <= 11'd650;
            lane_obs_x[4] <= 11'd300;  lane_obs2_x[4] <= 11'd900;
            lane_speed[3] <= 4'd2;
        end else if (game_reset_pulse) begin
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
                lane_obs_x[i]  <= 11'd2000;
                lane_obs2_x[i] <= 11'd2000;
            end

            lane_obs_x[2] <= 11'd100;  lane_obs2_x[2] <= 11'd750;
            lane_obs_x[3] <= 11'd100;  lane_obs2_x[3] <= 11'd650;
            lane_obs_x[4] <= 11'd300;  lane_obs2_x[4] <= 11'd900;
            lane_speed[3] <= 4'd2;
        end else begin
            // Normal operation. LFSR advances every tick regardless of
            // game_active so the first game isn't deterministic.
            if (lfsr == 16'd0) lfsr <= 16'hACE1;
            else               lfsr <= {lfsr[14:0], lfsr_fb};

            if (world_scrolled) begin
                prev_world_y <= prev_world_y + 11'd128;

                if (new_type == LANE_GRASS) begin
                    grass_spawn_pulse <= 1'b1;
                    new_lane_y        <= logical_world_y - (11'd128 * 3);
                end else begin
                    grass_spawn_pulse <= 1'b0;
                end

                for (i = NUM_LANES - 1; i > 0; i = i - 1) begin
                    lane_types[i]  <= lane_types[i-1];
                    lane_obs_x[i]  <= lane_obs_x[i-1];
                    lane_obs2_x[i] <= lane_obs2_x[i-1];
                    lane_dir[i]    <= lane_dir[i-1];
                    lane_speed[i]  <= lane_speed[i-1];
                end

                lane_types[0] <= new_type;

                if (new_type == LANE_GRASS || new_type == LANE_START)
                    consecutive_danger <= 2'd0;
                else
                    consecutive_danger <= consecutive_danger + 2'd1;

                if (new_type == LANE_RIVER) begin
                    lane_obs_x[0]  <= {4'd0, lfsr[6:0]} + 11'd50;
                    lane_obs2_x[0] <= {4'd0, lfsr[6:0]} + 11'd550;
                    lane_speed[0]  <= {2'b00, lfsr[9:8]} + 4'd2;
                end else begin
                    lane_obs_x[0]  <= {1'b0, lfsr[9:0]};
                    lane_obs2_x[0] <= {1'b0, lfsr[9:0]} + 11'd500;
                    lane_speed[0]  <= {1'b0, lfsr[14:12]} + 4'd2;
                end
                lane_dir[0] <= lfsr[11];
            end else if (game_active) begin
                grass_spawn_pulse <= 1'b0;

                for (i = 0; i < NUM_LANES; i = i + 1) begin
                    if (lane_types[i] == LANE_ROAD || lane_types[i] == LANE_RIVER) begin
                        if (lane_dir[i] == 1'b0) begin
                            if (lane_obs_x[i] >= SCREEN_WIDTH)  lane_obs_x[i]  <= 11'd0;
                            else                                lane_obs_x[i]  <= lane_obs_x[i]  + {7'd0, lane_speed[i]};
                            if (lane_obs2_x[i] >= SCREEN_WIDTH) lane_obs2_x[i] <= 11'd0;
                            else                                lane_obs2_x[i] <= lane_obs2_x[i] + {7'd0, lane_speed[i]};
                        end else begin
                            if (lane_obs_x[i]  > SCREEN_WIDTH)               lane_obs_x[i]  <= SCREEN_WIDTH;
                            else if (lane_obs_x[i]  < {7'd0, lane_speed[i]}) lane_obs_x[i]  <= SCREEN_WIDTH;
                            else                                              lane_obs_x[i]  <= lane_obs_x[i]  - {7'd0, lane_speed[i]};
                            if (lane_obs2_x[i] > SCREEN_WIDTH)               lane_obs2_x[i] <= SCREEN_WIDTH;
                            else if (lane_obs2_x[i] < {7'd0, lane_speed[i]}) lane_obs2_x[i] <= SCREEN_WIDTH;
                            else                                              lane_obs2_x[i] <= lane_obs2_x[i] - {7'd0, lane_speed[i]};
                        end
                    end
                end
            end
        end
    end

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
