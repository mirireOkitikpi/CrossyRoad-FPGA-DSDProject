`timescale 1ns / 1ps
// Module: drawcon.v
// Purpose: Display controller - computes the output RGB pixel for every (curr_x, curr_y)
//          scan position emitted by the VGA timing generator.  All sprite lookups go
//          through synchronous BRAM (sprite_rom), so every combinational hit/miss signal
//          is delayed by one pipeline register stage before it reaches the final mux so
//          that the mask bits and pixel data arrive at the output in the same clock cycle.
//
// Rendering order (highest priority first, painter's algorithm):
//   1. Game-over overlay (lava variant - death by chasm)
//   2. Game-over overlay (standard variant)
//   3. Info bar (score / lives / title - 100-pixel strip at top)
//   4. Feather debug pixel (pure white, covers everything below)
//   5. Scared (flying) geese - above all lane content so exit animation is unobscured
//   6. Player chicken sprite (suppressed during invulnerability / low-life flash)
//   7. Log obstacles (river lanes)
//   8. Car obstacles (road lanes)
//   9. Grounded geese (grass lanes only)
//  10. Lane background tile (grass, road BRAM, river BRAM, chasm BRAM, or solid black)
//
// Signed coordinate update:
//   chicken_x, obs_x_*, obs2_x_* are signed 12-bit to allow smooth off-screen
//   drifting without unsigned wrap-around artefacts.
//
// Goose grass-lane enforcement:
//   g*_in now requires lane_type == LANE_GRASS at the current scan position.
//   This means a goose that drifts onto a road/river/chasm lane becomes invisible
//   and its bounding box no longer fires any_goose_in, preventing phantom renders.
//   Collision and shout gating for geese on non-grass lanes is handled in game_top.v
//   via g*_valid flags derived from each goose's Y-position lane lookup.
//
// Authors: 2217321 & 2233381  (ES3B2 Digital Systems Design, University of Warwick)
// Target:  Nexys 4DDR - Artix-7 xc7a100tcsg324-1, Vivado 2024.1
// VGA:     1440x900 @ 60 Hz (~106.47 MHz pixel clock)

module drawcon (
    input             clk,
    input             rst,

    input             is_feather,

    // chicken_x is signed so the sprite can drift smoothly off either screen edge
    // without wrapping to a large positive value in unsigned arithmetic.
    input signed [11:0] chicken_x,
    input        [10:0] chicken_y,
    input      [1:0]  chicken_facing,   // 2'd2 = left (sprite mirrored); others = right
    input             chicken_moving,

    input             game_started, game_over,
    input             death_by_chasm,
    input      [1:0]  heart_frame,
    input      [7:0]  score,
    input      [2:0]  lives,
    input             sprite_flash,
    input             low_life_flash,

    input      [2:0]  lane_type_0,  lane_type_1,  lane_type_2,
    input      [2:0]  lane_type_3,  lane_type_4,  lane_type_5,

    // lane_dir: 0 = right-to-left, 1 = left-to-right.
    input             lane_dir_0, lane_dir_1, lane_dir_2,
    input             lane_dir_3, lane_dir_4, lane_dir_5,

    // Obstacle X positions are signed to allow smooth off-screen entry/exit.
    input signed [11:0] obs_x_0,  obs_x_1,  obs_x_2,  obs_x_3,  obs_x_4,  obs_x_5,
    input signed [11:0] obs2_x_0, obs2_x_1, obs2_x_2, obs2_x_3, obs2_x_4, obs2_x_5,

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


    // Lane index decode
    // Game area spans rows INFO_BAR_H to INFO_BAR_H+767.  Right-shift by 7 divides
    // the row offset by 128 (lane height) without a hardware divider.
    wire in_game   = (curr_y >= INFO_BAR_H) && (curr_y < INFO_BAR_H + 11'd768);
    wire [3:0] lane_idx = in_game ? ((curr_y - INFO_BAR_H) >> 7) : 4'd0;

    reg [2:0] lane_type;
    reg       act_lane_dir;

    always @(*) begin
        case (lane_idx)
            4'd0: begin lane_type = lane_type_0; act_lane_dir = lane_dir_0; end
            4'd1: begin lane_type = lane_type_1; act_lane_dir = lane_dir_1; end
            4'd2: begin lane_type = lane_type_2; act_lane_dir = lane_dir_2; end
            4'd3: begin lane_type = lane_type_3; act_lane_dir = lane_dir_3; end
            4'd4: begin lane_type = lane_type_4; act_lane_dir = lane_dir_4; end
            4'd5: begin lane_type = lane_type_5; act_lane_dir = lane_dir_5; end
            default: begin lane_type = LANE_GRASS; act_lane_dir = 1'b0; end
        endcase
    end

    // Internal obstacle X registers must also be signed so that signed subtraction
    // (s_curr_x - o1x) produces a correct negative result when the obstacle is
    // partially off the left edge of the screen.
    reg signed [11:0] o1x, o2x;
    always @(*) begin
        case (lane_idx)
            4'd0: begin o1x = obs_x_0;  o2x = obs2_x_0;  end
            4'd1: begin o1x = obs_x_1;  o2x = obs2_x_1;  end
            4'd2: begin o1x = obs_x_2;  o2x = obs2_x_2;  end
            4'd3: begin o1x = obs_x_3;  o2x = obs2_x_3;  end
            4'd4: begin o1x = obs_x_4;  o2x = obs2_x_4;  end
            4'd5: begin o1x = obs_x_5;  o2x = obs2_x_5;  end
            default: begin o1x = 0; o2x = 0; end
        endcase
    end

    wire [10:0] lane_top = INFO_BAR_H + (lane_idx << 7);  // lane_idx * 128
    wire [10:0] obs_y0   = lane_top + 11'd32;              // Vertically centred in 128-px lane
    wire        in_obs_y = (curr_y >= obs_y0) && (curr_y < obs_y0 + CAR_H);
    wire        is_active = (lane_type == LANE_ROAD) || (lane_type == LANE_RIVER);
    wire [10:0] obj_w    = (lane_type == LANE_RIVER) ? LOG_W : CAR_W;


    // Signed bounding-box hit tests
    // Casting curr_x to signed 12-bit (MSB = 0, always non-negative) allows
    // subtraction against signed obstacle/chicken positions without Verilog
    // treating the result as unsigned and losing the sign.
    //
    // A hit is valid when the signed horizontal offset (s_*_dx) is in [0, width):
    //   negative dx  → beam is left of the sprite's left edge (not yet entered)
    //   dx >= width  → beam has passed the sprite's right edge (already exited)
    wire signed [11:0] s_curr_x = {1'b0, curr_x};  // Zero-extend to signed 12-bit

    wire signed [11:0] s_chk_dx = s_curr_x - chicken_x;
    wire signed [11:0] s_o1_dx  = s_curr_x - o1x;
    wire signed [11:0] s_o2_dx  = s_curr_x - o2x;

    wire chk_in = (s_chk_dx >= 0) && (s_chk_dx < CHK_W) &&
                  (curr_y >= chicken_y) && (curr_y < chicken_y + CHK_H);

    wire o1_in = in_game && in_obs_y && is_active &&
                 (s_o1_dx >= 0) && (s_o1_dx < obj_w);

    wire o2_in = in_game && in_obs_y && is_active &&
                 (s_o2_dx >= 0) && (s_o2_dx < obj_w);

    // Goose AABB hit tests - two rendering modes:
    //
    // Grounded geese (g*_scrd == 0): the grass-lane gate is enforced.
    //   A grounded goose is only drawn when the VGA beam is sweeping a grass
    //   row. If the world scrolls and a grounded goose ends up over a road or
    //   river tile it becomes invisible, preventing phantom sprites on non-grass
    //   backgrounds. Collision/shout gating is handled in game_top via g*_valid.
    //
    // Scared / flying geese (g*_scrd == 1): the grass-lane gate is bypassed.
    //   Once scared, a goose flies upward and exits through whatever lane tiles
    //   happen to be beneath it. Removing the lane-type restriction allows the
    //   flying sprite to render over road, river, and chasm rows correctly.
    //   Scared geese have already been removed from collision logic in game_top
    //   (goose_manager only runs AABB checks on un-scared geese), so bypassing
    //   the gate here has no gameplay side-effects.
    wire g0_in = g0_act && (g0_scrd || (lane_type == LANE_GRASS)) &&
                 (curr_x >= g0_x) && (curr_x < g0_x + 11'd64) &&
                 (curr_y >= g0_y) && (curr_y < g0_y + GSE_H);
    wire g1_in = g1_act && (g1_scrd || (lane_type == LANE_GRASS)) &&
                 (curr_x >= g1_x) && (curr_x < g1_x + 11'd64) &&
                 (curr_y >= g1_y) && (curr_y < g1_y + GSE_H);
    wire g2_in = g2_act && (g2_scrd || (lane_type == LANE_GRASS)) &&
                 (curr_x >= g2_x) && (curr_x < g2_x + 11'd64) &&
                 (curr_y >= g2_y) && (curr_y < g2_y + GSE_H);

    // Split hit detection by scared state so the two cases can be placed at
    // different priority levels in the output mux.
    // scared_goose_in: flying geese - must render above lane backgrounds AND
    //   above road/log/car obstacles so the exit animation is never obscured.
    // grounded_goose_in: walking geese - rendered at the normal layer below
    //   obstacles, consistent with being on the ground.
    wire scared_goose_in   = (g0_in && g0_scrd) | (g1_in && g1_scrd) | (g2_in && g2_scrd);
    wire grounded_goose_in = (g0_in && !g0_scrd) | (g1_in && !g1_scrd) | (g2_in && !g2_scrd);
    wire any_goose_in      = scared_goose_in | grounded_goose_in;

    // Priority-select the first active goose for address computation (first-hit wins)
    wire [2:0]  active_frame    = g0_in ? g0_frame  : (g1_in ? g1_frame  : g2_frame);
    wire [10:0] active_gse_x    = g0_in ? g0_x      : (g1_in ? g1_x      : g2_x);
    wire        active_gse_scrd = g0_in ? g0_scrd   : (g1_in ? g1_scrd   : g2_scrd);


    // Goose ROM address: sheet is 320x64, five 64-px frames laid horizontally.
    // drawn_gse_col mirrors the column when the goose faces the player (XOR with scrd flag).
    // gse_col = mirrored_col + frame * 64; gse_addr = row * 320 + col.
    wire [5:0] local_gse_col = curr_x - active_gse_x;
    wire       gse_face_right = (chicken_x > active_gse_x) ^ active_gse_scrd;
    wire [5:0] drawn_gse_col  = gse_face_right ? (6'd63 - local_gse_col) : local_gse_col;
    wire [8:0] gse_col        = drawn_gse_col + (active_frame << 6);
    wire [5:0] gse_row        = g0_in ? (curr_y - g0_y) : g1_in ? (curr_y - g1_y) : (curr_y - g2_y);
    wire [14:0] gse_addr      = (gse_row * 15'd320) + gse_col;


    // Chicken ROM address: 64x64 sprite.
    // local_chk_col taken from s_chk_dx[5:0] - safe because chk_in guarantees
    // dx is in [0, 63] whenever this value feeds a BRAM address.
    // Facing left (chicken_facing == 2'd2) mirrors by subtracting the column from 63.
    wire [5:0] local_chk_col = s_chk_dx[5:0];
    wire [5:0] drawn_chk_col = (chicken_facing == 2'd2) ? (6'd63 - local_chk_col) : local_chk_col;
    wire [5:0] chk_row       = curr_y - chicken_y;
    wire [11:0] chk_addr     = (chk_row * 12'd64) + drawn_chk_col;


    // Car / log ROM address calculation
    // Direction mirroring: act_lane_dir == 0 → sprites travel right-to-left, so the
    // column is mirrored to keep headlights facing the direction of travel.
    // Car: {6-bit row, 7-bit col} = 13-bit flat index for 128x64 ROM.
    // Log: row * 192 + col (192 is not a power of two, concatenation not valid here).
    wire [5:0] car_row_1 = curr_y - obs_y0;

    wire [6:0] local_car_col_1  = s_o1_dx[6:0];
    wire [6:0] drawn_car_col_1  = (act_lane_dir == 1'b0) ? (7'd127 - local_car_col_1) : local_car_col_1;
    wire [12:0] car_addr_1      = {car_row_1, drawn_car_col_1};

    wire [6:0] local_car_col_2  = s_o2_dx[6:0];
    wire [6:0] drawn_car_col_2  = (act_lane_dir == 1'b0) ? (7'd127 - local_car_col_2) : local_car_col_2;
    wire [12:0] car_addr_2      = {car_row_1, drawn_car_col_2};

    wire [7:0] local_log_col_1  = s_o1_dx[7:0];
    wire [7:0] drawn_log_col_1  = (act_lane_dir == 1'b0) ? (8'd191 - local_log_col_1) : local_log_col_1;
    wire [13:0] log_addr_1      = (car_row_1 * 14'd192) + drawn_log_col_1;

    wire [7:0] local_log_col_2  = s_o2_dx[7:0];
    wire [7:0] drawn_log_col_2  = (act_lane_dir == 1'b0) ? (8'd191 - local_log_col_2) : local_log_col_2;
    wire [13:0] log_addr_2      = (car_row_1 * 14'd192) + drawn_log_col_2;

    wire [12:0] car_rom_addr = o1_in ? car_addr_1 : car_addr_2;
    wire [13:0] log_rom_addr = o1_in ? log_addr_1 : log_addr_2;


    // Background tile ROM addresses
    // Road/chasm tiles are 32x128: curr_x[4:0] gives column mod 32 by bit-select.
    // River tile is 128x128: curr_x[6:0] gives column mod 128.
    wire [4:0]  tile_col  = curr_x[4:0];
    wire [6:0]  tile_row  = (curr_y - INFO_BAR_H);
    wire [11:0] tile_addr = {tile_row, tile_col};

    wire [6:0]  river_col  = curr_x[6:0];
    wire [6:0]  river_row  = tile_row[6:0];
    wire [13:0] river_addr = {river_row, river_col};


    // Game-over overlay geometry (2x integer upscale, no framebuffer)
    // Each screen pixel maps back to ROM pixel (screen_offset >> 1).

    // Standard game-over: ROM 570x145 displayed as 1140x290, left margin 150 px.
    wire in_go_std = game_over && !death_by_chasm &&
                     (curr_x >= 11'd150) && (curr_x < 11'd1290) &&
                     (curr_y >= 11'd305) && (curr_y < 11'd595);
    wire [9:0]  go_std_x    = (curr_x - 11'd150) >> 1;
    wire [9:0]  go_std_y    = (curr_y - 11'd305) >> 1;
    // Max addr = 144 * 570 + 569 = 82,649 - fits in 17 bits.
    wire [16:0] go_std_addr = (go_std_y * 17'd570) + go_std_x;

    // Lava game-over: ROM 200x425 displayed as 400x850, left margin 520 px.
    wire in_go_lava = game_over && death_by_chasm &&
                      (curr_x >= 11'd520) && (curr_x < 11'd920) &&
                      (curr_y >= 11'd25)  && (curr_y < 11'd875);
    wire [9:0]  go_lava_x    = (curr_x - 11'd520) >> 1;
    wire [9:0]  go_lava_y    = (curr_y - 11'd25)  >> 1;
    // Max addr = 424 * 200 + 199 = 84,999 - fits in 17 bits.
    wire [16:0] go_lava_addr = (go_lava_y * 17'd200) + go_lava_x;


    // BRAM sprite ROM instantiations
    // All ROMs output 12-bit R4G4B4; magenta (12'hF0F) is the transparency key.
    wire [11:0] chk_pixel, car_pixel, log_pixel, gse_pixel;
    wire [11:0] road_pixel, river_pixel, chasm_pixel;
    wire [11:0] go_std_pixel, go_lava_pixel;

    sprite_rom #(.WIDTH(570),  .HEIGHT(145), .MEM_FILE("game_over_screen.mem"))      go_std_rom  (.clk(clk), .addr(go_std_addr),  .data(go_std_pixel));
    sprite_rom #(.WIDTH(200),  .HEIGHT(425), .MEM_FILE("fried_chicken_bucket.mem"))  go_lava_rom (.clk(clk), .addr(go_lava_addr), .data(go_lava_pixel));
    sprite_rom #(.WIDTH(64),   .HEIGHT(64),  .MEM_FILE("chick.mem"))                 chicken_rom (.clk(clk), .addr(chk_addr),     .data(chk_pixel));
    sprite_rom #(.WIDTH(128),  .HEIGHT(64),  .MEM_FILE("car_128x64.mem"))            car_rom     (.clk(clk), .addr(car_rom_addr), .data(car_pixel));
    sprite_rom #(.WIDTH(192),  .HEIGHT(64),  .MEM_FILE("log_192x64.mem"))            log_rom     (.clk(clk), .addr(log_rom_addr), .data(log_pixel));
    sprite_rom #(.WIDTH(320),  .HEIGHT(64),  .MEM_FILE("goose_FINAL_320x64_444.mem"))goose_rom   (.clk(clk), .addr(gse_addr),     .data(gse_pixel));
    sprite_rom #(.WIDTH(32),   .HEIGHT(128), .MEM_FILE("road_lane.mem"))             road_rom    (.clk(clk), .addr(tile_addr),    .data(road_pixel));
    sprite_rom #(.WIDTH(128),  .HEIGHT(128), .MEM_FILE("water.mem"))                 river_rom   (.clk(clk), .addr(river_addr),   .data(river_pixel));
    sprite_rom #(.WIDTH(32),   .HEIGHT(128), .MEM_FILE("chasm_lane.mem"))            chasm_rom   (.clk(clk), .addr(tile_addr),    .data(chasm_pixel));


    // Pipeline delay registers (1-cycle BRAM read latency compensation)
    // All combinational hit/mask signals are registered here so that when the BRAM
    // outputs the pixel on the next clock edge the corresponding hit flag has also
    // advanced by one cycle and the two signals are aligned in the output mux.
    //
    // The road/river split is baked in at registration time (o1_in_d vs o1_log_d)
    // to avoid routing lane_type through the critical path in the output mux.
    //
    // in_go_lava_d / in_go_std_d fix the 1-cycle left-edge artefact: at the first
    // pixel of the overlay region the BRAM was addressed one cycle earlier with an
    // underflowing address, producing a garbage pixel. Delaying the enable by one
    // cycle aligns it with the valid BRAM output at the next pixel position.
    reg chk_in_d, o1_in_d, o2_in_d, in_game_d, in_info_d;
    reg scared_goose_in_d;    // Flying geese - rendered above lane backgrounds
    reg grounded_goose_in_d;  // Walking geese - rendered below obstacles
    reg [2:0]  lane_type_d;
    reg [10:0] curr_y_d;
    reg [10:0] curr_x_d;
    reg        o1_log_d, o2_log_d;
    reg        low_life_flash_d;
    reg        in_go_lava_d;
    reg        in_go_std_d;

    always @(posedge clk) begin
        chk_in_d         <= chk_in;
        o1_in_d          <= o1_in && (lane_type == LANE_ROAD);
        o2_in_d          <= o2_in && (lane_type == LANE_ROAD);
        o1_log_d         <= o1_in && (lane_type == LANE_RIVER);
        o2_log_d         <= o2_in && (lane_type == LANE_RIVER);
        scared_goose_in_d   <= scared_goose_in;
        grounded_goose_in_d <= grounded_goose_in;
        in_game_d        <= in_game;
        in_info_d        <= (curr_y < INFO_BAR_H);
        lane_type_d      <= lane_type;
        curr_y_d         <= curr_y;
        curr_x_d         <= curr_x;
        low_life_flash_d <= low_life_flash;
        in_go_lava_d     <= in_go_lava;
        in_go_std_d      <= in_go_std;
    end


    // Transparency checks
    // Magenta (F0F) is the universal transparency key in all .mem files.
    // Car and log ROMs also treat black (000) as transparent to handle unpainted entries.
    wire chk_transparent = (chk_pixel == 12'hF0F);
    wire car_transparent = (car_pixel == 12'h000) || (car_pixel == 12'hF0F);
    wire log_transparent = (log_pixel == 12'h000) || (log_pixel == 12'hF0F);
    wire gse_transparent = (gse_pixel == 12'h000) || (gse_pixel == 12'hF0F);


    // Info bar submodule
    wire [3:0] info_r, info_g, info_b;
    wire       in_info_bar;

    info_bar info_bar_inst (
        .clk(clk),
        .curr_x(curr_x), .curr_y(curr_y),
        .score(score), .lives(lives), .game_over(game_over),
        .heart_frame(heart_frame),
        .pixel_r(info_r), .pixel_g(info_g), .pixel_b(info_b),
        .in_info_bar(in_info_bar)
    );

    reg [3:0] info_r_d, info_g_d, info_b_d;
    always @(posedge clk) begin
        info_r_d <= info_r;
        info_g_d <= info_g;
        info_b_d <= info_b;
    end


    // Chicken visibility
    // hide_chicken suppresses the sprite during the invulnerability window only.
    // low_life_flash is retained as an input for future use but no longer hides
    // the chicken - the one-life warning is conveyed by the HUD alone.
    wire hide_chicken     = sprite_flash;
    wire chk_layer_active = chk_in_d && !hide_chicken && !chk_transparent;


    // Priority pixel multiplexer (painter's algorithm, combinational)
    always @(*) begin
        {draw_r, draw_g, draw_b} = 12'h000;

        if (in_go_lava_d && go_lava_pixel != 12'hF0F) begin
            {draw_r, draw_g, draw_b} = go_lava_pixel;
        end else if (in_go_std_d && go_std_pixel != 12'hF0F) begin
            {draw_r, draw_g, draw_b} = go_std_pixel;
        end else if (in_info_d) begin
            {draw_r, draw_g, draw_b} = {info_r_d, info_g_d, info_b_d};
        // Layer 4: Feather debug pixel
        end else if (is_feather) begin
            {draw_r, draw_g, draw_b} = 12'hFFF;

        // Layer 5: Scared (flying) geese - above the chicken so the exit animation
        //   is never hidden by lane backgrounds, cars, or logs.  A goose that has
        //   been scared flies upward through whatever tiles happen to be beneath it;
        //   enforcing a lane-type check here would cause it to flicker or vanish.
        end else if (scared_goose_in_d && !gse_transparent) begin
            {draw_r, draw_g, draw_b} = gse_pixel;

        // Layer 6: Player chicken sprite (suppressed during flash states)
        end else if (chk_layer_active) begin
            {draw_r, draw_g, draw_b} = chk_pixel;

        // Layer 7: Log obstacles (river lanes)
        end else if ((o1_log_d || o2_log_d) && !log_transparent) begin
            {draw_r, draw_g, draw_b} = log_pixel;

        // Layer 8: Car obstacles (road lanes)
        end else if ((o1_in_d || o2_in_d) && !car_transparent) begin
            {draw_r, draw_g, draw_b} = car_pixel;

        // Layer 9: Grounded geese - below obstacles, standing on grass
        end else if (grounded_goose_in_d && !gse_transparent) begin
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
                LANE_RIVER: {draw_r, draw_g, draw_b} = river_pixel;
                LANE_START: begin
                    if (curr_x_d[2]) {draw_r, draw_g, draw_b} = 12'h4A2;
                    else             {draw_r, draw_g, draw_b} = 12'h3A1;
                end
            endcase
        end
    end

endmodule
