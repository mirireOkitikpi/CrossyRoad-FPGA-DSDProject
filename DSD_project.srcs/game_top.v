`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      game_top.v (v3 — log riding mechanics)
// Description:
//   Top-level for Crossy Road. Now includes log-riding: when the
//   chicken is on a river lane and overlapping a log, the chicken's
//   X position is carried with the log's scroll direction/speed.
//   If the chicken drifts off-screen, it dies.
//   River death only triggers when on a river lane and NOT on any log.
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
    output [15:0] led
);

    // ══════════════════════════════════════════════════════════
    // SECTION 1: Clocks
    // ══════════════════════════════════════════════════════════
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

    // ══════════════════════════════════════════════════════════
    // SECTION 2: Debouncing
    // ══════════════════════════════════════════════════════════
    wire btn_c_db, btn_u_db, btn_d_db, btn_l_db, btn_r_db;

    debounce db_c (.clk(sys_clk), .rst(rst), .btn_in(btn_c), .btn_out(btn_c_db));
    debounce db_u (.clk(sys_clk), .rst(rst), .btn_in(btn_u), .btn_out(btn_u_db));
    debounce db_d (.clk(sys_clk), .rst(rst), .btn_in(btn_d), .btn_out(btn_d_db));
    debounce db_l (.clk(sys_clk), .rst(rst), .btn_in(btn_l), .btn_out(btn_l_db));
    debounce db_r (.clk(sys_clk), .rst(rst), .btn_in(btn_r), .btn_out(btn_r_db));

    // ══════════════════════════════════════════════════════════
    // SECTION 3: Game state
    // ══════════════════════════════════════════════════════════
    reg        game_started, game_over;
    reg        btn_c_prev;
    wire       btn_c_rise = btn_c_db & ~btn_c_prev;
    reg [7:0]  score, high_score;
    reg [2:0]  lives;
    wire       game_active = game_started & ~game_over;

    // ══════════════════════════════════════════════════════════
    // SECTION 4: Lane manager
    // ══════════════════════════════════════════════════════════
    wire [1:0] lt0, lt1, lt2, lt3, lt4, lt5, lt6, lt7;
    wire [1:0] lt8, lt9, lt10, lt11, lt12, lt13;

    wire [10:0] ox0, ox1, ox2, ox3, ox4, ox5, ox6, ox7;
    wire [10:0] ox8, ox9, ox10, ox11, ox12, ox13;
    wire [10:0] o2x0, o2x1, o2x2, o2x3, o2x4, o2x5, o2x6, o2x7;
    wire [10:0] o2x8, o2x9, o2x10, o2x11, o2x12, o2x13;

    // Query interface for chicken's lane
    wire [10:0] chicken_x, chicken_y, world_y;
    localparam INFO_BAR_H = 11'd100;
    localparam LANE_H     = 11'd57;

    wire [3:0] chk_lane = (chicken_y >= INFO_BAR_H) ?
                           (chicken_y - INFO_BAR_H) / LANE_H : 4'd0;

    wire       qry_dir;
    wire [3:0] qry_speed;

    lane_manager lane_mgr (
        .clk(game_clk), .rst(rst),
        .game_active(game_active), .world_y(world_y),
        // Lane types
        .lane_type_0(lt0),   .lane_type_1(lt1),   .lane_type_2(lt2),
        .lane_type_3(lt3),   .lane_type_4(lt4),   .lane_type_5(lt5),
        .lane_type_6(lt6),   .lane_type_7(lt7),   .lane_type_8(lt8),
        .lane_type_9(lt9),   .lane_type_10(lt10),  .lane_type_11(lt11),
        .lane_type_12(lt12), .lane_type_13(lt13),
        // Obs 1
        .obs_x_0(ox0),   .obs_x_1(ox1),   .obs_x_2(ox2),   .obs_x_3(ox3),
        .obs_x_4(ox4),   .obs_x_5(ox5),   .obs_x_6(ox6),   .obs_x_7(ox7),
        .obs_x_8(ox8),   .obs_x_9(ox9),   .obs_x_10(ox10),  .obs_x_11(ox11),
        .obs_x_12(ox12), .obs_x_13(ox13),
        // Obs 2
        .obs2_x_0(o2x0),   .obs2_x_1(o2x1),   .obs2_x_2(o2x2),   .obs2_x_3(o2x3),
        .obs2_x_4(o2x4),   .obs2_x_5(o2x5),   .obs2_x_6(o2x6),   .obs2_x_7(o2x7),
        .obs2_x_8(o2x8),   .obs2_x_9(o2x9),   .obs2_x_10(o2x10),  .obs2_x_11(o2x11),
        .obs2_x_12(o2x12), .obs2_x_13(o2x13),
        // Query
        .query_lane(chk_lane), .query_dir(qry_dir), .query_speed(qry_speed)
    );

    // ══════════════════════════════════════════════════════════
    // SECTION 5: Collision — chicken's current lane
    // ══════════════════════════════════════════════════════════
    localparam OBS_W  = 11'd64;
    localparam LOG_W  = 11'd128;   // Wide logs for easier landing
    localparam HB_IN  = 11'd4;

    reg [1:0]  chk_lt;
    reg [10:0] chk_o1, chk_o2;

    always @(*) begin
        case (chk_lane)
            4'd0:  begin chk_lt=lt0;  chk_o1=ox0;  chk_o2=o2x0;  end
            4'd1:  begin chk_lt=lt1;  chk_o1=ox1;  chk_o2=o2x1;  end
            4'd2:  begin chk_lt=lt2;  chk_o1=ox2;  chk_o2=o2x2;  end
            4'd3:  begin chk_lt=lt3;  chk_o1=ox3;  chk_o2=o2x3;  end
            4'd4:  begin chk_lt=lt4;  chk_o1=ox4;  chk_o2=o2x4;  end
            4'd5:  begin chk_lt=lt5;  chk_o1=ox5;  chk_o2=o2x5;  end
            4'd6:  begin chk_lt=lt6;  chk_o1=ox6;  chk_o2=o2x6;  end
            4'd7:  begin chk_lt=lt7;  chk_o1=ox7;  chk_o2=o2x7;  end
            4'd8:  begin chk_lt=lt8;  chk_o1=ox8;  chk_o2=o2x8;  end
            4'd9:  begin chk_lt=lt9;  chk_o1=ox9;  chk_o2=o2x9;  end
            4'd10: begin chk_lt=lt10; chk_o1=ox10; chk_o2=o2x10; end
            4'd11: begin chk_lt=lt11; chk_o1=ox11; chk_o2=o2x11; end
            4'd12: begin chk_lt=lt12; chk_o1=ox12; chk_o2=o2x12; end
            4'd13: begin chk_lt=lt13; chk_o1=ox13; chk_o2=o2x13; end
            default: begin chk_lt=2'd0; chk_o1=11'd0; chk_o2=11'd0; end
        endcase
    end

    // Chicken hitbox
    wire [10:0] hb_x = chicken_x + HB_IN;
    wire [10:0] hb_w = 11'd24;

    // ── Road collision: overlaps a car ──
    wire car_hit_1 = (chk_lt == 2'd1) &&
                     (hb_x < chk_o1 + OBS_W) && (hb_x + hb_w > chk_o1) &&
                     (chk_o1 < 11'd1440);
    wire car_hit_2 = (chk_lt == 2'd1) &&
                     (hb_x < chk_o2 + OBS_W) && (hb_x + hb_w > chk_o2) &&
                     (chk_o2 < 11'd1440);

    // ── Log overlap: chicken is on a log ──
    wire on_log_1 = (hb_x < chk_o1 + LOG_W) && (hb_x + hb_w > chk_o1) &&
                    (chk_o1 < 11'd1440);
    wire on_log_2 = (hb_x < chk_o2 + LOG_W) && (hb_x + hb_w > chk_o2) &&
                    (chk_o2 < 11'd1440);
    wire on_any_log = on_log_1 | on_log_2;

    // ── River death: on river lane but NOT on any log ──
    wire is_river = (chk_lt == 2'd2);
    wire river_death = is_river && !on_any_log;

    // ── Carried off-screen by a log ──
    wire carried_offscreen;

    wire any_collision = car_hit_1 | car_hit_2 | river_death | carried_offscreen;

    // ══════════════════════════════════════════════════════════
    // SECTION 6: Player controller (with log carry)
    // ══════════════════════════════════════════════════════════
    wire [1:0]  chicken_facing;
    wire        chicken_moving;

    // Log carry: active when on a river lane AND on a log
    wire log_carry_en = is_river && on_any_log && game_active;

    player_ctrl player_inst (
        .clk(game_clk), .rst(rst),
        .btn_up(btn_u_db), .btn_down(btn_d_db),
        .btn_left(btn_l_db), .btn_right(btn_r_db),
        .game_active(game_active),
        .log_carry_en(log_carry_en),
        .log_carry_right(~qry_dir),      // dir: 0=right in lane_mgr, invert for carry
        .log_carry_speed(qry_speed),
        .chicken_x(chicken_x), .chicken_y(chicken_y),
        .world_y(world_y), .facing(chicken_facing),
        .is_moving(chicken_moving),
        .carried_offscreen(carried_offscreen)
    );

    // ══════════════════════════════════════════════════════════
    // SECTION 7: Game state machine
    // ══════════════════════════════════════════════════════════
    reg [10:0] prev_world_y;

    always @(posedge game_clk or negedge rst) begin
        if (!rst) begin
            game_started <= 0; game_over <= 0; btn_c_prev <= 0;
            score <= 0; high_score <= 0; lives <= 3'd3;
            prev_world_y <= 0;
        end else begin
            btn_c_prev <= btn_c_db;

            if (!game_started) begin
                if (btn_c_rise) begin
                    game_started <= 1; game_over <= 0;
                    score <= 0; lives <= 3'd3; prev_world_y <= 0;
                end
            end else if (!game_over) begin
                // Score
                if (world_y != prev_world_y) begin
                    score <= score + 1;
                    if (score + 1 > high_score) high_score <= score + 1;
                    prev_world_y <= world_y;
                end
                // Death
                if (any_collision) game_over <= 1;
            end else begin
                if (btn_c_rise) begin game_started <= 0; game_over <= 0; end
            end
        end
    end

    // ══════════════════════════════════════════════════════════
    // SECTION 8: Drawing
    // ══════════════════════════════════════════════════════════
    wire [3:0] draw_r, draw_g, draw_b;
    wire [10:0] curr_x, curr_y;

    drawcon drawcon_inst (
        .clk(pixclk), .rst(rst),
        .chicken_x(chicken_x), .chicken_y(chicken_y),
        .chicken_facing(chicken_facing), .chicken_moving(chicken_moving),
        .game_started(game_started), .game_over(game_over),
        .score(score), .lives(lives),
        .lane_type_0(lt0),   .lane_type_1(lt1),   .lane_type_2(lt2),
        .lane_type_3(lt3),   .lane_type_4(lt4),   .lane_type_5(lt5),
        .lane_type_6(lt6),   .lane_type_7(lt7),   .lane_type_8(lt8),
        .lane_type_9(lt9),   .lane_type_10(lt10),  .lane_type_11(lt11),
        .lane_type_12(lt12), .lane_type_13(lt13),
        .obs_x_0(ox0),   .obs_x_1(ox1),   .obs_x_2(ox2),   .obs_x_3(ox3),
        .obs_x_4(ox4),   .obs_x_5(ox5),   .obs_x_6(ox6),   .obs_x_7(ox7),
        .obs_x_8(ox8),   .obs_x_9(ox9),   .obs_x_10(ox10),  .obs_x_11(ox11),
        .obs_x_12(ox12), .obs_x_13(ox13),
        .obs2_x_0(o2x0),   .obs2_x_1(o2x1),   .obs2_x_2(o2x2),   .obs2_x_3(o2x3),
        .obs2_x_4(o2x4),   .obs2_x_5(o2x5),   .obs2_x_6(o2x6),   .obs2_x_7(o2x7),
        .obs2_x_8(o2x8),   .obs2_x_9(o2x9),   .obs2_x_10(o2x10),  .obs2_x_11(o2x11),
        .obs2_x_12(o2x12), .obs2_x_13(o2x13),
        .curr_x(curr_x), .curr_y(curr_y),
        .draw_r(draw_r), .draw_g(draw_g), .draw_b(draw_b)
    );

    // ══════════════════════════════════════════════════════════
    // SECTION 9: VGA
    // ══════════════════════════════════════════════════════════
    vga vga_inst (
        .clk(pixclk), .rst(rst),
        .draw_r(draw_r), .draw_g(draw_g), .draw_b(draw_b),
        .curr_x(curr_x), .curr_y(curr_y),
        .pix_r(pix_r), .pix_g(pix_g), .pix_b(pix_b),
        .hsync(hsync), .vsync(vsync)
    );

    // ══════════════════════════════════════════════════════════
    // SECTION 10: Score + LEDs
    // ══════════════════════════════════════════════════════════
    score_display score_inst (
        .clk(sys_clk), .rst(rst),
        .score(score), .high_score(high_score),
        .seg(seg), .an(an)
    );

    assign led[7:0]   = score;
    assign led[8]     = (lives >= 3'd1);
    assign led[9]     = (lives >= 3'd2);
    assign led[10]    = (lives >= 3'd3);
    assign led[11]    = on_any_log;         // Debug: lit when on a log
    assign led[12]    = is_river;           // Debug: lit when on river lane
    assign led[13]    = log_carry_en;       // Debug: lit when being carried
    assign led[14]    = qry_dir;            // Debug: current lane direction
    assign led[15]    = game_over;

endmodule
