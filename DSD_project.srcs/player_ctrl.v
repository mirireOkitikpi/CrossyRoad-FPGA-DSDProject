`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      player_ctrl.v  (patched)
//
// Fix vs previous revision:
//   - Added game_reset_pulse input. When high for one game_clk tick, the
//     chicken is returned to its spawn grid position (START_X, START_Y),
//     logical_world_y is zeroed, facing is set to FACE_UP, and the button
//     edge-detect previous-state registers are cleared.
//   - This fixes the bug where a restarted game left the chicken at the
//     position where it died (often on a chasm/river lane), which combined
//     with the 2-second spawn-invuln timer meant the chicken died the
//     instant invulnerability expired.
//   - Edge-detect registers are also cleared so a held btn_c from the
//     restart press is not interpreted as an Up/Down/Left/Right hop.
//////////////////////////////////////////////////////////////////////////////////

module player_ctrl (
    input             clk,
    input             rst,
    input             game_reset_pulse,  
    input             btn_up,
    input             btn_down,
    input             btn_left,
    input             btn_right,
    input             game_active,
    input             flick_jump_flag,
    output reg        clear_flick_flag,
    input             log_carry_en,
    input             log_carry_right,
    input      [3:0]  log_carry_speed,
    output reg [10:0] chicken_x,
    output reg [10:0] chicken_y,
    output reg [10:0] logical_world_y,
    output reg [1:0]  facing,
    output reg        is_moving,
    output            carried_offscreen
);

    localparam HOP_X        = 11'd32;
    localparam SCREEN_LEFT  = 11'd4;
    localparam SCREEN_RIGHT = 11'd1404;

    // Lane centre-line constants (y of the chicken hitbox top-left when
    // sitting in each lane). L0 is nearest the top of the play area.
    localparam L0 = 11'd148;
    localparam L1 = 11'd276;
    localparam L2 = 11'd404;
    localparam L3 = 11'd532;
    localparam L4 = 11'd660;
    localparam L5 = 11'd788;

    localparam START_X = 11'd704;
    localparam START_Y = L5;

    localparam FACE_UP    = 2'd0;
    localparam FACE_DOWN  = 2'd1;
    localparam FACE_LEFT  = 2'd2;
    localparam FACE_RIGHT = 2'd3;

    reg btn_up_prev, btn_down_prev, btn_left_prev, btn_right_prev;
    wire btn_up_rise    = btn_up    & ~btn_up_prev;
    wire btn_down_rise  = btn_down  & ~btn_down_prev;
    wire btn_left_rise  = btn_left  & ~btn_left_prev;
    wire btn_right_rise = btn_right & ~btn_right_prev;

    assign carried_offscreen = (chicken_x < SCREEN_LEFT) || (chicken_x > SCREEN_RIGHT);

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // Hardware reset path.
            chicken_x        <= START_X;
            chicken_y        <= START_Y;
            logical_world_y  <= 11'd0;
            facing           <= FACE_UP;
            is_moving        <= 1'b0;
            btn_up_prev      <= 1'b0;
            btn_down_prev    <= 1'b0;
            btn_left_prev    <= 1'b0;
            btn_right_prev   <= 1'b0;
            clear_flick_flag <= 1'b0;
        end else if (game_reset_pulse) begin
            chicken_x        <= START_X;
            chicken_y        <= START_Y;
            logical_world_y  <= 11'd0;
            facing           <= FACE_UP;
            is_moving        <= 1'b0;
            btn_up_prev      <= btn_up;
            btn_down_prev    <= btn_down;
            btn_left_prev    <= btn_left;
            btn_right_prev   <= btn_right;
            clear_flick_flag <= 1'b0;
        end else begin
            btn_up_prev      <= btn_up;
            btn_down_prev    <= btn_down;
            btn_left_prev    <= btn_left;
            btn_right_prev   <= btn_right;
            is_moving        <= 1'b0;
            clear_flick_flag <= 1'b0;

            if (flick_jump_flag) begin
                clear_flick_flag <= 1'b1;
                if (game_active) begin
                    facing    <= FACE_UP;
                    is_moving <= 1'b1;
                    if      (chicken_y == L5) chicken_y <= L3;
                    else if (chicken_y == L4) chicken_y <= L2;
                    else if (chicken_y == L3) begin
                        chicken_y       <= L2;
                        logical_world_y <= logical_world_y + 11'd128;
                    end
                    else if (chicken_y <= L2) logical_world_y <= logical_world_y + 11'd256;
                end
            end else if (game_active) begin
                if (log_carry_en) begin
                    if (log_carry_right) begin
                        chicken_x <= chicken_x + {7'd0, log_carry_speed};
                    end else begin
                        if (chicken_x >= {7'd0, log_carry_speed})
                            chicken_x <= chicken_x - {7'd0, log_carry_speed};
                        else
                            chicken_x <= 11'd0;
                    end
                end

                if (btn_up_rise) begin
                    facing    <= FACE_UP;
                    is_moving <= 1'b1;
                    if      (chicken_y == L5) chicken_y <= L4;
                    else if (chicken_y == L4) chicken_y <= L3;
                    else if (chicken_y == L3) chicken_y <= L2;
                    else if (chicken_y <= L2) logical_world_y <= logical_world_y + 11'd128;
                end else if (btn_down_rise) begin
                    facing    <= FACE_DOWN;
                    is_moving <= 1'b1;
                    if      (chicken_y == L0) chicken_y <= L1;
                    else if (chicken_y == L1) chicken_y <= L2;
                    else if (chicken_y == L2) chicken_y <= L3;
                    else if (chicken_y == L3) chicken_y <= L4;
                    else if (chicken_y == L4) chicken_y <= L5;
                end else if (btn_left_rise) begin
                    facing    <= FACE_LEFT;
                    is_moving <= 1'b1;
                    if (chicken_x >= SCREEN_LEFT + HOP_X) chicken_x <= chicken_x - HOP_X;
                    else                                   chicken_x <= SCREEN_LEFT;
                end else if (btn_right_rise) begin
                    facing    <= FACE_RIGHT;
                    is_moving <= 1'b1;
                    if (chicken_x + HOP_X <= SCREEN_RIGHT) chicken_x <= chicken_x + HOP_X;
                    else                                    chicken_x <= SCREEN_RIGHT;
                end
            end
        end
    end
endmodule
