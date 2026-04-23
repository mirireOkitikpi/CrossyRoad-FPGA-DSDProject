`timescale 1ns / 1ps

module goose_manager (
    input             clk,
    input             rst,
    input             game_active,
    
    input      [10:0] player_x,
    input      [10:0] player_y,         
    input      [10:0] logical_world_y,  
    input             shout_detected,
    output reg        clear_shout_flag, 
    
    input             spawn_pulse,       
    input      [10:0] spawn_y,           
    input      [15:0] lfsr_rand,         
    
    input      [1:0]  sw, // Using sw[0] and sw[1] for Difficulty
    
    output     [10:0] goose0_x, output [10:0] goose0_y, output goose0_act, output goose0_scared, output [2:0] goose0_frame,
    output     [10:0] goose1_x, output [10:0] goose1_y, output goose1_act, output goose1_scared, output [2:0] goose1_frame,
    output     [10:0] goose2_x, output [10:0] goose2_y, output goose2_act, output goose2_scared, output [2:0] goose2_frame,
    
    output reg        goose_hit,
    output reg [5:0]  goose_bonus,
    output reg [2:0]  difficulty_bonus_type // Tells game_top if we give 1, 2, or 4 points
);

    localparam FLY_SPEED    = 11'd4;
    localparam SCREEN_LEFT  = 11'd4;
    localparam SCREEN_RIGHT = 11'd1404;
    localparam CHICKEN_SIZE = 11'd64;
    
    // ── DIFFICULTY DECODER ──
    reg [10:0] goose_speed;
    reg        reduced_shout_radius;
    
    always @(*) begin
        case (sw[1:0])
            2'b01: begin // Level 1
                goose_speed = 11'd3;           // 1.5x Speed (Normal is 2)
                reduced_shout_radius = 1'b0;   // Normal Shout
                difficulty_bonus_type = 3'd1;  // +1 Point per 5 lanes
            end
            2'b10: begin // Level 2
                goose_speed = 11'd2;           // Normal Speed
                reduced_shout_radius = 1'b1;   // Reduced Shout (Lane only)
                difficulty_bonus_type = 3'd2;  // +2 Points per 5 lanes
            end
            2'b11: begin // Level 3
                goose_speed = 11'd4;           // 2x Speed
                reduced_shout_radius = 1'b1;   // Reduced Shout (Lane only)
                difficulty_bonus_type = 3'd4;  // +4 Points per 5 lanes
            end
            default: begin // Normal / Level 0
                goose_speed = 11'd2;
                reduced_shout_radius = 1'b0;
                difficulty_bonus_type = 3'd0;
            end
        endcase
    end

    reg        active [0:2];
    reg        scared [0:2];
    reg [10:0] x_pos  [0:2];
    reg [10:0] y_pos  [0:2];
    reg [2:0]  frame  [0:2]; 
    
    integer i;

    assign goose0_x = x_pos[0]; assign goose0_y = y_pos[0]; assign goose0_act = active[0]; assign goose0_scared = scared[0]; assign goose0_frame = frame[0];
    assign goose1_x = x_pos[1]; assign goose1_y = y_pos[1]; assign goose1_act = active[1]; assign goose1_scared = scared[1]; assign goose1_frame = frame[1];
    assign goose2_x = x_pos[2]; assign goose2_y = y_pos[2]; assign goose2_act = active[2]; assign goose2_scared = scared[2]; assign goose2_frame = frame[2];

    reg [10:0] prev_world_y;
    wire world_scrolled = (logical_world_y != prev_world_y) && game_active;

    reg [3:0] anim_tick;
    reg [2:0] fly_frame;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            goose_hit <= 0; goose_bonus <= 0; prev_world_y <= 0; anim_tick <= 0; fly_frame <= 3'd2;
            for (i = 0; i < 3; i = i + 1) begin
                active[i] <= 0; scared[i] <= 0; x_pos[i] <= 0; y_pos[i] <= 0; frame[i] <= 0;
            end
        end else if (!game_active) begin
             goose_hit <= 0; goose_bonus <= 0;
             for (i = 0; i < 3; i = i + 1) active[i] <= 0;
        end else begin
            goose_hit <= 0; clear_shout_flag <= 0; goose_bonus <= 0;
            
            if (world_scrolled) prev_world_y <= prev_world_y + 11'd128;
            
            anim_tick <= anim_tick + 1;
            if (anim_tick == 4'd7) begin 
                if (fly_frame == 3'd4) fly_frame <= 3'd2; else fly_frame <= fly_frame + 1;
            end

            for (i = 0; i < 3; i = i + 1) begin
                if (scared[i]) frame[i] <= fly_frame;
                else if (y_pos[i] == player_y) frame[i] <= 3'd1; else frame[i] <= 3'd0; 
            end
            
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
            
            if (shout_detected) begin
                clear_shout_flag <= 1'b1;  
                for (i = 0; i < 3; i = i + 1) begin
                    if (active[i] && !scared[i]) begin
                        if (!reduced_shout_radius || (y_pos[i] == player_y)) begin
                            scared[i] <= 1;
                            goose_bonus <= goose_bonus + 6'd10;
                        end
                    end
                end
            end

            for (i = 0; i < 3; i = i + 1) begin
                if (active[i]) begin
                    if (world_scrolled) y_pos[i] <= y_pos[i] + 11'd128;
                    if (y_pos[i] > 11'd800) active[i] <= 0;
                    
                    if (scared[i]) begin
                        y_pos[i] <= y_pos[i] - 11'd2; 
                        if (y_pos[i] < 11'd100) active[i] <= 0; 
                        if (x_pos[i] > 11'd700) begin
                            x_pos[i] <= x_pos[i] + FLY_SPEED;
                            if (x_pos[i] >= SCREEN_RIGHT) active[i] <= 0;
                        end else begin
                            x_pos[i] <= x_pos[i] - FLY_SPEED;
                            if (x_pos[i] <= SCREEN_LEFT) active[i] <= 0;
                        end
                    end 
                    else if (y_pos[i] == player_y) begin 
                        // SCALED SPEED 
                        if (player_x > x_pos[i])      x_pos[i] <= x_pos[i] + goose_speed;
                        else if (player_x < x_pos[i]) x_pos[i] <= x_pos[i] - goose_speed;
                    end
                    
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
