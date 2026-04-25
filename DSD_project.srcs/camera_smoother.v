`timescale 1ns / 1ps
// Module: camera_smoother.v
// Purpose: Interpolates a render position toward a logical target position each
//          clock cycle so that lane scrolls and player hops appear smooth rather
//          than snapping by a full 128-pixel lane in one frame.
//
// Each cycle render_y steps toward logical_y by at most PAN_SPEED pixels.
// When the remaining gap is smaller than PAN_SPEED the remainder is closed
// exactly, preventing overshoot oscillation around the target.
//
// Reset is intentionally SYNCHRONOUS (sensitivity list is posedge clk only).
// An asynchronous reset cannot capture a run-time variable — it would load
// whatever combinational value logical_y has during reset assertion, which is
// not guaranteed stable. The synchronous path loads logical_y one cycle after
// deassertion, giving an instant snap to the correct position on game start or
// restart without a visible pan from 0.
//
// Three instances are used in game_top:
//   cam_smooth_inst — world scroll  (logical_world_y  → render_world_y)
//   smooth_chk_y    — chicken Y     (chicken_y        → render_chicken_y)
//   smooth_chk_x    — chicken X     (chicken_x[10:0]  → render_chicken_x)

module camera_smoother (
    input             clk,
    input             rst,
    input      [10:0] logical_y,  // Target position from game logic
    output reg [10:0] render_y    // Smoothed position fed to the VGA pipeline
);

    // Maximum pixels render_y steps toward logical_y per clock tick.
    // At game_clk (~60 Hz): 8 px/frame × 60 = 480 px/s — fast enough to
    // track a 128-px lane scroll in ~2-3 frames without feeling laggy.
    localparam PAN_SPEED = 11'd8;

    always @(posedge clk) begin
        if (!rst) begin
            // Snap render_y to logical_y on reset so the camera does not pan
            // from 0 to the player's respawn position at the start of each game.
            render_y <= logical_y;
        end else begin
            if (render_y < logical_y) begin
                // render_y is behind the target — step forward
                if ((logical_y - render_y) < PAN_SPEED)
                    render_y <= logical_y;         // Close small remainder exactly
                else
                    render_y <= render_y + PAN_SPEED;
            end
            else if (render_y > logical_y) begin
                // render_y is ahead (player moved back) — step backward
                if ((render_y - logical_y) < PAN_SPEED)
                    render_y <= logical_y;         // Close small remainder exactly
                else
                    render_y <= render_y - PAN_SPEED;
            end
            // render_y == logical_y: no update required.
        end
    end

endmodule
