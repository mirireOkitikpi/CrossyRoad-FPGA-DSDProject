`timescale 1ns / 1ps
// Module: game_top.v
// Purpose: Top-level orchestrator for Crossy Chasm. Instantiates and connects
//          all subsystems: clocking, debounce, sensor peripherals (ADXL362 SPI,
//          PDM microphone), lane manager, goose AI, player controller, camera
//          smoothers, particle engine, drawcon, VGA output, and 7-segment display.
//
// Scoring system:
//   Base +1 points: driven by player_ctrl's score_point_pulse (high-watermark).
//   score_point_pulse fires once per genuinely new forward lane reached and never
//   fires when the player retreats and re-crosses an already-visited lane, closing
//   the back-and-forth farming exploit.
//   lane_counter increments on score_point_pulse (not world_scrolled) to count
//   genuine new lanes for the per-5-lane cross_bonus.
//   world_scrolled is still computed for lane_manager but is not used for scoring.
//
// Log-off-screen death:
//   player_ctrl clamps chicken_x at screen edges to keep the sprite visible.
//   log_pushed_to_wall detects the equivalent carried-off condition: chicken is
//   pinned at a screen wall on a river lane with no log beneath it.
//
// Goose grass-lane enforcement:
//   g*_valid flags derived from each goose's Y-position lane lookup suppress
//   goose_hit and shout interactions for geese not standing on grass.
//   drawcon enforces the same rule visually via lane_type checks in g*_in.
//
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
    input        accel_miso,
    output       m_clk,
    input        m_data,
    output       m_lrsel
);

    // SECTION 1: Clocking
    // pixclk drives the VGA pixel pipeline (~106.47 MHz for 1440x900 @ 60 Hz).
    // sys_clk is 100 MHz and drives debounce, peripherals, and CDC registers.
    // game_clk is ~60 Hz derived from sys_clk for all game logic.
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

    // SECTION 2: Debounce
    wire btn_c_db, btn_u_db, btn_d_db, btn_l_db, btn_r_db;

    debounce db_c (.clk(sys_clk), .rst(rst), .btn_in(btn_c), .btn_out(btn_c_db));
    debounce db_u (.clk(sys_clk), .rst(rst), .btn_in(btn_u), .btn_out(btn_u_db));
    debounce db_d (.clk(sys_clk), .rst(rst), .btn_in(btn_d), .btn_out(btn_d_db));
    debounce db_l (.clk(sys_clk), .rst(rst), .btn_in(btn_l), .btn_out(btn_l_db));
    debounce db_r (.clk(sys_clk), .rst(rst), .btn_in(btn_r), .btn_out(btn_r_db));

    // SECTION 3: Game-state registers
    reg        game_started, game_over;
    reg        btn_c_prev;
    wire       btn_c_rise = btn_c_db & ~btn_c_prev;
    reg [7:0]  score, high_score;
    reg [2:0]  lives;
    wire       game_active = game_started & ~game_over;

    reg        game_reset_pulse;

    // reset_settle: suppresses lane_counter increments for the first few
    // game_clk ticks after game_reset_pulse while player_ctrl propagates the
    // reset through logical_world_y.
    reg [2:0]  reset_settle;

    // SECTION 4: Sensor peripherals + CDC flags
    // ADXL362 flick and PDM mic shout pulses arrive on sys_clk. They are latched
    // into sticky flags so game_clk logic can consume them without missing pulses.
    wire flick_pulse_100MHz;
    wire shout_pulse_100MHz;

    adxl362_ctrl accel_inst (
        .clk(sys_clk), .rst(rst),
        .cs(accel_cs), .mosi(accel_mosi), .sclk(accel_sclk), .miso(accel_miso),
        .flick_detected(flick_pulse_100MHz)
    );

    mic_ctrl microphone_inst (
        .clk(sys_clk), .rst(rst),
        .m_clk(m_clk), .m_data(m_data), .m_lrsel(m_lrsel),
        .shout_detected(shout_pulse_100MHz)
    );

    wire flick_cleared_by_game;
    reg  flick_flag;
    wire shout_cleared_by_game;
    reg  shout_flag;

    always @(posedge sys_clk or negedge rst) begin
        if (!rst) begin
            flick_flag <= 1'b0;
            shout_flag <= 1'b0;
        end else begin
            if (flick_pulse_100MHz)         flick_flag <= 1'b1;
            else if (flick_cleared_by_game) flick_flag <= 1'b0;
            if (shout_pulse_100MHz)         shout_flag <= 1'b1;
            else if (shout_cleared_by_game) shout_flag <= 1'b0;
        end
    end

    // SECTION 5: Game-logic wires
    wire signed [11:0] chicken_x;   // Signed — matches player_ctrl output
    wire [10:0] chicken_y;
    wire [10:0] logical_world_y;
    wire [10:0] render_world_y;
    wire [10:0] render_chicken_x;
    wire [10:0] render_chicken_y;

    wire [2:0]  lt0, lt1, lt2, lt3, lt4, lt5;
    wire [11:0] ox0,  ox1,  ox2,  ox3,  ox4,  ox5;
    wire [11:0] o2x0, o2x1, o2x2, o2x3, o2x4, o2x5;
    wire ld0, ld1, ld2, ld3, ld4, ld5;

    localparam INFO_BAR_H = 11'd100;
    localparam LANE_H     = 11'd128;
    localparam LANE_GRASS = 3'd0;

    wire [3:0] chk_lane = (chicken_y >= INFO_BAR_H) ? ((chicken_y - INFO_BAR_H) >> 7) : 4'd0;
    wire       qry_dir;
    wire [3:0] qry_speed;

    wire        grass_spawn_pulse;
    wire [10:0] new_lane_y;
    wire [15:0] prng_val;

    lane_manager lane_mgr (
        .clk(game_clk), .rst(rst),
        .game_reset_pulse(game_reset_pulse),
        .game_active(game_active), .logical_world_y(logical_world_y),
        .lane_type_0(lt0), .lane_type_1(lt1), .lane_type_2(lt2),
        .lane_type_3(lt3), .lane_type_4(lt4), .lane_type_5(lt5),
        .lane_dir_0(ld0), .lane_dir_1(ld1), .lane_dir_2(ld2),
        .lane_dir_3(ld3), .lane_dir_4(ld4), .lane_dir_5(ld5),
        .obs_x_0(ox0), .obs_x_1(ox1), .obs_x_2(ox2),
        .obs_x_3(ox3), .obs_x_4(ox4), .obs_x_5(ox5),
        .obs2_x_0(o2x0), .obs2_x_1(o2x1), .obs2_x_2(o2x2),
        .obs2_x_3(o2x3), .obs2_x_4(o2x4), .obs2_x_5(o2x5),
        .query_lane(chk_lane), .query_dir(qry_dir), .query_speed(qry_speed),
        .grass_spawn_pulse(grass_spawn_pulse),
        .new_lane_y(new_lane_y),
        .prng_val(prng_val)
    );

    wire [10:0] g0_x, g0_y, g1_x, g1_y, g2_x, g2_y;
    wire        g0_act, g0_scrd, g1_act, g1_scrd, g2_act, g2_scrd;
    wire        goose_hit_raw;  // Unfiltered — gated by g*_valid before use
    wire [2:0]  g0_frame, g1_frame, g2_frame;
    wire [5:0]  goose_bonus;
    wire [2:0]  difficulty_bonus_type;

    goose_manager ai_geese (
        .clk(game_clk), .rst(rst),
        .game_active(game_active),
        .player_x(chicken_x[10:0]), .player_y(chicken_y),
        .logical_world_y(logical_world_y),
        .shout_detected(shout_flag),
        .clear_shout_flag(shout_cleared_by_game),
        .spawn_pulse(grass_spawn_pulse),
        .spawn_y(new_lane_y),
        .lfsr_rand(prng_val),
        .sw(sw[1:0]),
        .goose0_x(g0_x), .goose0_y(g0_y), .goose0_act(g0_act), .goose0_scared(g0_scrd), .goose0_frame(g0_frame),
        .goose1_x(g1_x), .goose1_y(g1_y), .goose1_act(g1_act), .goose1_scared(g1_scrd), .goose1_frame(g1_frame),
        .goose2_x(g2_x), .goose2_y(g2_y), .goose2_act(g2_act), .goose2_scared(g2_scrd), .goose2_frame(g2_frame),
        .goose_hit(goose_hit_raw),
        .goose_bonus(goose_bonus),
        .difficulty_bonus_type(difficulty_bonus_type)
    );

    // SECTION 6: Goose grass-lane validity flags
    // Each goose's Y position is decoded to a lane index then looked up against
    // the lane_type outputs of lane_manager. A goose is only valid (can collide
    // or be scared) when it is active AND its current lane is grass.
    wire [2:0] g0_lane_idx = (g0_y - 11'd100) >> 7;
    wire [2:0] g1_lane_idx = (g1_y - 11'd100) >> 7;
    wire [2:0] g2_lane_idx = (g2_y - 11'd100) >> 7;

    reg [2:0] g0_lane_type, g1_lane_type, g2_lane_type;

    always @(*) begin
        case (g0_lane_idx)
            3'd0: g0_lane_type = lt0; 3'd1: g0_lane_type = lt1;
            3'd2: g0_lane_type = lt2; 3'd3: g0_lane_type = lt3;
            3'd4: g0_lane_type = lt4; 3'd5: g0_lane_type = lt5;
            default: g0_lane_type = 3'd1; // Non-grass safe fallback
        endcase
        case (g1_lane_idx)
            3'd0: g1_lane_type = lt0; 3'd1: g1_lane_type = lt1;
            3'd2: g1_lane_type = lt2; 3'd3: g1_lane_type = lt3;
            3'd4: g1_lane_type = lt4; 3'd5: g1_lane_type = lt5;
            default: g1_lane_type = 3'd1;
        endcase
        case (g2_lane_idx)
            3'd0: g2_lane_type = lt0; 3'd1: g2_lane_type = lt1;
            3'd2: g2_lane_type = lt2; 3'd3: g2_lane_type = lt3;
            3'd4: g2_lane_type = lt4; 3'd5: g2_lane_type = lt5;
            default: g2_lane_type = 3'd1;
        endcase
    end

    wire g0_valid = g0_act && (g0_lane_type == LANE_GRASS);
    wire g1_valid = g1_act && (g1_lane_type == LANE_GRASS);
    wire g2_valid = g2_act && (g2_lane_type == LANE_GRASS);

    // Accept goose_hit only when the colliding goose is on a grass lane
    wire goose_hit = goose_hit_raw && (g0_valid | g1_valid | g2_valid);

    // SECTION 7: Collision lookup + damage logic
    localparam OBS_W = 11'd64;
    localparam LOG_W = 11'd128;
    localparam HB_IN = 11'd4;   // Horizontal inset for the player hitbox

    reg [2:0]  chk_lt;
    reg [10:0] chk_o1, chk_o2;

    reg        death_by_chasm;
    reg [5:0]  heart_anim_timer;
    reg [1:0]  heart_frame;

    always @(*) begin
        case (chk_lane)
            4'd0: begin chk_lt=lt0; chk_o1=ox0[10:0]; chk_o2=o2x0[10:0]; end
            4'd1: begin chk_lt=lt1; chk_o1=ox1[10:0]; chk_o2=o2x1[10:0]; end
            4'd2: begin chk_lt=lt2; chk_o1=ox2[10:0]; chk_o2=o2x2[10:0]; end
            4'd3: begin chk_lt=lt3; chk_o1=ox3[10:0]; chk_o2=o2x3[10:0]; end
            4'd4: begin chk_lt=lt4; chk_o1=ox4[10:0]; chk_o2=o2x4[10:0]; end
            4'd5: begin chk_lt=lt5; chk_o1=ox5[10:0]; chk_o2=o2x5[10:0]; end
            default: begin chk_lt=3'd0; chk_o1=11'd0; chk_o2=11'd0; end
        endcase
    end

    wire [10:0] hb_x = chicken_x[10:0] + HB_IN;
    wire [10:0] hb_w = 11'd56;

    wire car_hit_1 = (chk_lt == 3'd1) && (hb_x < chk_o1 + OBS_W) && (hb_x + hb_w > chk_o1) && (chk_o1 < 11'd1440);
    wire car_hit_2 = (chk_lt == 3'd1) && (hb_x < chk_o2 + OBS_W) && (hb_x + hb_w > chk_o2) && (chk_o2 < 11'd1440);

    wire on_log_1   = (hb_x < chk_o1 + LOG_W) && (hb_x + hb_w > chk_o1) && (chk_o1 < 11'd1440);
    wire on_log_2   = (hb_x < chk_o2 + LOG_W) && (hb_x + hb_w > chk_o2) && (chk_o2 < 11'd1440);
    wire on_any_log = on_log_1 | on_log_2;

    wire is_river    = (chk_lt == 3'd2);
    wire river_death = is_river && !on_any_log;
    wire chasm_death = (chk_lt == 3'd4);

    // log_pushed_to_wall: correct carried-off-screen death condition.
    // player_ctrl clamps chicken_x at the screen edges so the sprite stays visible,
    // meaning chicken_x can never truly go out of bounds. Instead this wire detects
    // the semantically equivalent state: the chicken is pinned at a wall on a river
    // lane with no log beneath it, meaning the log has wrapped away and left the
    // player standing over water with no way to avoid drowning.
    localparam signed [11:0] SCREEN_LEFT  = 12'sd4;
    localparam signed [11:0] SCREEN_RIGHT = 12'sd1404;
    wire at_left_wall       = (chicken_x <= SCREEN_LEFT);
    wire at_right_wall      = (chicken_x >= SCREEN_RIGHT);
    wire log_pushed_to_wall = is_river && !on_any_log && (at_left_wall || at_right_wall);

    wire carried_offscreen; // Port still connected to player_ctrl but unused for death logic
    reg [2:0] jump_timer;
    wire is_jumping    = (chicken_y != render_chicken_y) || (jump_timer > 0);
    wire any_collision = (car_hit_1 | car_hit_2 | river_death | chasm_death | log_pushed_to_wall | goose_hit) && !is_jumping;

    reg [6:0] invuln_timer;
    wire invulnerable = (invuln_timer > 0);
    wire sprite_flash = invuln_timer[3]; // Rapid blink during invulnerability window
    wire take_damage  = any_collision && !invulnerable;

    wire [1:0] chicken_facing;
    wire       chicken_moving;
    wire       log_carry_en = is_river && on_any_log && game_active;

    // score_point_pulse: high-watermark pulse from player_ctrl (one tick per new lane)
    wire score_point_pulse;

    player_ctrl player_inst (
        .clk(game_clk), .rst(rst),
        .game_reset_pulse(game_reset_pulse),
        .btn_up(btn_u_db), .btn_down(btn_d_db),
        .btn_left(btn_l_db), .btn_right(btn_r_db),
        .game_active(game_active),
        .flick_jump_flag(flick_flag),
        .clear_flick_flag(flick_cleared_by_game),
        .log_carry_en(log_carry_en),
        .log_carry_right(~qry_dir),
        .log_carry_speed(qry_speed),
        .chicken_x(chicken_x), .chicken_y(chicken_y),
        .logical_world_y(logical_world_y), .facing(chicken_facing),
        .is_moving(chicken_moving),
        .carried_offscreen(carried_offscreen),
        .score_point_pulse(score_point_pulse)
    );

    // Three camera_smoother instances interpolate render positions toward logical
    // positions at PAN_SPEED px/tick to prevent hard-cut visual jumps.
    camera_smoother cam_smooth_inst (.clk(game_clk), .rst(rst), .logical_y(logical_world_y),   .render_y(render_world_y));
    camera_smoother smooth_chk_y   (.clk(game_clk), .rst(rst), .logical_y(chicken_y),          .render_y(render_chicken_y));
    camera_smoother smooth_chk_x   (.clk(game_clk), .rst(rst), .logical_y(chicken_x[10:0]),    .render_y(render_chicken_x));

    // SECTION 8: Low-life flash generator
    // Drives a ~1 Hz blink when lives == 1 by taking bit 4 of a 5-bit counter
    // clocked at game_clk (~60 Hz): 60 / 32 ≈ 1.9 Hz toggle.
    reg [4:0] life_flash_cnt;
    always @(posedge game_clk or negedge rst) begin
        if (!rst) life_flash_cnt <= 5'd0;
        else      life_flash_cnt <= life_flash_cnt + 5'd1;
    end
    wire low_life_flash = (lives == 3'd1) && !game_over && life_flash_cnt[4];

    // SECTION 9: FSM
    // Scoring:
    //   Base +1: driven by score_point_pulse (high-watermark, from player_ctrl).
    //   lane_counter: increments on score_point_pulse so cross_bonus counts new
    //     lanes, not camera scroll events.
    //   cross_bonus: awards difficulty_bonus_type points every 5 new lanes.
    //   goose_bonus: added directly from goose_manager on shout scatter events.
    //   reset_settle: guards lane_counter against the post-reset transient.
    reg [10:0] prev_world_y; // Tracked to keep lane_manager's world_scrolled valid
    reg [2:0]  lane_counter;

    wire [7:0] cross_bonus   = (score_point_pulse && lane_counter == 3'd4) ? {5'd0, difficulty_bonus_type} : 8'd0;
    wire [7:0] points_to_add = (score_point_pulse ? 8'd1 : 8'd0) + goose_bonus + cross_bonus;

    always @(posedge game_clk or negedge rst) begin
        if (!rst) begin
            game_started     <= 1'b0;
            game_over        <= 1'b0;
            btn_c_prev       <= 1'b0;
            score            <= 8'd0;
            high_score       <= 8'd0;
            lives            <= 3'd3;
            prev_world_y     <= 11'd0;
            invuln_timer     <= 7'd0;
            jump_timer       <= 3'd0;
            lane_counter     <= 3'd0;
            death_by_chasm   <= 1'b0;
            heart_anim_timer <= 6'd0;
            heart_frame      <= 2'd0;
            game_reset_pulse <= 1'b0;
            reset_settle     <= 3'd0;
        end else begin
            game_reset_pulse <= 1'b0;
            btn_c_prev       <= btn_c_db;

            if (reset_settle > 0) reset_settle <= reset_settle - 1;

            if (heart_anim_timer == 6'd15) begin
                heart_anim_timer <= 0;
                heart_frame      <= (heart_frame == 2) ? 2'd0 : heart_frame + 1;
            end else begin
                heart_anim_timer <= heart_anim_timer + 1;
            end

            // Maintain prev_world_y so lane_manager's world_scrolled stays valid
            if (logical_world_y != prev_world_y)
                prev_world_y <= logical_world_y;

            if (!game_started) begin
                if (btn_c_rise) begin
                    game_started     <= 1'b1;
                    game_over        <= 1'b0;
                    score            <= 8'd0;
                    lives            <= 3'd3;
                    invuln_timer     <= 7'd120;
                    jump_timer       <= 3'd0;
                    lane_counter     <= 3'd0;
                    death_by_chasm   <= 1'b0;
                    prev_world_y     <= logical_world_y;
                    game_reset_pulse <= 1'b1;
                    reset_settle     <= 3'd4;
                end
            end else if (!game_over) begin
                if (chicken_moving)      jump_timer <= 3'd3;
                else if (jump_timer > 0) jump_timer <= jump_timer - 1;

                if (invuln_timer > 0) invuln_timer <= invuln_timer - 1;

                if (score_point_pulse && reset_settle == 3'd0)
                    lane_counter <= (lane_counter == 3'd4) ? 3'd0 : lane_counter + 3'd1;

                if (points_to_add > 0 && reset_settle == 3'd0) begin
                    score <= score + points_to_add;
                    if (score + points_to_add > high_score)
                        high_score <= score + points_to_add;
                end

                if (take_damage) begin
                    if (chasm_death) begin
                        lives          <= 3'd0;
                        game_over      <= 1'b1;
                        death_by_chasm <= 1'b1;
                    end else if (lives > 3'd1) begin
                        lives        <= lives - 1;
                        invuln_timer <= 7'd120;
                    end else begin
                        lives          <= 3'd0;
                        game_over      <= 1'b1;
                        death_by_chasm <= 1'b0;
                    end
                end
            end else begin
                if (btn_c_rise) begin
                    game_started     <= 1'b1;
                    game_over        <= 1'b0;
                    score            <= 8'd0;
                    lives            <= 3'd3;
                    invuln_timer     <= 7'd120;
                    jump_timer       <= 3'd0;
                    lane_counter     <= 3'd0;
                    death_by_chasm   <= 1'b0;
                    prev_world_y     <= logical_world_y;
                    game_reset_pulse <= 1'b1;
                    reset_settle     <= 3'd4;
                end
            end
        end
    end

    // SECTION 10: Particle engine with CDC
    // game_over_pulse_pclk is derived by crossing spawn_pending_gclk through a
    // 3-stage synchroniser into the pixclk domain. A rising-edge detector on the
    // last two stages produces a single-cycle pulse on pixclk.
    reg game_over_prev;
    always @(posedge game_clk or negedge rst) begin
        if (!rst) game_over_prev <= 1'b0;
        else      game_over_prev <= game_over;
    end
    wire game_over_pulse_gclk = game_over & ~game_over_prev;

    reg [10:0] spawn_x_gclk, spawn_y_gclk;
    reg        spawn_pending_gclk;
    wire       spawn_ack_pclk;

    reg spawn_ack_sync0, spawn_ack_sync1;
    always @(posedge game_clk or negedge rst) begin
        if (!rst) begin spawn_ack_sync0 <= 1'b0; spawn_ack_sync1 <= 1'b0; end
        else begin
            spawn_ack_sync0 <= spawn_ack_pclk;
            spawn_ack_sync1 <= spawn_ack_sync0;
        end
    end

    always @(posedge game_clk or negedge rst) begin
        if (!rst) begin
            spawn_x_gclk <= 11'd0; spawn_y_gclk <= 11'd0; spawn_pending_gclk <= 1'b0;
        end else if (game_over_pulse_gclk) begin
            spawn_x_gclk       <= render_chicken_x;
            spawn_y_gclk       <= render_chicken_y;
            spawn_pending_gclk <= 1'b1;
        end else if (spawn_ack_sync1) begin
            spawn_pending_gclk <= 1'b0;
        end
    end

    reg pending_sync0, pending_sync1, pending_sync2;
    always @(posedge pixclk or negedge rst) begin
        if (!rst) begin pending_sync0 <= 1'b0; pending_sync1 <= 1'b0; pending_sync2 <= 1'b0; end
        else begin
            pending_sync0 <= spawn_pending_gclk;
            pending_sync1 <= pending_sync0;
            pending_sync2 <= pending_sync1;
        end
    end
    wire game_over_pulse_pclk = pending_sync1 & ~pending_sync2;
    assign spawn_ack_pclk = pending_sync1;

    wire [3:0]  draw_r, draw_g, draw_b;
    wire [10:0] curr_x, curr_y;
    wire        is_feather;

    particle_engine feather_explosion (
        .clk(pixclk), .rst(rst),
        .spawn_x(spawn_x_gclk), .spawn_y(spawn_y_gclk),
        .game_over_pulse(game_over_pulse_pclk),
        .curr_x(curr_x), .curr_y(curr_y),
        .is_particle_pixel(is_feather)
    );

    // SECTION 11: Drawcon + VGA
    drawcon drawcon_inst (
        .clk(pixclk), .rst(rst),
        .is_feather(is_feather),
        .chicken_x(render_chicken_x), .chicken_y(render_chicken_y),
        .chicken_facing(chicken_facing), .chicken_moving(chicken_moving),
        .game_started(game_started), .game_over(game_over),
        .death_by_chasm(death_by_chasm), .heart_frame(heart_frame),
        .score(score), .lives(lives), .sprite_flash(sprite_flash),
        .low_life_flash(low_life_flash),
        .lane_type_0(lt0), .lane_type_1(lt1), .lane_type_2(lt2),
        .lane_type_3(lt3), .lane_type_4(lt4), .lane_type_5(lt5),
        .lane_dir_0(ld0), .lane_dir_1(ld1), .lane_dir_2(ld2),
        .lane_dir_3(ld3), .lane_dir_4(ld4), .lane_dir_5(ld5),
        .obs_x_0(ox0), .obs_x_1(ox1), .obs_x_2(ox2),
        .obs_x_3(ox3), .obs_x_4(ox4), .obs_x_5(ox5),
        .obs2_x_0(o2x0), .obs2_x_1(o2x1), .obs2_x_2(o2x2),
        .obs2_x_3(o2x3), .obs2_x_4(o2x4), .obs2_x_5(o2x5),
        .g0_x(g0_x), .g0_y(g0_y), .g0_act(g0_act), .g0_scrd(g0_scrd), .g0_frame(g0_frame),
        .g1_x(g1_x), .g1_y(g1_y), .g1_act(g1_act), .g1_scrd(g1_scrd), .g1_frame(g1_frame),
        .g2_x(g2_x), .g2_y(g2_y), .g2_act(g2_act), .g2_scrd(g2_scrd), .g2_frame(g2_frame),
        .curr_x(curr_x), .curr_y(curr_y),
        .draw_r(draw_r), .draw_g(draw_g), .draw_b(draw_b)
    );

    vga vga_inst (
        .clk(pixclk), .rst(rst),
        .draw_r(draw_r), .draw_g(draw_g), .draw_b(draw_b),
        .curr_x(curr_x), .curr_y(curr_y),
        .pix_r(pix_r), .pix_g(pix_g), .pix_b(pix_b),
        .hsync(hsync), .vsync(vsync)
    );

    // SECTION 12: 7-segment + debug LEDs
    score_display score_inst (
        .clk(sys_clk), .rst(rst),
        .game_over(game_over),
        .score(score), .high_score(high_score),
        .seg(seg), .an(an)
    );

    reg debug_shout_led;
    always @(posedge sys_clk or negedge rst) begin
        if (!rst)                    debug_shout_led <= 1'b0;
        else if (shout_pulse_100MHz) debug_shout_led <= ~debug_shout_led;
    end

    assign led[7:0]  = score;
    assign led[8]    = (lives >= 3'd1);
    assign led[9]    = (lives >= 3'd2);
    assign led[10]   = (lives >= 3'd3);
    assign led[11]   = on_any_log;
    assign led[12]   = is_river;
    assign led[13]   = log_carry_en;
    assign led[14]   = debug_shout_led;
    assign led[15]   = game_over;

endmodule
