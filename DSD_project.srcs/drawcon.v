`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      drawcon.v
// Description: Render pipeline. Includes 3-bit lane types, Chasm rendering,
//              sprite flashing logic, and shifted 64px hit-test boundaries.
//////////////////////////////////////////////////////////////////////////////////

module drawcon (
    input             clk,
    input             rst,

    input      [10:0] chicken_x, chicken_y,
    input      [1:0]  chicken_facing,
    input             chicken_moving,

    input             game_started, game_over,
    input      [7:0]  score,
    input      [2:0]  lives,
    input             sprite_flash, 

    input      [2:0]  lane_type_0,  lane_type_1,  lane_type_2,
    input      [2:0]  lane_type_3,  lane_type_4,  lane_type_5,

    // Lane Directions needed for Car/Log Mirroring
    input             lane_dir_0, lane_dir_1, lane_dir_2,
    input             lane_dir_3, lane_dir_4, lane_dir_5,

    input      [10:0] obs_x_0,  obs_x_1,  obs_x_2,  obs_x_3,  obs_x_4,  obs_x_5,
    input      [10:0] obs2_x_0, obs2_x_1, obs2_x_2, obs2_x_3, obs2_x_4, obs2_x_5,

    input      [10:0] g0_x, g0_y, input g0_act, g0_scrd, input [2:0] g0_frame,
    input      [10:0] g1_x, g1_y, input g1_act, g1_scrd, input [2:0] g1_frame,
    input      [10:0] g2_x, g2_y, input g2_act, g2_scrd, input [2:0] g2_frame,

    input      [10:0] curr_x, curr_y,

    output reg [3:0]  draw_r, draw_g, draw_b
);

    localparam INFO_BAR_H = 11'd100;
    localparam CHK_W      = 11'd64; 
    localparam CHK_H      = 11'd64; 
    localparam CAR_W      = 11'd128; 
    localparam CAR_H      = 11'd64;
    localparam LOG_W      = 11'd192; 
    localparam LOG_H      = 11'd64;
    localparam GSE_W      = 11'd320; 
    localparam GSE_H      = 11'd64; 
    localparam SCREEN_W   = 11'd1440;

    localparam LANE_GRASS = 3'd0;
    localparam LANE_ROAD  = 3'd1;
    localparam LANE_RIVER = 3'd2;
    localparam LANE_START = 3'd3;
    localparam LANE_CHASM = 3'd4;

    wire in_game = (curr_y >= INFO_BAR_H) && (curr_y < INFO_BAR_H + 11'd768);
    wire [3:0] lane_idx = in_game ? ((curr_y - INFO_BAR_H) >> 7) : 4'd0;

    reg [2:0] lane_type;
    reg       act_lane_dir; // Holds the direction of the current lane
    
    always @(*) begin
        case (lane_idx)
            4'd0: begin lane_type=lane_type_0; act_lane_dir=lane_dir_0; end
            4'd1: begin lane_type=lane_type_1; act_lane_dir=lane_dir_1; end
            4'd2: begin lane_type=lane_type_2; act_lane_dir=lane_dir_2; end
            4'd3: begin lane_type=lane_type_3; act_lane_dir=lane_dir_3; end
            4'd4: begin lane_type=lane_type_4; act_lane_dir=lane_dir_4; end
            4'd5: begin lane_type=lane_type_5; act_lane_dir=lane_dir_5; end
            default: begin lane_type=LANE_GRASS; act_lane_dir=1'b0; end
        endcase
    end

    reg [10:0] o1x, o2x;
    always @(*) begin
        case (lane_idx)
            4'd0: begin o1x=obs_x_0;  o2x=obs2_x_0;  end
            4'd1: begin o1x=obs_x_1;  o2x=obs2_x_1;  end
            4'd2: begin o1x=obs_x_2;  o2x=obs2_x_2;  end
            4'd3: begin o1x=obs_x_3;  o2x=obs2_x_3;  end
            4'd4: begin o1x=obs_x_4;  o2x=obs2_x_4;  end
            4'd5: begin o1x=obs_x_5;  o2x=obs2_x_5;  end
            default: begin o1x=0; o2x=0; end
        endcase
    end

    wire [10:0] lane_top = INFO_BAR_H + (lane_idx << 7); 
    wire [10:0] obs_y0   = lane_top + 11'd32;
    wire        in_obs_y = (curr_y >= obs_y0) && (curr_y < obs_y0 + CAR_H);
    wire        is_active = (lane_type == LANE_ROAD) || (lane_type == LANE_RIVER);
    wire [10:0] obj_w    = (lane_type == LANE_RIVER) ? LOG_W : CAR_W;

    wire chk_in = (curr_x >= chicken_x) && (curr_x < chicken_x + CHK_W) &&
                  (curr_y >= chicken_y) && (curr_y < chicken_y + CHK_H);

    wire o1_in = in_game && in_obs_y && is_active &&
                 (curr_x >= o1x) && (curr_x < o1x + obj_w) && (o1x < SCREEN_W);

    wire o2_in = in_game && in_obs_y && is_active &&
                 (curr_x >= o2x) && (curr_x < o2x + obj_w) && (o2x < SCREEN_W);

    wire g0_in = g0_act && (curr_x >= g0_x) && (curr_x < g0_x + 11'd64) && (curr_y >= g0_y) && (curr_y < g0_y + GSE_H);
    wire g1_in = g1_act && (curr_x >= g1_x) && (curr_x < g1_x + 11'd64) && (curr_y >= g1_y) && (curr_y < g1_y + GSE_H);
    wire g2_in = g2_act && (curr_x >= g2_x) && (curr_x < g2_x + 11'd64) && (curr_y >= g2_y) && (curr_y < g2_y + GSE_H);

    wire any_goose_in = g0_in | g1_in | g2_in;


    // Goose logic, mirrors if player is to the right AND XORs if scared away by shout
    wire [2:0]  active_frame = g0_in ? g0_frame : (g1_in ? g1_frame : g2_frame);
    wire [10:0] active_gse_x = g0_in ? g0_x : (g1_in ? g1_x : g2_x);
    wire        active_gse_scrd = g0_in ? g0_scrd : (g1_in ? g1_scrd : g2_scrd); // Is THIS goose scared?
    
    wire [5:0] local_gse_col = curr_x - active_gse_x;
    
    // The XOR Gate (^): If chicken is to the right (1), face right. But if scared (1), 1^1 = 0 (face left)
    wire       gse_face_right = (chicken_x > active_gse_x) ^ active_gse_scrd; 
    wire [5:0] drawn_gse_col  = gse_face_right ? (6'd63 - local_gse_col) : local_gse_col;
    
    wire [8:0] gse_col = drawn_gse_col + (active_frame << 6); 
    wire [5:0] gse_row = g0_in ? (curr_y - g0_y) : g1_in ? (curr_y - g1_y) : (curr_y - g2_y);
    wire [14:0] gse_addr = (gse_row * 15'd320) + gse_col; 

    // player logic, mirrors based on player_ctrl facing state
    // Note: State 2'd3 is FACE_RIGHT in your player_ctrl
    wire [5:0] local_chk_col = curr_x - chicken_x;
    wire [5:0] drawn_chk_col = (chicken_facing == 2'd3) ? (6'd55 - local_chk_col) : local_chk_col;
    wire [5:0] chk_row = curr_y - chicken_y;
    wire [11:0] chk_addr = (chk_row * 12'd56) + drawn_chk_col;  

    // Car logic, mirrors if lane is flowing Right (0))
    wire [5:0] car_row_1 = curr_y - obs_y0;

    wire [6:0] local_car_col_1 = curr_x - o1x;
    wire [6:0] drawn_car_col_1 = (act_lane_dir == 1'b0) ? (7'd127 - local_car_col_1) : local_car_col_1;
    wire [12:0] car_addr_1 = {car_row_1, drawn_car_col_1}; 

    wire [6:0] local_car_col_2 = curr_x - o2x;
    wire [6:0] drawn_car_col_2 = (act_lane_dir == 1'b0) ? (7'd127 - local_car_col_2) : local_car_col_2;
    wire [12:0] car_addr_2 = {car_row_1, drawn_car_col_2};

    // log, mirrors if lane is flowing Right (0)) 
    wire [7:0] local_log_col_1 = curr_x - o1x;
    wire [7:0] drawn_log_col_1 = (act_lane_dir == 1'b0) ? (8'd191 - local_log_col_1) : local_log_col_1;
    wire [13:0] log_addr_1 = (car_row_1 * 14'd192) + drawn_log_col_1;

    wire [7:0] local_log_col_2 = curr_x - o2x;
    wire [7:0] drawn_log_col_2 = (act_lane_dir == 1'b0) ? (8'd191 - local_log_col_2) : local_log_col_2;
    wire [13:0] log_addr_2 = (car_row_1 * 14'd192) + drawn_log_col_2;

    wire [12:0] car_rom_addr = o1_in ? car_addr_1 : car_addr_2;
    wire [13:0] log_rom_addr = o1_in ? log_addr_1 : log_addr_2;

    // lane tiling
    wire [4:0] tile_col = curr_x[4:0]; 
    wire [6:0] tile_row = (curr_y - INFO_BAR_H); 
    wire [11:0] tile_addr = {tile_row, tile_col};

    // EXACT FILENAME BRAM INSTANTIATIONS
    wire [11:0] chk_pixel, car_pixel, log_pixel, gse_pixel;
    wire [11:0] road_pixel, chasm_pixel;

    sprite_rom #(.WIDTH(64), .HEIGHT(64), .MEM_FILE("chicken.mem")) chicken_rom (.clk(clk), .addr(chk_addr), .data(chk_pixel));
    sprite_rom #(.WIDTH(128), .HEIGHT(64), .MEM_FILE("car_128x64.mem")) car_rom (.clk(clk), .addr(car_rom_addr), .data(car_pixel));
    sprite_rom #(.WIDTH(192), .HEIGHT(64), .MEM_FILE("log_192x64.mem")) log_rom (.clk(clk), .addr(log_rom_addr), .data(log_pixel));
    
    sprite_rom #(.WIDTH(320), .HEIGHT(64), .MEM_FILE("goose_FINAL_320x64_444.mem")) goose_rom (.clk(clk), .addr(gse_addr), .data(gse_pixel));

    sprite_rom #(.WIDTH(32), .HEIGHT(128), .MEM_FILE("road_lane.mem")) road_rom (.clk(clk), .addr(tile_addr), .data(road_pixel));
    sprite_rom #(.WIDTH(32), .HEIGHT(128), .MEM_FILE("chasm_lane.mem")) chasm_rom (.clk(clk), .addr(tile_addr), .data(chasm_pixel));

    // Pipeline Registers
    reg chk_in_d, o1_in_d, o2_in_d, in_game_d, in_info_d;
    reg any_goose_in_d;
    reg [2:0] lane_type_d;
    reg [10:0] curr_y_d;
    reg [10:0] curr_x_d; 
    reg o1_log_d, o2_log_d;
    
    always @(posedge clk) begin
        chk_in_d       <= chk_in;
        o1_in_d        <= o1_in && (lane_type == LANE_ROAD);
        o2_in_d        <= o2_in && (lane_type == LANE_ROAD);
        o1_log_d       <= o1_in && (lane_type == LANE_RIVER);
        o2_log_d       <= o2_in && (lane_type == LANE_RIVER);
        any_goose_in_d <= any_goose_in;
        
        in_game_d      <= in_game;
        in_info_d      <= (curr_y < INFO_BAR_H);
        lane_type_d    <= lane_type;
        curr_y_d       <= curr_y;
        curr_x_d       <= curr_x;
    end

    wire chk_transparent = (chk_pixel == 12'h000) || (chk_pixel == 12'hF0F);
    wire car_transparent = (car_pixel == 12'h000) || (car_pixel == 12'hF0F);
    wire log_transparent = (log_pixel == 12'h000) || (log_pixel == 12'hF0F);
    wire gse_transparent = (gse_pixel == 12'h000) || (gse_pixel == 12'hF0F);

    wire [3:0] info_r, info_g, info_b;
    wire       in_info_bar;

    info_bar info_bar_inst (
        .curr_x(curr_x), .curr_y(curr_y),
        .score(score), .lives(lives), .game_over(game_over),
        .pixel_r(info_r), .pixel_g(info_g), .pixel_b(info_b),
        .in_info_bar(in_info_bar)
    );

    reg [3:0] info_r_d, info_g_d, info_b_d;
    always @(posedge clk) begin
        info_r_d <= info_r;
        info_g_d <= info_g;
        info_b_d <= info_b;
    end

    // Priority pixel mux
    // Selects the final RGB output for each pixel using a fixed priority order:
    // info bar > player sprite > logs > cars > geese > lane background.
    // Higher-priority layers override lower ones, implementing painter's-algorithm
    // style compositing without a framebuffer. Transparent sprites (F0F key) fall
    // through to the next layer rather than occluding it.
    always @(*) begin
        {draw_r, draw_g, draw_b} = 12'h000;

        if (in_info_d) begin
            {draw_r, draw_g, draw_b} = {info_r_d, info_g_d, info_b_d};

        end else if (chk_in_d && !chk_transparent && !sprite_flash) begin
            {draw_r, draw_g, draw_b} = game_over ? 12'hF44 : chk_pixel;

        end else if ((o1_log_d || o2_log_d) && !log_transparent) begin
            {draw_r, draw_g, draw_b} = log_pixel;

        end else if ((o1_in_d || o2_in_d) && !car_transparent) begin
            {draw_r, draw_g, draw_b} = car_pixel;

        end else if (any_goose_in_d && !gse_transparent) begin
            {draw_r, draw_g, draw_b} = gse_pixel;

        end else if (curr_y_d >= INFO_BAR_H + 11'd768) begin
            {draw_r, draw_g, draw_b} = 12'h000; 

        end else if (in_game_d) begin
            case (lane_type_d)
                LANE_GRASS: begin
                    if (curr_x_d[2]) {draw_r, draw_g, draw_b} = 12'h4A2;
                    else             {draw_r, draw_g, draw_b} = 12'h3A1;
                end
                
                LANE_ROAD:  {draw_r, draw_g, draw_b} = road_pixel;
                LANE_CHASM: {draw_r, draw_g, draw_b} = chasm_pixel;
                
                LANE_RIVER: begin
                    if (curr_x_d[3] ^ curr_y_d[2]) {draw_r, draw_g, draw_b} = 12'h26B;
                    else                           {draw_r, draw_g, draw_b} = 12'h37C;
                end
                
                LANE_START: begin 
                    if (curr_x_d[2]) {draw_r, draw_g, draw_b} = 12'h4A2;
                    else             {draw_r, draw_g, draw_b} = 12'h3A1;
                end
            endcase
        end
    end
endmodule
