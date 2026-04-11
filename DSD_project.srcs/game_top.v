`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      game_top.v
// Description: Top-level for Sanic Road Rush. 
// Features: 6-Lane optimized layout, arcade invulnerability flashing, 
// and 3-bit lane types (supporting the new Chasm obstacle).
//////////////////////////////////////////////////////////////////////////////////

module game_top (
    input        clk,
    input        rst,
    input        btn_c, btn_u, btn_d, btn_l, btn_r,
    input  [2:0] sw,
    output [3:0] pix_r, pix_g, pix_b,
    output       hsync, vsync,
    output [6:0] seg,
    output [7:0] an,
    output [15:0] led,
    output       accel_cs,
    output       accel_mosi,
    output       accel_sclk,
    input        accel_miso
);

    // SECTION 1: Clocks
    wire pixclk, sys_clk;

    clk_wiz_0 clk_inst (
        .clk_out1(pixclk), .clk_out2(sys_clk), .clk_in1(clk)
    );

    reg [20:0] clk_div;
    reg        game_clk;

    always @(posedge sys_clk or negedge rst) begin
        if (!rst) begin clk_div <= 0; game_clk <= 0; end
        else if (clk_div == 21'd833333) begin clk_div <= 0; game_clk <= ~game_clk; end
        else clk_div <= clk_div + 1;
    end

    // Debouncing
    wire btn_c_db, btn_u_db, btn_d_db, btn_l_db, btn_r_db;

    debounce db_c (.clk(sys_clk), .rst(rst), .btn_in(btn_c), .btn_out(btn_c_db));
    debounce db_u (.clk(sys_clk), .rst(rst), .btn_in(btn_u), .btn_out(btn_u_db));
    debounce db_d (.clk(sys_clk), .rst(rst), .btn_in(btn_d), .btn_out(btn_d_db));
    debounce db_l (.clk(sys_clk), .rst(rst), .btn_in(btn_l), .btn_out(btn_l_db));
    debounce db_r (.clk(sys_clk), .rst(rst), .btn_in(btn_r), .btn_out(btn_r_db));

    //  Game state
    reg        game_started, game_over;
    reg        btn_c_prev;
    wire       btn_c_rise = btn_c_db & ~btn_c_prev;
    reg [7:0]  score, high_score;
    reg [2:0]  lives;
    wire       game_active = game_started & ~game_over;

    //  Global Coordinates & Lane Manager 
    wire [10:0] logical_world_y;
    wire [10:0] render_world_y;  
    wire [10:0] chicken_x;
    wire [10:0] chicken_y;
    wire [10:0] render_chicken_x;
    wire [10:0] render_chicken_y;
    // jump logic
    //wire flick_detected;
    
    wire flick_pulse_100MHz;
    wire flick_cleared_by_game;
    reg  flick_flag;
    
    adxl362_ctrl accel_inst (
        .clk(sys_clk), // 100MHz
        .rst(rst),
        .cs(accel_cs),
        .mosi(accel_mosi),
        .sclk(accel_sclk),
        .miso(accel_miso),
        .flick_detected(flick_pulse_100MHz) 
    );
    
    // Catch the fast pulse and hold it
    always @(posedge sys_clk or negedge rst) begin
        if (!rst) begin
            flick_flag <= 0;
        end else begin
            if (flick_pulse_100MHz) 
                flick_flag <= 1; 
            else if (flick_cleared_by_game) 
                flick_flag <= 0; 
        end
    end
    
    // Expanded to 3 bits to support Chasm
    wire [2:0] lt0, lt1, lt2, lt3, lt4, lt5;
    wire [10:0] ox0, ox1, ox2, ox3, ox4, ox5;
    wire [10:0] o2x0, o2x1, o2x2, o2x3, o2x4, o2x5;

    localparam INFO_BAR_H = 11'd100;
    localparam LANE_H     = 11'd64;

    // Hardware Math: >> 6 division
    wire [3:0] chk_lane = (chicken_y >= INFO_BAR_H) ? ((chicken_y - INFO_BAR_H) >> 6) : 4'd0;

    wire       qry_dir;
    wire [3:0] qry_speed;

    lane_manager lane_mgr (
        .clk(game_clk), .rst(rst),
        .game_active(game_active), .logical_world_y(logical_world_y),
        .lane_type_0(lt0), .lane_type_1(lt1), .lane_type_2(lt2),
        .lane_type_3(lt3), .lane_type_4(lt4), .lane_type_5(lt5),
        .obs_x_0(ox0), .obs_x_1(ox1), .obs_x_2(ox2), .obs_x_3(ox3), .obs_x_4(ox4), .obs_x_5(ox5),
        .obs2_x_0(o2x0), .obs2_x_1(o2x1), .obs2_x_2(o2x2), .obs2_x_3(o2x3), .obs2_x_4(o2x4), .obs2_x_5(o2x5),
        .query_lane(chk_lane), .query_dir(qry_dir), .query_speed(qry_speed)
    );

    //  Collision & Invulnerability System
    localparam OBS_W  = 11'd64;
    localparam LOG_W  = 11'd128;   
    localparam HB_IN  = 11'd4;
    
    reg [2:0]  chk_lt; // 3-bit lane type
    reg [10:0] chk_o1, chk_o2;

    always @(*) begin
        case (chk_lane)
            4'd0: begin chk_lt=lt0; chk_o1=ox0; chk_o2=o2x0; end
            4'd1: begin chk_lt=lt1; chk_o1=ox1; chk_o2=o2x1; end
            4'd2: begin chk_lt=lt2; chk_o1=ox2; chk_o2=o2x2; end
            4'd3: begin chk_lt=lt3; chk_o1=ox3; chk_o2=o2x3; end
            4'd4: begin chk_lt=lt4; chk_o1=ox4; chk_o2=o2x4; end
            4'd5: begin chk_lt=lt5; chk_o1=ox5; chk_o2=o2x5; end
            default: begin chk_lt=3'd0; chk_o1=11'd0; chk_o2=11'd0; end
        endcase
    end

    wire [10:0] hb_x = chicken_x + HB_IN;
    wire [10:0] hb_w = 11'd24;

    wire car_hit_1 = (chk_lt == 3'd1) && (hb_x < chk_o1 + OBS_W) && (hb_x + hb_w > chk_o1) && (chk_o1 < 11'd1440);
    wire car_hit_2 = (chk_lt == 3'd1) && (hb_x < chk_o2 + OBS_W) && (hb_x + hb_w > chk_o2) && (chk_o2 < 11'd1440);

    wire on_log_1 = (hb_x < chk_o1 + LOG_W) && (hb_x + hb_w > chk_o1) && (chk_o1 < 11'd1440);
    wire on_log_2 = (hb_x < chk_o2 + LOG_W) && (hb_x + hb_w > chk_o2) && (chk_o2 < 11'd1440);
    wire on_any_log = on_log_1 | on_log_2;

    wire is_river = (chk_lt == 3'd2);
    wire river_death = is_river && !on_any_log;
    wire chasm_death = (chk_lt == 3'd4);

    wire carried_offscreen;
    wire is_jumping = (chicken_y != render_chicken_y) || (logical_world_y != render_world_y);    
    wire any_collision = (car_hit_1 | car_hit_2 | river_death | chasm_death | carried_offscreen) && !is_jumping;
    // Damage / Invulnerability Logic 
    reg [6:0] invuln_timer; 
    wire invulnerable = (invuln_timer > 0);
    wire sprite_flash = invuln_timer[3]; 
    wire take_damage = any_collision && !invulnerable;

    // Player controller & Camera Smoothers
    wire [1:0]  chicken_facing;
    wire        chicken_moving;

    wire log_carry_en = is_river && on_any_log && game_active;
    //wire carried_offscreen;

    // ── ACCELEROMETER CLOCK CROSSING ──
   // wire flick_pulse_100MHz;        
   // wire flick_cleared_by_game;     
    //reg  flick_flag;                

//    adxl362_ctrl accel_inst (
//        .clk(sys_clk), // 100MHz
//        .rst(rst),
//        .cs(accel_cs),
//        .mosi(accel_mosi),
//        .sclk(accel_sclk),
//        .miso(accel_miso),
//        .flick_detected(flick_pulse_100MHz) 
//    );

    // Clock Domain Crossing: Catch the fast pulse and hold it
    always @(posedge sys_clk or negedge rst) begin
        if (!rst) begin
            flick_flag <= 0;
        end else begin
            if (flick_pulse_100MHz) 
                flick_flag <= 1; 
            else if (flick_cleared_by_game) 
                flick_flag <= 0; 
        end
    end

    player_ctrl player_inst (
        .clk(game_clk), .rst(rst),
        .btn_up(btn_u_db), .btn_down(btn_d_db),
        .btn_left(btn_l_db), .btn_right(btn_r_db),
        .game_active(game_active),
        
        // flick jump wiring
        .flick_jump_flag(flick_flag),
        .clear_flick_flag(flick_cleared_by_game),
        
        // Log carry wiring 
        .log_carry_en(log_carry_en),
        .log_carry_right(~qry_dir),
        .log_carry_speed(qry_speed),
        .chicken_x(chicken_x), .chicken_y(chicken_y),
        .logical_world_y(logical_world_y), .facing(chicken_facing),
        .is_moving(chicken_moving),
        .carried_offscreen(carried_offscreen)
    );
    
    camera_smoother cam_smooth_inst (
        .clk(game_clk), .rst(rst),
        .logical_y(logical_world_y), 
        .render_y(render_world_y)
    );

    camera_smoother smooth_chk_y (
        .clk(game_clk), .rst(rst),
        .logical_y(chicken_y), 
        .render_y(render_chicken_y)
    );
    
    camera_smoother smooth_chk_x (
        .clk(game_clk), .rst(rst),
        .logical_y(chicken_x), 
        .render_y(render_chicken_x)
    );
    //  Game state machine
    reg [10:0] prev_world_y;

    always @(posedge game_clk or negedge rst) begin
        if (!rst) begin
            game_started <= 0; game_over <= 0; btn_c_prev <= 0;
            score <= 0; high_score <= 0; lives <= 3'd3;
            prev_world_y <= 0; invuln_timer <= 0;
        end else begin
            btn_c_prev <= btn_c_db;

            if (!game_started) begin
                if (btn_c_rise) begin
                    game_started <= 1; game_over <= 0;
                    score <= 0; lives <= 3'd3; prev_world_y <= 0;
                    invuln_timer <= 0;
                end
            end else if (!game_over) begin
                
                if (invuln_timer > 0) invuln_timer <= invuln_timer - 1;

                if (logical_world_y != prev_world_y) begin
                    score <= score + 1;
                    if (score + 1 > high_score) high_score <= score + 1;
                    prev_world_y <= logical_world_y;
                end
                
                // Damage Handler
                if (take_damage) begin
                    if (lives > 1) begin
                        lives <= lives - 1;
                        invuln_timer <= 7'd120; // 2 seconds of safety
                    end else begin
                        lives <= 0;
                        game_over <= 1;
                    end
                end

            end else begin
                if (btn_c_rise) begin game_started <= 0; game_over <= 0; end
            end
        end
    end

    //  Drawing
    wire [3:0] draw_r, draw_g, draw_b;
    wire [10:0] curr_x, curr_y;

    drawcon drawcon_inst (
        .clk(pixclk), .rst(rst),
        .chicken_x(render_chicken_x), 
        .chicken_y(render_chicken_y), 
        .chicken_facing(chicken_facing), .chicken_moving(chicken_moving),
        .game_started(game_started), .game_over(game_over),
        .score(score), .lives(lives),
        .sprite_flash(sprite_flash), 

        .lane_type_0(lt0), .lane_type_1(lt1), .lane_type_2(lt2),
        .lane_type_3(lt3), .lane_type_4(lt4), .lane_type_5(lt5),
        
        .obs_x_0(ox0), .obs_x_1(ox1), .obs_x_2(ox2), 
        .obs_x_3(ox3), .obs_x_4(ox4), .obs_x_5(ox5),
        
        .obs2_x_0(o2x0), .obs2_x_1(o2x1), .obs2_x_2(o2x2), 
        .obs2_x_3(o2x3), .obs2_x_4(o2x4), .obs2_x_5(o2x5),
        
        .curr_x(curr_x), .curr_y(curr_y),
        .draw_r(draw_r), .draw_g(draw_g), .draw_b(draw_b)
    );

    //  VGA
    vga vga_inst (
        .clk(pixclk), .rst(rst),
        .draw_r(draw_r), .draw_g(draw_g), .draw_b(draw_b),
        .curr_x(curr_x), .curr_y(curr_y),
        .pix_r(pix_r), .pix_g(pix_g), .pix_b(pix_b),
        .hsync(hsync), .vsync(vsync)
    );

    // Score + LEDs
    score_display score_inst (
        .clk(sys_clk), .rst(rst),
        .score(score), .high_score(high_score),
        .seg(seg), .an(an)
    );

    assign led[7:0]   = score;
    assign led[8]     = (lives >= 3'd1);
    assign led[9]     = (lives >= 3'd2);
    assign led[10]    = (lives >= 3'd3);
    assign led[11]    = on_any_log;
    assign led[12]    = is_river;
    assign led[13]    = log_carry_en;
    assign led[14]    = qry_dir;
    assign led[15]    = game_over;

endmodule
