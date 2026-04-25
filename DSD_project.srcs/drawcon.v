`timescale 1ns / 1ps
// Module: drawcon.v
// Purpose: Display controller — computes the output RGB pixel for every (curr_x, curr_y)
//          scan position emitted by the VGA timing generator.  All sprite lookups go
//          through synchronous BRAM (sprite_rom), so every combinational hit/miss signal
//          is delayed by one pipeline register stage before it reaches the final mux so
//          that the mask bits and pixel data arrive at the output in the same clock cycle.
//
// Rendering order (highest priority first, painter's algorithm):
//   1. Game-over overlay (lava variant — death by chasm)
//   2. Game-over overlay (standard variant)
//   3. Info bar (score / lives / title — 100-pixel strip at top)
//   4. Feather debug pixel (pure white, covers everything below)
//   5. Player chicken sprite (suppressed during invulnerability / low-life flash)
//   6. Log obstacles (river lanes)
//   7. Car obstacles (road lanes)
//   8. Goose enemies
//   9. Lane background tile (grass, road BRAM, river BRAM, chasm BRAM, or solid black)
//
// Authors: 2217321 & 2233381  (ES3B2 Digital Systems Design, University of Warwick)
// Target:  Nexys 4DDR — Artix-7 xc7a100tcsg324-1, Vivado 2024.1
// VGA:     1440x900 @ 60 Hz (~106.47 MHz pixel clock), info bar occupies rows 0-99,
//          game area occupies rows 100-867 (768 px = 6 lanes x 128 px each).

module drawcon (
    input             clk,
    input             rst,

    // Set high for exactly one pixel clock when the scan position coincides with
    // a collected feather power-up; renders a white pixel for debug/visual feedback.
    input             is_feather,

    // Player chicken: top-left pixel position, directional facing (2-bit), move flag.
    input      [10:0] chicken_x, chicken_y,
    input      [1:0]  chicken_facing,   // 2'd2 = left (sprite mirrored); others = right
    input             chicken_moving,

    // Game state flags used to gate overlay rendering and chicken flash logic.
    input             game_started, game_over,
    input             death_by_chasm,   // Selects lava vs standard game-over overlay

    // Info bar animation / HUD inputs.
    input      [1:0]  heart_frame,      // Selects one of 4 heart animation frames
    input      [7:0]  score,
    input      [2:0]  lives,

    // sprite_flash: toggled rapidly after a collision (invulnerability period) — hides chicken.
    // low_life_flash: ~1 Hz toggle driven by game_top when lives == 1 — warns the player.
    input             sprite_flash,
    input             low_life_flash,

    // Per-lane type: encodes background tile and obstacle class (see localparams below).
    input      [2:0]  lane_type_0,  lane_type_1,  lane_type_2,
    input      [2:0]  lane_type_3,  lane_type_4,  lane_type_5,

    // Per-lane scroll direction: 0 = right-to-left, 1 = left-to-right.
    // Used to mirror obstacle sprites so they always face their direction of travel.
    input             lane_dir_0, lane_dir_1, lane_dir_2,
    input             lane_dir_3, lane_dir_4, lane_dir_5,

    // Obstacle X positions: each lane has two independent obstacles (o1, o2).
    // Values >= SCREEN_W indicate the obstacle is off-screen and must not be drawn.
    input      [10:0] obs_x_0,  obs_x_1,  obs_x_2,  obs_x_3,  obs_x_4,  obs_x_5,
    input      [10:0] obs2_x_0, obs2_x_1, obs2_x_2, obs2_x_3, obs2_x_4, obs2_x_5,

    // Three goose enemy instances: position, active flag, scored flag, animation frame.
    // g*_scrd flips the horizontal orientation so a goose that has scored faces away.
    input      [10:0] g0_x, g0_y, input g0_act, g0_scrd, input [2:0] g0_frame,
    input      [10:0] g1_x, g1_y, input g1_act, g1_scrd, input [2:0] g1_frame,
    input      [10:0] g2_x, g2_y, input g2_act, g2_scrd, input [2:0] g2_frame,

    // Current VGA scan pixel — driven directly from the VGA timing generator.
    input      [10:0] curr_x, curr_y,

    // 4-bit-per-channel RGB pixel output (R4G4B4 = 12 bits total, matches sprite_rom format).
    output reg [3:0]  draw_r, draw_g, draw_b
);

    // Sprite and screen geometry (all in pixels).
    localparam INFO_BAR_H = 11'd100;   // Rows 0-99 reserved for the HUD info bar
    localparam CHK_W      = 11'd64;    // Chicken sprite width
    localparam CHK_H      = 11'd64;    // Chicken sprite height
    localparam CAR_W      = 11'd128;   // Car/road obstacle width
    localparam CAR_H      = 11'd64;    // Car/road obstacle height (also used for logs)
    localparam LOG_W      = 11'd192;   // Log/river obstacle width
    localparam LOG_H      = 11'd64;
    localparam GSE_W      = 11'd320;   // Goose sprite sheet width (5 frames × 64 px)
    localparam GSE_H      = 11'd64;    // Goose sprite height
    localparam SCREEN_W   = 11'd1440;  // Horizontal resolution

    // Lane type encoding — must match lane_manager.v constants.
    localparam LANE_GRASS = 3'd0;
    localparam LANE_ROAD  = 3'd1;
    localparam LANE_RIVER = 3'd2;
    localparam LANE_START = 3'd3;  // Safe starting lane, rendered identically to grass
    localparam LANE_CHASM = 3'd4;


    // Lane index decode
    // The game area spans INFO_BAR_H to INFO_BAR_H+767 (768 px, 6 lanes).
    // Each lane is 128 px tall, so right-shifting by 7 divides by 128 without a divider.
    wire in_game   = (curr_y >= INFO_BAR_H) && (curr_y < INFO_BAR_H + 11'd768);
    wire [3:0] lane_idx = in_game ? ((curr_y - INFO_BAR_H) >> 7) : 4'd0;

    // Unpack the flat per-lane ports into scalars for the active lane.
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

    // Obstacle X lookup for the active lane.
    reg [10:0] o1x, o2x;
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


    // Obstacle bounding-box hit tests
    // Obstacles are vertically centred within their 128-px lane: top of lane + 32 px
    // gives a 64-px band that matches CAR_H / LOG_H.
    wire [10:0] lane_top  = INFO_BAR_H + (lane_idx << 7);  // lane_idx * 128
    wire [10:0] obs_y0    = lane_top + 11'd32;              // Obstacle top edge
    wire        in_obs_y  = (curr_y >= obs_y0) && (curr_y < obs_y0 + CAR_H);

    // Road and river lanes contain obstacles; grass/start/chasm do not.
    wire        is_active = (lane_type == LANE_ROAD) || (lane_type == LANE_RIVER);

    // Select sprite width based on lane type so the same hit-test logic covers both
    // 128-px cars and 192-px logs.
    wire [10:0] obj_w = (lane_type == LANE_RIVER) ? LOG_W : CAR_W;

    // Player chicken AABB hit test.
    wire chk_in = (curr_x >= chicken_x) && (curr_x < chicken_x + CHK_W) &&
                  (curr_y >= chicken_y) && (curr_y < chicken_y + CHK_H);

    // Obstacle hit tests — guard with in_game and in_obs_y so off-screen obstacles
    // and scan lines above/below the game area never trigger.  The o*x < SCREEN_W
    // check prevents wrapping artefacts when an obstacle X saturates near 2047.
    wire o1_in = in_game && in_obs_y && is_active &&
                 (curr_x >= o1x) && (curr_x < o1x + obj_w) && (o1x < SCREEN_W);
    wire o2_in = in_game && in_obs_y && is_active &&
                 (curr_x >= o2x) && (curr_x < o2x + obj_w) && (o2x < SCREEN_W);

    // Goose AABB hit tests — each goose occupies a 64×64 window (one animation frame).
    wire g0_in = g0_act && (curr_x >= g0_x) && (curr_x < g0_x + 11'd64) &&
                            (curr_y >= g0_y) && (curr_y < g0_y + GSE_H);
    wire g1_in = g1_act && (curr_x >= g1_x) && (curr_x < g1_x + 11'd64) &&
                            (curr_y >= g1_y) && (curr_y < g1_y + GSE_H);
    wire g2_in = g2_act && (curr_x >= g2_x) && (curr_x < g2_x + 11'd64) &&
                            (curr_y >= g2_y) && (curr_y < g2_y + GSE_H);

    wire any_goose_in = g0_in | g1_in | g2_in;

    // Priority-select the first active goose for address computation.
    // Only one goose's pixel is computed per scan position (first-hit wins).
    wire [2:0]  active_frame    = g0_in ? g0_frame  : (g1_in ? g1_frame  : g2_frame);
    wire [10:0] active_gse_x    = g0_in ? g0_x      : (g1_in ? g1_x      : g2_x);
    wire        active_gse_scrd = g0_in ? g0_scrd   : (g1_in ? g1_scrd   : g2_scrd);


    // Goose sprite ROM address calculation
    // The goose sprite sheet is 320×64: five 64-px-wide animation frames laid
    // horizontally.  The column within the sheet is:
    //   drawn_gse_col  = local column (possibly mirrored) + frame_offset
    // where frame_offset = active_frame * 64, implemented as a left shift by 6.
    //
    // Mirroring: the goose faces the player's position.  XOR with g*_scrd (scored
    // flag) flips orientation once the goose has passed the player.
    wire [5:0] local_gse_col = curr_x - active_gse_x;
    wire       gse_face_right = (chicken_x > active_gse_x) ^ active_gse_scrd;
    wire [5:0] drawn_gse_col  = gse_face_right ? (6'd63 - local_gse_col) : local_gse_col;

    // gse_col packs the mirrored column plus the frame offset into a 9-bit value
    // covering [0, 319].  gse_addr = row * 320 + col (row-major flat addressing).
    wire [8:0]  gse_col  = drawn_gse_col + (active_frame << 6);
    wire [5:0]  gse_row  = g0_in ? (curr_y - g0_y) : g1_in ? (curr_y - g1_y) : (curr_y - g2_y);
    wire [14:0] gse_addr = (gse_row * 15'd320) + gse_col;


    // Chicken sprite ROM address calculation
    // The chicken sprite is 64×64.  When facing left (chicken_facing == 2'd2) the
    // column index is mirrored: drawn_col = 63 - local_col.
    // chk_addr = row * 64 + col — with 64-px width this simplifies to {row, col[5:0]},
    // but the multiply form is used for clarity and matches the other sprites.
    wire [5:0]  local_chk_col = curr_x - chicken_x;
    wire [5:0]  drawn_chk_col = (chicken_facing == 2'd2) ? (6'd63 - local_chk_col) : local_chk_col;
    wire [5:0]  chk_row  = curr_y - chicken_y;
    wire [11:0] chk_addr = (chk_row * 12'd64) + drawn_chk_col;


    // Car / log sprite ROM address calculation
    // car_row_1 is the row offset from the obstacle's top edge — shared between both
    // obstacle slots and both road/river sprite types.
    //
    // Direction mirroring: act_lane_dir == 0 means obstacles travel right-to-left, so
    // the sprite is mirrored horizontally (col = max_col - local_col) to keep headlights
    // facing the direction of travel.
    //
    // Car address: {6-bit row, 7-bit col} concatenated = 13-bit flat index for a 128×64 ROM.
    // Log address: row * 192 + col for a 192×64 ROM (width is not a power of two, so the
    //              multiply cannot be replaced by concatenation).
    wire [5:0] car_row_1 = curr_y - obs_y0;

    // Obstacle slot 1 address
    wire [6:0] local_car_col_1  = curr_x - o1x;
    wire [6:0] drawn_car_col_1  = (act_lane_dir == 1'b0) ? (7'd127 - local_car_col_1) : local_car_col_1;
    wire [12:0] car_addr_1      = {car_row_1, drawn_car_col_1};

    wire [7:0] local_log_col_1  = curr_x - o1x;
    wire [7:0] drawn_log_col_1  = (act_lane_dir == 1'b0) ? (8'd191 - local_log_col_1) : local_log_col_1;
    wire [13:0] log_addr_1      = (car_row_1 * 14'd192) + drawn_log_col_1;

    // Obstacle slot 2 address
    wire [6:0] local_car_col_2  = curr_x - o2x;
    wire [6:0] drawn_car_col_2  = (act_lane_dir == 1'b0) ? (7'd127 - local_car_col_2) : local_car_col_2;
    wire [12:0] car_addr_2      = {car_row_1, drawn_car_col_2};

    wire [7:0] local_log_col_2  = curr_x - o2x;
    wire [7:0] drawn_log_col_2  = (act_lane_dir == 1'b0) ? (8'd191 - local_log_col_2) : local_log_col_2;
    wire [13:0] log_addr_2      = (car_row_1 * 14'd192) + drawn_log_col_2;

    // Feed whichever obstacle slot the scan position is inside into the single ROM port.
    // o1 takes priority if both hit simultaneously (shouldn't happen with correct spacing).
    wire [12:0] car_rom_addr = o1_in ? car_addr_1 : car_addr_2;
    wire [13:0] log_rom_addr = o1_in ? log_addr_1 : log_addr_2;


    // Background tile ROM address calculation
    // Road and chasm tiles are 32×128 px, tiled horizontally across the full screen width.
    // curr_x[4:0] gives the column within a 32-px tile (modulo 32 via bit-select).
    // tile_row is the row offset from the top of the game area; only the lower 7 bits are
    // needed to address 128 rows.
    wire [4:0]  tile_col  = curr_x[4:0];
    wire [6:0]  tile_row  = (curr_y - INFO_BAR_H);
    wire [11:0] tile_addr = {tile_row, tile_col};  // 7+5 = 12 bits, covers 128*32 = 4096 entries

    // River tile is 128×128 px; curr_x[6:0] and tile_row[6:0] give (col mod 128, row mod 128).
    wire [6:0]  river_col  = curr_x[6:0];
    wire [6:0]  river_row  = tile_row[6:0];
    wire [13:0] river_addr = {river_row, river_col};  // 7+7 = 14 bits, covers 128*128 = 16384


    // Game-over overlay geometry (2x integer upscale, no framebuffer)
    // To render a ROM image at 2× size, each screen pixel maps back to ROM pixel
    // (screen_offset >> 1).  This is equivalent to nearest-neighbour upsampling
    // and costs only a 1-bit right-shift per axis — no multiplier required.

    // Standard game-over screen: ROM is 570×145 → displayed as 1140×290.
    // Placement: top-left at (150, 305), so the 1140-px width is centred on the
    // 1440-px screen (left margin = (1440 - 1140) / 2 = 150).
    wire in_go_std = game_over && !death_by_chasm &&
                     (curr_x >= 11'd150) && (curr_x < 11'd1290) &&
                     (curr_y >= 11'd305) && (curr_y < 11'd595);
    wire [9:0]  go_std_x    = (curr_x - 11'd150) >> 1;
    wire [9:0]  go_std_y    = (curr_y - 11'd305) >> 1;
    // Max ROM address: 144 * 570 + 569 = 82,649 — fits in 17 bits (2^17 = 131,072).
    wire [16:0] go_std_addr = (go_std_y * 17'd570) + go_std_x;

    // Lava game-over screen (death by chasm): ROM is 200×425 → displayed as 400×850.
    // Placement: top-left at (520, 25), centred horizontally ((1440 - 400) / 2 = 520).
    wire in_go_lava = game_over && death_by_chasm &&
                      (curr_x >= 11'd520) && (curr_x < 11'd920) &&
                      (curr_y >= 11'd25)  && (curr_y < 11'd875);
    wire [9:0]  go_lava_x    = (curr_x - 11'd520) >> 1;
    wire [9:0]  go_lava_y    = (curr_y - 11'd25)  >> 1;
    // Max ROM address: 424 * 200 + 199 = 84,999 — fits in 17 bits.
    wire [16:0] go_lava_addr = (go_lava_y * 17'd200) + go_lava_x;


    // BRAM sprite ROM instantiations
    // Each sprite_rom is a parameterised synchronous single-port ROM inferred from a
    // .mem file loaded with $readmemh.  All ROMs share a common 12-bit R4G4B4 output
    // format; magenta (12'hF0F) is the universal transparency key.
    // Road and chasm tiles reuse the same tile_addr since they have identical geometry.
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
    // All combinational hit/mask signals are flopped here.  This ensures that when
    // the BRAM outputs the pixel on the *next* clock edge, the corresponding hit
    // flag has also advanced by exactly one cycle and the two signals are aligned
    // in the final output mux below.
    reg chk_in_d, o1_in_d, o2_in_d, in_game_d, in_info_d;
    reg any_goose_in_d;
    reg [2:0]  lane_type_d;
    reg [10:0] curr_y_d;
    reg [10:0] curr_x_d;
    reg        o1_log_d, o2_log_d;  // Log (river) hit flags, separate from car hit flags
    reg        low_life_flash_d;

    always @(posedge clk) begin
        chk_in_d         <= chk_in;
        // Split the road/river hit flags at registration time so the output mux
        // can select log_pixel vs car_pixel without combinational lane_type logic
        // that would create a critical path through the registered BRAM output.
        o1_in_d          <= o1_in && (lane_type == LANE_ROAD);
        o2_in_d          <= o2_in && (lane_type == LANE_ROAD);
        o1_log_d         <= o1_in && (lane_type == LANE_RIVER);
        o2_log_d         <= o2_in && (lane_type == LANE_RIVER);
        any_goose_in_d   <= any_goose_in;
        in_game_d        <= in_game;
        in_info_d        <= (curr_y < INFO_BAR_H);
        lane_type_d      <= lane_type;
        curr_y_d         <= curr_y;
        curr_x_d         <= curr_x;
        low_life_flash_d <= low_life_flash;
    end


    // Transparency checks
    // Magenta (12'hF0F) is the sprite transparency key used in all .mem files.
    // Car and log ROMs additionally treat black (12'h000) as transparent to handle
    // palette entries that default to zero in unpainted regions.
    wire chk_transparent = (chk_pixel == 12'hF0F);
    wire car_transparent = (car_pixel == 12'h000) || (car_pixel == 12'hF0F);
    wire log_transparent = (log_pixel == 12'h000) || (log_pixel == 12'hF0F);
    wire gse_transparent = (gse_pixel == 12'h000) || (gse_pixel == 12'hF0F);


    // Info bar pixel (instantiated submodule — renders score, lives, title text)
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

    // Delay the info_bar pixel outputs by one cycle to match the pipeline stage
    // applied to the combinational hit signals above.
    reg [3:0] info_r_d, info_g_d, info_b_d;
    always @(posedge clk) begin
        info_r_d <= info_r;
        info_g_d <= info_g;
        info_b_d <= info_b;
    end


    // Chicken visibility logic
    // The chicken is hidden in two independent situations:
    //   1. sprite_flash: post-collision invulnerability window (rapid blink from game_top).
    //   2. low_life_flash && !game_over: player is at 1 life — slow ~1 Hz warning blink.
    //      The !game_over guard prevents the sprite disappearing at the exact death frame.
    // hide_chicken suppresses the chicken branch in the priority mux below; the BRAM
    // address is still computed every cycle (BRAM cannot be clock-gated per-pixel).
    wire hide_chicken    = sprite_flash || (low_life_flash_d && !game_over);
    wire chk_layer_active = chk_in_d && !hide_chicken && !chk_transparent;


    // Priority pixel multiplexer (painter's algorithm, combinational)
    // Evaluated once per pixel clock against the registered hit flags and the
    // pixel data returned from the BRAMs in the same cycle.
    // The default assignment (12'h000 = black) handles the overscan region and
    // any unclassified pixels.
    always @(*) begin
        {draw_r, draw_g, draw_b} = 12'h000; // Default: black (overscan / undefined)

        // Layer 1: Lava game-over overlay (death by chasm — highest priority)
        if (in_go_lava && go_lava_pixel != 12'hF0F) begin
            {draw_r, draw_g, draw_b} = go_lava_pixel;

        // Layer 2: Standard game-over overlay
        end else if (in_go_std && go_std_pixel != 12'hF0F) begin
            {draw_r, draw_g, draw_b} = go_std_pixel;

        // Layer 3: Info bar (score, lives, title — top 100 px)
        end else if (in_info_d) begin
            {draw_r, draw_g, draw_b} = {info_r_d, info_g_d, info_b_d};

        // Layer 4: Feather debug pixel (pure white, single-pixel diagnostic overlay)
        end else if (is_feather) begin
            {draw_r, draw_g, draw_b} = 12'hFFF;

        // Layer 5: Player chicken sprite (suppressed during flash states)
        end else if (chk_layer_active) begin
            {draw_r, draw_g, draw_b} = chk_pixel;

        // Layer 6: Log obstacles (river lanes)
        end else if ((o1_log_d || o2_log_d) && !log_transparent) begin
            {draw_r, draw_g, draw_b} = log_pixel;

        // Layer 7: Car obstacles (road lanes)
        end else if ((o1_in_d || o2_in_d) && !car_transparent) begin
            {draw_r, draw_g, draw_b} = car_pixel;

        // Layer 8: Goose enemies
        end else if (any_goose_in_d && !gse_transparent) begin
            {draw_r, draw_g, draw_b} = gse_pixel;

        // Below-game-area guard: rows below the 768-px game area render black.
        end else if (curr_y_d >= INFO_BAR_H + 11'd768) begin
            {draw_r, draw_g, draw_b} = 12'h000;

        // Layer 9: Lane background tiles
        end else if (in_game_d) begin
            case (lane_type_d)
                // Grass and start lanes: procedural two-tone checkerboard using bit 2 of
                // curr_x (toggles every 8 px) to alternate between two shades of green.
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
