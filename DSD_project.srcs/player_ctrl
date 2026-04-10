`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      player_ctrl.v (v2 — log riding support)
// Description:
//   Controls chicken movement with discrete hops.
//   Now accepts log_carry_en and log_carry_right/speed inputs from
//   game_top. When the chicken is on a river lane standing on a log,
//   its X position is shifted each game tick to match the log's
//   scrolling direction and speed. If carried off-screen, signals
//   carried_offscreen for game_top to trigger death.
//////////////////////////////////////////////////////////////////////////////////

module player_ctrl (
    input             clk,
    input             rst,
    input             btn_up,
    input             btn_down,
    input             btn_left,
    input             btn_right,
    input             game_active,

    // ── Log riding inputs (from game_top) ──
    input             log_carry_en,     // High when on a log
    input             log_carry_right,  // 1=carry right, 0=carry left
    input      [3:0]  log_carry_speed,  // Pixels per tick to carry

    output reg [10:0] chicken_x,
    output reg [10:0] chicken_y,
    output reg [10:0] world_y,
    output reg [1:0]  facing,
    output reg        is_moving,
    output            carried_offscreen  // High if log carried us off edge
);

    localparam LANE_HEIGHT    = 11'd57;
    localparam HOP_X          = 11'd32;
    localparam CHICKEN_SIZE   = 11'd32;
    localparam SCREEN_LEFT    = 11'd4;
    localparam SCREEN_RIGHT   = 11'd1404;
    localparam GAME_TOP       = 11'd104;
    localparam GAME_BOTTOM    = 11'd864;
    localparam SCROLL_THRESH  = 11'd300;
    localparam START_X        = 11'd704;
    localparam START_Y        = GAME_BOTTOM;

    localparam FACE_UP    = 2'd0;
    localparam FACE_DOWN  = 2'd1;
    localparam FACE_LEFT  = 2'd2;
    localparam FACE_RIGHT = 2'd3;

    // Edge detection
    reg btn_up_prev, btn_down_prev, btn_left_prev, btn_right_prev;
    wire btn_up_rise    = btn_up    & ~btn_up_prev;
    wire btn_down_rise  = btn_down  & ~btn_down_prev;
    wire btn_left_rise  = btn_left  & ~btn_left_prev;
    wire btn_right_rise = btn_right & ~btn_right_prev;

    // Off-screen detection for log carrying
    assign carried_offscreen = (chicken_x < SCREEN_LEFT) ||
                               (chicken_x > SCREEN_RIGHT);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            chicken_x      <= START_X;
            chicken_y      <= START_Y;
            world_y        <= 11'd0;
            facing         <= FACE_UP;
            is_moving      <= 1'b0;
            btn_up_prev    <= 1'b0;
            btn_down_prev  <= 1'b0;
            btn_left_prev  <= 1'b0;
            btn_right_prev <= 1'b0;
        end else begin
            btn_up_prev    <= btn_up;
            btn_down_prev  <= btn_down;
            btn_left_prev  <= btn_left;
            btn_right_prev <= btn_right;
            is_moving      <= 1'b0;

            if (game_active) begin
                // ── Log carrying: shift X with the log each tick ──
                if (log_carry_en) begin
                    if (log_carry_right) begin
                        chicken_x <= chicken_x + {7'd0, log_carry_speed};
                    end else begin
                        if (chicken_x >= {7'd0, log_carry_speed})
                            chicken_x <= chicken_x - {7'd0, log_carry_speed};
                        else
                            chicken_x <= 11'd0;  // Will trigger carried_offscreen
                    end
                end

                // ── Button hops (override log carry direction) ──
                if (btn_up_rise) begin
                    facing    <= FACE_UP;
                    is_moving <= 1'b1;
                    if (chicken_y <= SCROLL_THRESH)
                        world_y <= world_y + LANE_HEIGHT;
                    else if (chicken_y >= GAME_TOP + LANE_HEIGHT)
                        chicken_y <= chicken_y - LANE_HEIGHT;
                end
                else if (btn_down_rise) begin
                    facing    <= FACE_DOWN;
                    is_moving <= 1'b1;
                    if (chicken_y + LANE_HEIGHT <= GAME_BOTTOM)
                        chicken_y <= chicken_y + LANE_HEIGHT;
                end
                else if (btn_left_rise) begin
                    facing    <= FACE_LEFT;
                    is_moving <= 1'b1;
                    if (chicken_x >= SCREEN_LEFT + HOP_X)
                        chicken_x <= chicken_x - HOP_X;
                    else
                        chicken_x <= SCREEN_LEFT;
                end
                else if (btn_right_rise) begin
                    facing    <= FACE_RIGHT;
                    is_moving <= 1'b1;
                    if (chicken_x + HOP_X <= SCREEN_RIGHT)
                        chicken_x <= chicken_x + HOP_X;
                    else
                        chicken_x <= SCREEN_RIGHT;
                end
            end
        end
    end

endmodule
