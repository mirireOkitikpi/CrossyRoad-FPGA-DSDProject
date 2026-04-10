`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      drawcon.v (v3 - BRAM sprite rendering)
// Description:
//   Renders sprites from Block RAM ROMs instead of coloured rectangles.
//   Uses sprite_rom module with $readmemh for automatic BRAM inference.
//
//   BRAM has 1-cycle read latency: address presented on cycle N, data
//   available on cycle N+1. We pipeline the hit-test signals by 1 cycle
//   to match. The result is a 1-pixel horizontal shift which is
//   invisible at 1440px width.
//
//   Sprites:
//     - Chicken (32×32) - player character
//     - Car (64×32)     - road obstacle
//     - Log (128×32)    - river platform
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

    input      [1:0]  lane_type_0,  lane_type_1,  lane_type_2,
    input      [1:0]  lane_type_3,  lane_type_4,  lane_type_5,
    input      [1:0]  lane_type_6,  lane_type_7,  lane_type_8,
    input      [1:0]  lane_type_9,  lane_type_10, lane_type_11,
    input      [1:0]  lane_type_12, lane_type_13,

    input      [10:0] obs_x_0,  obs_x_1,  obs_x_2,  obs_x_3,
    input      [10:0] obs_x_4,  obs_x_5,  obs_x_6,  obs_x_7,
    input      [10:0] obs_x_8,  obs_x_9,  obs_x_10, obs_x_11,
    input      [10:0] obs_x_12, obs_x_13,

    input      [10:0] obs2_x_0,  obs2_x_1,  obs2_x_2,  obs2_x_3,
    input      [10:0] obs2_x_4,  obs2_x_5,  obs2_x_6,  obs2_x_7,
    input      [10:0] obs2_x_8,  obs2_x_9,  obs2_x_10, obs2_x_11,
    input      [10:0] obs2_x_12, obs2_x_13,

    input      [10:0] curr_x, curr_y,

    output reg [3:0]  draw_r, draw_g, draw_b
);

    localparam INFO_BAR_H = 11'd100;
    localparam LANE_H     = 11'd57;
    localparam CHK_W      = 11'd32;
    localparam CHK_H      = 11'd32;
    localparam CAR_W      = 11'd64;
    localparam CAR_H      = 11'd32;
    localparam LOG_W      = 11'd128;
    localparam LOG_H      = 11'd32;
    localparam SCREEN_W   = 11'd1440;

    localparam LANE_GRASS = 2'd0;
    localparam LANE_ROAD  = 2'd1;
    localparam LANE_RIVER = 2'd2;
    localparam LANE_START = 2'd3;

    // ══════════════════════════════════════════════════════════
    // Lane determination for current scan line
    // ══════════════════════════════════════════════════════════
    wire in_game = (curr_y >= INFO_BAR_H);
    wire [3:0] lane_idx = in_game ? (curr_y - INFO_BAR_H) / LANE_H : 4'd0;

    reg [1:0] lane_type;
    always @(*) begin
        case (lane_idx)
            4'd0: lane_type=lane_type_0;  4'd1: lane_type=lane_type_1;
            4'd2: lane_type=lane_type_2;  4'd3: lane_type=lane_type_3;
            4'd4: lane_type=lane_type_4;  4'd5: lane_type=lane_type_5;
            4'd6: lane_type=lane_type_6;  4'd7: lane_type=lane_type_7;
            4'd8: lane_type=lane_type_8;  4'd9: lane_type=lane_type_9;
            4'd10:lane_type=lane_type_10; 4'd11:lane_type=lane_type_11;
            4'd12:lane_type=lane_type_12; 4'd13:lane_type=lane_type_13;
            default: lane_type = LANE_GRASS;
        endcase
    end

    // Obstacle X muxes
    reg [10:0] o1x, o2x;
    always @(*) begin
        case (lane_idx)
            4'd0: begin o1x=obs_x_0;  o2x=obs2_x_0;  end
            4'd1: begin o1x=obs_x_1;  o2x=obs2_x_1;  end
            4'd2: begin o1x=obs_x_2;  o2x=obs2_x_2;  end
            4'd3: begin o1x=obs_x_3;  o2x=obs2_x_3;  end
            4'd4: begin o1x=obs_x_4;  o2x=obs2_x_4;  end
            4'd5: begin o1x=obs_x_5;  o2x=obs2_x_5;  end
            4'd6: begin o1x=obs_x_6;  o2x=obs2_x_6;  end
            4'd7: begin o1x=obs_x_7;  o2x=obs2_x_7;  end
            4'd8: begin o1x=obs_x_8;  o2x=obs2_x_8;  end
            4'd9: begin o1x=obs_x_9;  o2x=obs2_x_9;  end
            4'd10:begin o1x=obs_x_10; o2x=obs2_x_10; end
            4'd11:begin o1x=obs_x_11; o2x=obs2_x_11; end
            4'd12:begin o1x=obs_x_12; o2x=obs2_x_12; end
            4'd13:begin o1x=obs_x_13; o2x=obs2_x_13; end
            default: begin o1x=0; o2x=0; end
        endcase
    end

    // ══════════════════════════════════════════════════════════
    // Sprite hit tests (combinational, cycle N)
    // ══════════════════════════════════════════════════════════

    // Obstacle vertical band
    wire [10:0] lane_top = INFO_BAR_H + lane_idx * LANE_H;
    wire [10:0] obs_y0   = lane_top + 11'd12;
    wire        in_obs_y = (curr_y >= obs_y0) && (curr_y < obs_y0 + CAR_H);
    wire        is_active = (lane_type == LANE_ROAD) || (lane_type == LANE_RIVER);
    wire [10:0] obj_w    = (lane_type == LANE_RIVER) ? LOG_W : CAR_W;

    // Chicken
    wire chk_in = (curr_x >= chicken_x) && (curr_x < chicken_x + CHK_W) &&
                  (curr_y >= chicken_y) && (curr_y < chicken_y + CHK_H);

    // Obstacle 1
    wire o1_in = in_game && in_obs_y && is_active &&
                 (curr_x >= o1x) && (curr_x < o1x + obj_w) && (o1x < SCREEN_W);

    // Obstacle 2
    wire o2_in = in_game && in_obs_y && is_active &&
                 (curr_x >= o2x) && (curr_x < o2x + obj_w) && (o2x < SCREEN_W);

    // ══════════════════════════════════════════════════════════
    // Sprite ROM address computation (cycle N)
    // ══════════════════════════════════════════════════════════

    // Chicken address: (row * 32) + col
    wire [4:0] chk_col = curr_x - chicken_x;
    wire [4:0] chk_row = curr_y - chicken_y;
    wire [9:0] chk_addr = {chk_row, chk_col};  // 5+5 = 10 bits for 32×32

    // Car address: (row * 64) + col
    wire [5:0] car_col_1 = curr_x - o1x;
    wire [4:0] car_row_1 = curr_y - obs_y0;
    wire [10:0] car_addr_1 = {car_row_1, car_col_1};

    wire [5:0] car_col_2 = curr_x - o2x;
    wire [10:0] car_addr_2 = {car_row_1, car_col_2};

    // Log address: (row * 128) + col
    wire [6:0] log_col_1 = curr_x - o1x;
    wire [6:0] log_col_2 = curr_x - o2x;
    wire [11:0] log_addr_1 = {car_row_1, log_col_1};
    wire [11:0] log_addr_2 = {car_row_1, log_col_2};

    // Select which address to feed to each ROM
    // Car ROM: use obs1 address if obs1 is active, else obs2
    wire [10:0] car_rom_addr = o1_in ? car_addr_1 : car_addr_2;

    // Log ROM: use obs1 address if obs1 is active, else obs2
    wire [11:0] log_rom_addr = o1_in ? log_addr_1 : log_addr_2;

    // ══════════════════════════════════════════════════════════
    // Sprite ROM instantiations
    // ══════════════════════════════════════════════════════════

    wire [11:0] chk_pixel;
    sprite_rom #(.WIDTH(32), .HEIGHT(32), .MEM_FILE("C:/Users/mirir/OneDrive/Documents/Warwick Engineering/3rd Year/ES3B2 Digital System Design/DSD_project/coe/chicken_up.mem")) chicken_rom (
        .clk(clk), .addr(chk_addr), .data(chk_pixel)
    );

    wire [11:0] car_pixel;
    sprite_rom #(.WIDTH(64), .HEIGHT(32), .MEM_FILE("C:/Users/mirir/OneDrive/Documents/Warwick Engineering/3rd Year/ES3B2 Digital System Design/DSD_project/coe/car_red.mem")) car_rom (
        .clk(clk), .addr(car_rom_addr), .data(car_pixel)
    );

    wire [11:0] log_pixel;
    sprite_rom #(.WIDTH(128), .HEIGHT(32), .MEM_FILE("C:/Users/mirir/OneDrive/Documents/Warwick Engineering/3rd Year/ES3B2 Digital System Design/DSD_project/coe/log.mem")) log_rom (
        .clk(clk), .addr(log_rom_addr), .data(log_pixel)
    );

    // ══════════════════════════════════════════════════════════
    // Pipeline: delay hit-test signals by 1 cycle to match BRAM latency
    // ══════════════════════════════════════════════════════════

    reg chk_in_d, o1_in_d, o2_in_d, in_game_d, in_info_d;
    reg [1:0] lane_type_d;
    reg [10:0] curr_x_d, curr_y_d;
    reg lane_border_d;

    wire lane_border = in_game && (((curr_y - INFO_BAR_H) % LANE_H) < 2);
    wire road_dash = (curr_x[4] == 1'b0);

    reg road_dash_d;

    always @(posedge clk) begin
        chk_in_d     <= chk_in;
        o1_in_d      <= o1_in && (lane_type == LANE_ROAD);
        o2_in_d      <= o2_in && (lane_type == LANE_ROAD);
        in_game_d    <= in_game;
        in_info_d    <= (curr_y < INFO_BAR_H);
        lane_type_d  <= lane_type;
        curr_x_d     <= curr_x;
        curr_y_d     <= curr_y;
        lane_border_d <= lane_border;
        road_dash_d  <= road_dash;
    end

    // Log hit delayed
    reg o1_log_d, o2_log_d;
    always @(posedge clk) begin
        o1_log_d <= o1_in && (lane_type == LANE_RIVER);
        o2_log_d <= o2_in && (lane_type == LANE_RIVER);
    end

    // Transparency check (000 = transparent)
    wire chk_transparent = (chk_pixel == 12'h000);
    wire car_transparent = (car_pixel == 12'h000);
    wire log_transparent = (log_pixel == 12'h000);

    // ══════════════════════════════════════════════════════════
    // Info bar
    // ══════════════════════════════════════════════════════════
    wire [3:0] info_r, info_g, info_b;
    wire       in_info_bar;

    info_bar info_bar_inst (
        .curr_x(curr_x), .curr_y(curr_y),
        .score(score), .lives(lives), .game_over(game_over),
        .pixel_r(info_r), .pixel_g(info_g), .pixel_b(info_b),
        .in_info_bar(in_info_bar)
    );

    // Pipeline info bar output by 1 cycle to match BRAM delay
    reg [3:0] info_r_d, info_g_d, info_b_d;
    always @(posedge clk) begin
        info_r_d <= info_r;
        info_g_d <= info_g;
        info_b_d <= info_b;
    end

    // ══════════════════════════════════════════════════════════
    // Priority mux (uses delayed signals, cycle N+1)
    // ══════════════════════════════════════════════════════════
    always @(*) begin
        {draw_r, draw_g, draw_b} = 12'h000;

        // Layer 0: Info bar
        if (in_info_d) begin
            {draw_r, draw_g, draw_b} = {info_r_d, info_g_d, info_b_d};

        // Layer 1: Chicken sprite
        end else if (chk_in_d && !chk_transparent) begin
            if (game_over)
                {draw_r, draw_g, draw_b} = 12'hF44;  // Red tint when dead
            else
                {draw_r, draw_g, draw_b} = chk_pixel;

        // Layer 2: Log sprites (on river lanes)
        end else if ((o1_log_d || o2_log_d) && !log_transparent) begin
            {draw_r, draw_g, draw_b} = log_pixel;

        // Layer 3: Car sprites (on road lanes)
        end else if ((o1_in_d || o2_in_d) && !car_transparent) begin
            {draw_r, draw_g, draw_b} = car_pixel;

        // Layer 4: Lane backgrounds
        end else if (in_game_d) begin
            case (lane_type_d)
                LANE_GRASS: begin
                    if (curr_x_d[2]) {draw_r, draw_g, draw_b} = 12'h4A2;
                    else             {draw_r, draw_g, draw_b} = 12'h3A1;
                end
                LANE_ROAD: begin
                    {draw_r, draw_g, draw_b} = 12'h555;
                    if (lane_border_d && road_dash_d)
                        {draw_r, draw_g, draw_b} = 12'hEEB;
                end
                LANE_RIVER: begin
                    if (curr_x_d[3] ^ curr_y_d[2])
                        {draw_r, draw_g, draw_b} = 12'h26B;
                    else
                        {draw_r, draw_g, draw_b} = 12'h37C;
                end
                LANE_START: {draw_r, draw_g, draw_b} = 12'h5B3;
            endcase

            if (lane_border_d && lane_type_d != LANE_RIVER)
                {draw_r, draw_g, draw_b} = 12'h222;
        end
    end

endmodule
