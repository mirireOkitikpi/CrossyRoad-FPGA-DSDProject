`timescale 1ns / 1ps
// Module: goose_manager.v
// Purpose: Manages up to three concurrent goose enemy instances. Geese spawn on
//          grass lanes, walk toward the player horizontally while on the same lane,
//          and can be scared away by a shout (microphone input). A scared goose
//          flies off-screen and awards bonus points.
//
// Spawn: lane_manager fires grass_spawn_pulse when a new grass lane enters the
//        visible area. goose_manager allocates the first inactive slot with 50%
//        probability (LFSR bit 0) to vary encounter density.
//
// Animation: the goose sprite sheet is 320x64 — five 64-px-wide frames.
//   Frame 0  — idle (facing player direction)
//   Frame 1  — alert (player is on the same lane)
//   Frames 2-4 — flying (cycled at ~30 fps when scared)
//
// Difficulty (sw[1:0]):
//   00 — normal speed, full shout radius, no cross-bonus
//   01 — 1.5x speed, full shout radius, +1 pt per 5 lanes
//   10 — normal speed, same-lane shout only, +2 pts per 5 lanes
//   11 — 2x speed, same-lane shout only, +4 pts per 5 lanes
//
// Collision: AABB against the 64x64 chicken hitbox. goose_hit is a single-cycle
//   pulse consumed by game_top. game_top additionally gates goose_hit through
//   g*_valid flags so a goose on a non-grass lane cannot kill the player.
//
// Bonus: each scared goose awards 6 points accumulated into goose_bonus.
//   game_top adds goose_bonus to the score on the same tick.

module goose_manager (
    input             clk,
    input             rst,
    input             game_active,

    input      [10:0] player_x,
    input      [10:0] player_y,
    input      [10:0] logical_world_y,
    input             shout_detected,       // Single-cycle pulse from mic_ctrl CDC flag
    output reg        clear_shout_flag,     // Acknowledges shout consumption to game_top

    input             spawn_pulse,          // One-cycle pulse from lane_manager on new grass lane
    input      [10:0] spawn_y,
    input      [15:0] lfsr_rand,            // LFSR state from lane_manager for spawn randomisation

    input      [1:0]  sw,                   // Difficulty selector sw[1:0]

    output     [10:0] goose0_x, output [10:0] goose0_y, output goose0_act, output goose0_scared, output [2:0] goose0_frame,
    output     [10:0] goose1_x, output [10:0] goose1_y, output goose1_act, output goose1_scared, output [2:0] goose1_frame,
    output     [10:0] goose2_x, output [10:0] goose2_y, output goose2_act, output goose2_scared, output [2:0] goose2_frame,

    output reg        goose_hit,            // Single-cycle AABB collision pulse
    output reg [5:0]  goose_bonus,          // Bonus points accumulated this tick on shout
    output reg [2:0]  difficulty_bonus_type // Per-5-lane bonus multiplier for game_top
);

    localparam FLY_SPEED    = 11'd4;    // Horizontal exit speed when scared (px/tick)
    localparam SCREEN_LEFT  = 11'd4;    // Left despawn boundary
    localparam SCREEN_RIGHT = 11'd1404; // Right despawn boundary
    localparam CHICKEN_SIZE = 11'd64;   // Player hitbox side length for AABB

    // Difficulty decode
    // goose_speed: how fast a grounded goose chases the player horizontally.
    // reduced_shout_radius: when set, shout only scares geese on the player's lane.
    reg [10:0] goose_speed;
    reg        reduced_shout_radius;

    always @(*) begin
        case (sw[1:0])
            2'b01: begin // Level 1 — faster chase, global shout, small bonus
                goose_speed           = 11'd3;
                reduced_shout_radius  = 1'b0;
                difficulty_bonus_type = 3'd1;
            end
            2'b10: begin // Level 2 — normal speed, same-lane shout only, medium bonus
                goose_speed           = 11'd2;
                reduced_shout_radius  = 1'b1;
                difficulty_bonus_type = 3'd2;
            end
            2'b11: begin // Level 3 — 2x speed, same-lane shout only, large bonus
                goose_speed           = 11'd4;
                reduced_shout_radius  = 1'b1;
                difficulty_bonus_type = 3'd4;
            end
            default: begin // Level 0 — baseline
                goose_speed           = 11'd2;
                reduced_shout_radius  = 1'b0;
                difficulty_bonus_type = 3'd0;
            end
        endcase
    end

    // Per-instance state (3 slots)
    reg        active [0:2]; // Whether this slot is in use
    reg        scared [0:2]; // Whether this goose has been scared and is flying away
    reg [10:0] x_pos  [0:2];
    reg [10:0] y_pos  [0:2];
    reg [2:0]  frame  [0:2]; // Sprite sheet frame index (0-4)

    integer i;

    // Flatten array outputs to flat ports (Verilog-2001 cannot use array ports)
    assign goose0_x = x_pos[0]; assign goose0_y = y_pos[0]; assign goose0_act = active[0]; assign goose0_scared = scared[0]; assign goose0_frame = frame[0];
    assign goose1_x = x_pos[1]; assign goose1_y = y_pos[1]; assign goose1_act = active[1]; assign goose1_scared = scared[1]; assign goose1_frame = frame[1];
    assign goose2_x = x_pos[2]; assign goose2_y = y_pos[2]; assign goose2_act = active[2]; assign goose2_scared = scared[2]; assign goose2_frame = frame[2];

    // World scroll tracking: mirrors the logic in lane_manager and player_ctrl.
    // When logical_world_y changes, active goose Y positions advance by 128 so
    // geese remain visually attached to their lane as the world scrolls.
    reg [10:0] prev_world_y;
    wire world_scrolled = (logical_world_y != prev_world_y) && game_active;

    // Animation ticker: cycles flying frames 2→3→4→2 at approximately 30 fps.
    // anim_tick increments each game_clk tick; fly_frame advances every 8 ticks.
    reg [3:0] anim_tick;
    reg [2:0] fly_frame;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            goose_hit <= 0; goose_bonus <= 0; prev_world_y <= 0;
            anim_tick <= 0; fly_frame <= 3'd2;
            for (i = 0; i < 3; i = i + 1) begin
                active[i] <= 0; scared[i] <= 0;
                x_pos[i]  <= 0; y_pos[i]  <= 0; frame[i] <= 0;
            end

        end else if (!game_active) begin
            // Deactivate all geese when the game is not running
            goose_hit <= 0; goose_bonus <= 0;
            for (i = 0; i < 3; i = i + 1) active[i] <= 0;

        end else begin
            goose_hit        <= 0;
            clear_shout_flag <= 0;
            goose_bonus      <= 0;

            if (world_scrolled) prev_world_y <= prev_world_y + 11'd128;

            // Advance animation ticker and cycle fly_frame through 2→3→4→2
            anim_tick <= anim_tick + 1;
            if (anim_tick == 4'd7) begin
                if (fly_frame == 3'd4) fly_frame <= 3'd2;
                else                   fly_frame <= fly_frame + 1;
            end

            // Per-goose animation frame assignment:
            //   Scared geese use the cycling fly_frame.
            //   Grounded geese on the player's lane use frame 1 (alert).
            //   All other grounded geese use frame 0 (idle).
            for (i = 0; i < 3; i = i + 1) begin
                if (scared[i])               frame[i] <= fly_frame;
                else if (y_pos[i] == player_y) frame[i] <= 3'd1;
                else                           frame[i] <= 3'd0;
            end

            // Spawn: fill the first inactive slot on a grass lane pulse.
            // lfsr_rand[0] provides 50% spawn probability.
            // lfsr_rand[2]/[3]/[4] select left or right screen entry point.
            if (spawn_pulse) begin
                if (lfsr_rand[0] == 1'b0) begin
                    if (!active[0]) begin
                        active[0] <= 1; scared[0] <= 0; y_pos[0] <= 11'd148;
                        x_pos[0]  <= (lfsr_rand[2]) ? SCREEN_LEFT : SCREEN_RIGHT;
                    end else if (!active[1]) begin
                        active[1] <= 1; scared[1] <= 0; y_pos[1] <= 11'd148;
                        x_pos[1]  <= (lfsr_rand[3]) ? SCREEN_LEFT : SCREEN_RIGHT;
                    end else if (!active[2]) begin
                        active[2] <= 1; scared[2] <= 0; y_pos[2] <= 11'd148;
                        x_pos[2]  <= (lfsr_rand[4]) ? SCREEN_LEFT : SCREEN_RIGHT;
                    end
                end
            end

            // Shout handler: scare all active un-scared geese within range.
            // If reduced_shout_radius is set (difficulty >= 2), only scare
            // geese whose lane row matches the player (y_pos[i] == player_y).
            // Each scared goose awards 6 bonus points.
            if (shout_detected) begin
                clear_shout_flag <= 1'b1;
                for (i = 0; i < 3; i = i + 1) begin
                    if (active[i] && !scared[i]) begin
                        if (!reduced_shout_radius || (y_pos[i] == player_y)) begin
                            scared[i]   <= 1;
                            goose_bonus <= goose_bonus + 6'd6;
                        end
                    end
                end
            end

            // Per-goose update
            for (i = 0; i < 3; i = i + 1) begin
                if (active[i]) begin
                    // Scroll goose down with the world on each lane shift
                    if (world_scrolled) y_pos[i] <= y_pos[i] + 11'd128;

                    // Despawn when pushed below the visible game area
                    if (y_pos[i] > 11'd800) active[i] <= 0;

                    if (scared[i]) begin
                        // Flying: move upward and exit to the nearest screen edge.
                        // Threshold at x=700 (screen centre) picks the exit direction.
                        y_pos[i] <= y_pos[i] - 11'd2;
                        if (y_pos[i] < 11'd100) active[i] <= 0; // Above info bar

                        if (x_pos[i] > 11'd700) begin
                            x_pos[i] <= x_pos[i] + FLY_SPEED;
                            if (x_pos[i] >= SCREEN_RIGHT) active[i] <= 0;
                        end else begin
                            x_pos[i] <= x_pos[i] - FLY_SPEED;
                            if (x_pos[i] <= SCREEN_LEFT)  active[i] <= 0;
                        end

                    end else if (y_pos[i] == player_y) begin
                        // Grounded goose on the player's lane: chase horizontally.
                        // Speed scales with the difficulty setting.
                        if (player_x > x_pos[i])      x_pos[i] <= x_pos[i] + goose_speed;
                        else if (player_x < x_pos[i]) x_pos[i] <= x_pos[i] - goose_speed;
                    end

                    // AABB collision: active un-scared goose on player's lane.
                    // Checks horizontal overlap of two CHICKEN_SIZE-wide bounding boxes.
                    if (!scared[i] && y_pos[i] == player_y) begin
                        if ((player_x + CHICKEN_SIZE > x_pos[i]) && (player_x < x_pos[i] + CHICKEN_SIZE)) begin
                            goose_hit <= 1;
                        end
                    end
                end
            end
        end
    end

endmodule
