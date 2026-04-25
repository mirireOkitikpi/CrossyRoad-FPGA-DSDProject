`timescale 1ns / 1ps
// Module: player_ctrl.v
// Purpose: Manages the player chicken's position, orientation, and world-scroll
//          counter. Movement is discrete (one lane or HOP_X pixels per button
//          press) and is processed on the rising edge of each debounced button
//          input. A log-carry input allows the chicken to be passively displaced
//          by a river log while standing on it.
//
// Coordinate system:
//   chicken_x uses 12-bit signed two's complement math to allow safe subtraction
//   and bounding against screen edges without unsigned integer underflow.
//   chicken_y remains 11-bit unsigned as vertical movement is strictly clamped
//   to visible lanes.
//   Lanes L0-L5 are defined as fixed Y values (top of sprite when centred).
//   L5 is the starting lane (nearest the player / bottom of screen).
//
// High-watermark scoring:
//   score_point_pulse fires for exactly one game_clk tick when the player reaches
//   a lane they have never previously visited in the current game.
//   current_lane_abs tracks the player's absolute forward position (increments on
//   every genuine upward hop, decrements on downward hops).
//   max_lane_reached records the furthest position ever reached and is never
//   decremented. A point is only awarded when current_lane_abs strictly exceeds
//   max_lane_reached, preventing back-and-forth farming on any lane.
//   Both flick jumps and button hops advance current_lane_abs, so all movement
//   modes score correctly.
//
// Exploit mitigations:
//   - Pulse uses btn_up_rise and flick_jump_flag (edge signals), NOT btn_up level.
//     Using the level would fire every game_clk tick the button is held.
//   - Flick increments current_lane_abs proportionally (2 lanes for L5/L4 skip,
//     1 lane for L3/above scroll) matching the actual distance travelled.
//   - max_lane_reached resets on game_reset_pulse so each game starts from 0.
//   - score_point_pulse is forced low on game_reset_pulse to avoid a spurious
//     point on the first tick of a new game.
//
// Authors: 2217321 & 2233381

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

    // Signed 12-bit to support negative bounds arithmetic without underflow
    output reg signed [11:0] chicken_x,
    output reg [10:0] chicken_y,
    output reg [10:0] logical_world_y,
    output reg [1:0]  facing,
    output reg        is_moving,
    output            carried_offscreen,

    // High-watermark score pulse: asserts for one game_clk tick when the
    // player reaches a new forward record. Consumed by game_top for scoring.
    output reg        score_point_pulse
);

    // X-axis constants in signed 12-bit for uniform arithmetic
    localparam signed [11:0] HOP_X        = 12'sd32;
    localparam signed [11:0] SCREEN_LEFT  = 12'sd4;
    localparam signed [11:0] SCREEN_RIGHT = 12'sd1404;
    localparam signed [11:0] START_X      = 12'sd704;

    // Lane Y positions - top-left of the 64x64 sprite centred in a 128-px lane
    localparam L0 = 11'd148;
    localparam L1 = 11'd276;
    localparam L2 = 11'd404;
    localparam L3 = 11'd532;
    localparam L4 = 11'd660;
    localparam L5 = 11'd788;

    localparam START_Y = L5;

    localparam FACE_UP    = 2'd0;
    localparam FACE_DOWN  = 2'd1;
    localparam FACE_LEFT  = 2'd2;
    localparam FACE_RIGHT = 2'd3;

    // Rising-edge detectors for each button
    reg btn_up_prev, btn_down_prev, btn_left_prev, btn_right_prev;
    wire btn_up_rise    = btn_up    & ~btn_up_prev;
    wire btn_down_rise  = btn_down  & ~btn_down_prev;
    wire btn_left_rise  = btn_left  & ~btn_left_prev;
    wire btn_right_rise = btn_right & ~btn_right_prev;

    // carried_offscreen: asserted when log carry has drifted the chicken past
    // a screen boundary. game_top uses this to trigger a river death.
    assign carried_offscreen = (chicken_x < SCREEN_LEFT) || (chicken_x > SCREEN_RIGHT);

    // High-watermark tracking registers
    // current_lane_abs: player's absolute lane count from spawn (increases on
    //   forward hops, decreases on backward hops, unbounded in both directions).
    // max_lane_reached: all-time maximum of current_lane_abs in this game session.
    //   Never decremented - only updated when current_lane_abs exceeds it.
    reg [15:0] current_lane_abs;
    reg [15:0] max_lane_reached;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            chicken_x         <= START_X;
            chicken_y         <= START_Y;
            logical_world_y   <= 11'd0;
            facing            <= FACE_UP;
            is_moving         <= 1'b0;
            btn_up_prev       <= 1'b0;
            btn_down_prev     <= 1'b0;
            btn_left_prev     <= 1'b0;
            btn_right_prev    <= 1'b0;
            clear_flick_flag  <= 1'b0;
            score_point_pulse <= 1'b0;
            current_lane_abs  <= 16'd0;
            max_lane_reached  <= 16'd0;

        end else if (game_reset_pulse) begin
            // Soft reset on game restart. Load edge-detect registers with the
            // current button state so a held button from the restart press does
            // not register as a rising edge on the very next tick.
            chicken_x         <= START_X;
            chicken_y         <= START_Y;
            logical_world_y   <= 11'd0;
            facing            <= FACE_UP;
            is_moving         <= 1'b0;
            btn_up_prev       <= btn_up;
            btn_down_prev     <= btn_down;
            btn_left_prev     <= btn_left;
            btn_right_prev    <= btn_right;
            clear_flick_flag  <= 1'b0;
            // Force pulse low so the FSM does not see a spurious point on the
            // first tick after reset, before any real movement has occurred.
            score_point_pulse <= 1'b0;
            current_lane_abs  <= 16'd0;
            max_lane_reached  <= 16'd0;

        end else begin
            btn_up_prev       <= btn_up;
            btn_down_prev     <= btn_down;
            btn_left_prev     <= btn_left;
            btn_right_prev    <= btn_right;
            is_moving         <= 1'b0;
            clear_flick_flag  <= 1'b0;
            score_point_pulse <= 1'b0; // Default low - only raised for one tick below

            if (flick_jump_flag) begin
                clear_flick_flag <= 1'b1;
                if (game_active) begin
                    facing    <= FACE_UP;
                    is_moving <= 1'b1;

                    if (chicken_y == L5) begin
                        // Skip two lanes: L5 -> L3
                        chicken_y        <= L3;
                        current_lane_abs <= current_lane_abs + 16'd2;
                        if ((current_lane_abs + 16'd2) > max_lane_reached) begin
                            max_lane_reached  <= current_lane_abs + 16'd2;
                            score_point_pulse <= 1'b1;
                        end

                    end else if (chicken_y == L4) begin
                        // Skip two lanes: L4 -> L2
                        chicken_y        <= L2;
                        current_lane_abs <= current_lane_abs + 16'd2;
                        if ((current_lane_abs + 16'd2) > max_lane_reached) begin
                            max_lane_reached  <= current_lane_abs + 16'd2;
                            score_point_pulse <= 1'b1;
                        end

                    end else if (chicken_y == L3) begin
                        // One visible hop + one world scroll tick
                        chicken_y        <= L2;
                        logical_world_y  <= logical_world_y + 11'd128;
                        current_lane_abs <= current_lane_abs + 16'd2;
                        if ((current_lane_abs + 16'd2) > max_lane_reached) begin
                            max_lane_reached  <= current_lane_abs + 16'd2;
                            score_point_pulse <= 1'b1;
                        end

                    end else if (chicken_y <= L2) begin
                        // Two world scroll ticks, no visible Y change
                        logical_world_y  <= logical_world_y + 11'd256;
                        current_lane_abs <= current_lane_abs + 16'd2;
                        if ((current_lane_abs + 16'd2) > max_lane_reached) begin
                            max_lane_reached  <= current_lane_abs + 16'd2;
                            score_point_pulse <= 1'b1;
                        end
                    end
                end

            end else if (game_active) begin

                // Passive log carry: uses signed arithmetic to clamp correctly
                // at screen edges. The log carries the chicken at log speed
                // each tick while log_carry_en is high.
                if (log_carry_en) begin
                    if (log_carry_right) begin
                        if (chicken_x + $signed({8'd0, log_carry_speed}) >= SCREEN_RIGHT)
                            chicken_x <= SCREEN_RIGHT;
                        else
                            chicken_x <= chicken_x + $signed({8'd0, log_carry_speed});
                    end else begin
                        if (chicken_x - $signed({8'd0, log_carry_speed}) <= SCREEN_LEFT)
                            chicken_x <= SCREEN_LEFT;
                        else
                            chicken_x <= chicken_x - $signed({8'd0, log_carry_speed});
                    end
                end

                if (btn_up_rise) begin
                    // Forward hop: advance current_lane_abs and check watermark.
                    // btn_up_rise (edge) is used here, NOT btn_up (level), so
                    // holding the button only registers one hop per press.
                    facing           <= FACE_UP;
                    is_moving        <= 1'b1;
                    current_lane_abs <= current_lane_abs + 16'd1;

                    if ((current_lane_abs + 16'd1) > max_lane_reached) begin
                        max_lane_reached  <= current_lane_abs + 16'd1;
                        score_point_pulse <= 1'b1;
                    end

                    if      (chicken_y == L5) chicken_y <= L4;
                    else if (chicken_y == L4) chicken_y <= L3;
                    else if (chicken_y == L3) chicken_y <= L2;
                    else if (chicken_y <= L2) logical_world_y <= logical_world_y + 11'd128;

                end else if (btn_down_rise) begin
                    // Backward hop: decrement current_lane_abs (record is preserved).
                    // Underflow guard prevents current_lane_abs wrapping below 0.
                    facing    <= FACE_DOWN;
                    is_moving <= 1'b1;
                    if (current_lane_abs > 16'd0)
                        current_lane_abs <= current_lane_abs - 16'd1;

                    if      (chicken_y == L0) chicken_y <= L1;
                    else if (chicken_y == L1) chicken_y <= L2;
                    else if (chicken_y == L2) chicken_y <= L3;
                    else if (chicken_y == L3) chicken_y <= L4;
                    else if (chicken_y == L4) chicken_y <= L5;

                end else if (btn_left_rise) begin
                    facing    <= FACE_LEFT;
                    is_moving <= 1'b1;
                    if (chicken_x - HOP_X <= SCREEN_LEFT)
                        chicken_x <= SCREEN_LEFT;
                    else
                        chicken_x <= chicken_x - HOP_X;

                end else if (btn_right_rise) begin
                    facing    <= FACE_RIGHT;
                    is_moving <= 1'b1;
                    if (chicken_x + HOP_X >= SCREEN_RIGHT)
                        chicken_x <= SCREEN_RIGHT;
                    else
                        chicken_x <= chicken_x + HOP_X;
                end
            end
        end
    end

endmodule
