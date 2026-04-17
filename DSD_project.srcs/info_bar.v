`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:    info_bar.v
// Description:
//   Renders the mandatory 100-pixel-tall info bar across the full
//   1440px display width. Uses the font_rom module to draw text
//   at 2× scale (16×32 pixels per character) for readability.
//////////////////////////////////////////////////////////////////////////////////

module info_bar (
    input      [10:0] curr_x,
    input      [10:0] curr_y,
    input      [7:0]  score,
    input      [2:0]  lives,
    input             game_over,
    output     [3:0]  pixel_r,
    output     [3:0]  pixel_g,
    output     [3:0]  pixel_b,
    output            in_info_bar
);

    // Info bar region detection
    localparam BAR_HEIGHT   = 11'd100;
    localparam BORDER_WIDTH = 11'd4;

    assign in_info_bar = (curr_y < BAR_HEIGHT);

    wire is_border = (curr_y < BORDER_WIDTH) ||
                     (curr_y >= BAR_HEIGHT - BORDER_WIDTH);

    // Colour palette
    localparam [11:0] COL_BORDER = 12'hFB0;  // Gold border
    localparam [11:0] COL_BG     = 12'h165;  // Dark teal background
    localparam [11:0] COL_TEXT   = 12'hFFF;  // White text
    localparam [11:0] COL_SCORE  = 12'hFF0;  // Yellow score digits
    localparam [11:0] COL_HEART  = 12'hF24;  // Red hearts
    localparam [11:0] COL_DEAD   = 12'hF44;  

    // Text string definitions (stored as arrays of 7-bit ASCII)

    // Title: "CROSSY ROAD" (11 chars)
    localparam TITLE_X     = 11'd40;
    localparam TITLE_Y     = 11'd10;
    localparam TITLE_LEN   = 5'd12;
    localparam TITLE_SCALE = 2;

    wire [6:0] title_char [0:11];

    assign title_char[0]  = 7'h43; // C
    assign title_char[1]  = 7'h52; // R
    assign title_char[2]  = 7'h4F; // O
    assign title_char[3]  = 7'h53; // S
    assign title_char[4]  = 7'h53; // S
    assign title_char[5]  = 7'h59; // Y
    assign title_char[6]  = 7'h20; // space
    
    assign title_char[7]  = 7'h43; // C
    assign title_char[8]  = 7'h48; // H
    assign title_char[9]  = 7'h41; // A
    assign title_char[10] = 7'h53; // S
    assign title_char[11] = 7'h4D; // M

    localparam ID1_X   = 11'd420;
    localparam ID1_Y   = 11'd14;
    localparam ID1_LEN = 5'd10;

    wire [6:0] id1_char [0:9];
    assign id1_char[0] = 7'h49; // I
    assign id1_char[1] = 7'h44; // D
    assign id1_char[2] = 7'h3A; // :
    assign id1_char[3] = 7'h32; // 2
    assign id1_char[4] = 7'h32; // 2
    assign id1_char[5] = 7'h31; // 1
    assign id1_char[6] = 7'h37; // 7
    assign id1_char[7] = 7'h33; // 3
    assign id1_char[8] = 7'h32; // 2
    assign id1_char[9] = 7'h31; // 1

    localparam ID2_X   = 11'd420;
    localparam ID2_Y   = 11'd52;
    localparam ID2_LEN = 5'd10;

    wire [6:0] id2_char [0:9];
    assign id2_char[0] = 7'h49; // I
    assign id2_char[1] = 7'h44; // D
    assign id2_char[2] = 7'h3A; // :
    assign id2_char[3] = 7'h32; // 2
    assign id2_char[4] = 7'h32; // 2
    assign id2_char[5] = 7'h33; // 3
    assign id2_char[6] = 7'h33; // 3
    assign id2_char[7] = 7'h33; // 3
    assign id2_char[8] = 7'h38; // 8
    assign id2_char[9] = 7'h30; // 0

    // Score label: "SCORE:" (6 chars) at x=800, y=14
    localparam SCR_LABEL_X   = 11'd800;
    localparam SCR_LABEL_Y   = 11'd14;
    localparam SCR_LABEL_LEN = 5'd6;

    wire [6:0] scr_label_char [0:5];
    assign scr_label_char[0] = 7'h53; // S
    assign scr_label_char[1] = 7'h43; // C
    assign scr_label_char[2] = 7'h4F; // O
    assign scr_label_char[3] = 7'h52; // R
    assign scr_label_char[4] = 7'h45; // E
    assign scr_label_char[5] = 7'h3A; // :

    // Score digits: Now 3 chars wide at x=896, y=14 
    localparam SCR_DIGIT_X = 11'd896;
    localparam SCR_DIGIT_Y = 11'd14;

    wire [6:0] score_huns_char = 7'h30 + (score / 8'd100);             // Extracts 100s
    wire [6:0] score_tens_char = 7'h30 + ((score / 8'd10) % 8'd10);    // Extracts 10s and caps at 9
    wire [6:0] score_ones_char = 7'h30 + (score % 8'd10);              // Extracts 1s

    // Lives label: "LIVES:" (6 chars) at x=800, y=52
    localparam LIV_LABEL_X   = 11'd800;
    localparam LIV_LABEL_Y   = 11'd52;
    localparam LIV_LABEL_LEN = 5'd6;

    wire [6:0] liv_label_char [0:5];
    assign liv_label_char[0] = 7'h4C; // L 
    assign liv_label_char[1] = 7'h49; // I
    assign liv_label_char[2] = 7'h56; // V
    assign liv_label_char[3] = 7'h45; // E
    assign liv_label_char[4] = 7'h53; // S
    assign liv_label_char[5] = 7'h3A; // :

    // Font ROM instance
    reg  [10:0] font_addr;
    wire [7:0]  font_data;

    font_rom font_inst (
        .addr      (font_addr),
        .font_data (font_data)
    );

    // Text rendering helper function

    reg [11:0] pixel_colour;
    reg        pixel_on;

    wire [10:0] dx_title    = curr_x - TITLE_X;
    wire [10:0] dy_title    = curr_y - TITLE_Y;
    wire        in_title    = (curr_x >= TITLE_X) &&
                              (curr_x < TITLE_X + TITLE_LEN * 8 * TITLE_SCALE) &&
                              (curr_y >= TITLE_Y) &&
                              (curr_y < TITLE_Y + 16 * TITLE_SCALE);
    wire [3:0]  title_idx   = dx_title / (8 * TITLE_SCALE);
    wire [2:0]  title_col   = (dx_title / TITLE_SCALE) % 8;
    wire [3:0]  title_row   = (dy_title / TITLE_SCALE) % 16;

    wire [10:0] dx_id1      = curr_x - ID1_X;
    wire [10:0] dy_id1      = curr_y - ID1_Y;
    wire        in_id1      = (curr_x >= ID1_X) &&
                              (curr_x < ID1_X + ID1_LEN * 16) &&
                              (curr_y >= ID1_Y) && (curr_y < ID1_Y + 32);
    wire [3:0]  id1_idx     = dx_id1 / 16;
    wire [2:0]  id1_col     = (dx_id1 / 2) % 8;
    wire [3:0]  id1_row     = (dy_id1 / 2) % 16;

    wire [10:0] dx_id2      = curr_x - ID2_X;
    wire [10:0] dy_id2      = curr_y - ID2_Y;
    wire        in_id2      = (curr_x >= ID2_X) &&
                              (curr_x < ID2_X + ID2_LEN * 16) &&
                              (curr_y >= ID2_Y) && (curr_y < ID2_Y + 32);
    wire [3:0]  id2_idx     = dx_id2 / 16;
    wire [2:0]  id2_col     = (dx_id2 / 2) % 8;
    wire [3:0]  id2_row     = (dy_id2 / 2) % 16;

    wire [10:0] dx_scrl     = curr_x - SCR_LABEL_X;
    wire [10:0] dy_scrl     = curr_y - SCR_LABEL_Y;
    wire        in_scr_label= (curr_x >= SCR_LABEL_X) &&
                              (curr_x < SCR_LABEL_X + SCR_LABEL_LEN * 16) &&
                              (curr_y >= SCR_LABEL_Y) && (curr_y < SCR_LABEL_Y + 32);
    wire [3:0]  scrl_idx    = dx_scrl / 16;
    wire [2:0]  scrl_col    = (dx_scrl / 2) % 8;
    wire [3:0]  scrl_row    = (dy_scrl / 2) % 16;

    wire [10:0] dx_scrd     = curr_x - SCR_DIGIT_X;
    wire [10:0] dy_scrd     = curr_y - SCR_DIGIT_Y;
    //Increased width to 3 * 16 to fit 3 digits
    wire        in_scr_digit= (curr_x >= SCR_DIGIT_X) &&
                              (curr_x < SCR_DIGIT_X + 3 * 16) &&
                              (curr_y >= SCR_DIGIT_Y) && (curr_y < SCR_DIGIT_Y + 32);
    wire [3:0]  scrd_idx    = dx_scrd / 16;
    wire [2:0]  scrd_col    = (dx_scrd / 2) % 8;
    wire [3:0]  scrd_row    = (dy_scrd / 2) % 16;

    wire [10:0] dx_livl     = curr_x - LIV_LABEL_X;
    wire [10:0] dy_livl     = curr_y - LIV_LABEL_Y;
    wire        in_liv_label= (curr_x >= LIV_LABEL_X) &&
                              (curr_x < LIV_LABEL_X + LIV_LABEL_LEN * 16) &&
                              (curr_y >= LIV_LABEL_Y) && (curr_y < LIV_LABEL_Y + 32);
    wire [3:0]  livl_idx    = dx_livl / 16;
    wire [2:0]  livl_col    = (dx_livl / 2) % 8;
    wire [3:0]  livl_row    = (dy_livl / 2) % 16;

    // Lives hearts: simple filled squares at x=896, y=56, 20px apart
    localparam HEART_X = 11'd896;
    localparam HEART_Y = 11'd56;
    wire in_heart = (curr_y >= HEART_Y) && (curr_y < HEART_Y + 20) &&
                    (curr_x >= HEART_X) && (curr_x < HEART_X + 3 * 24);
    wire [1:0] heart_idx = (curr_x - HEART_X) / 24;
    wire heart_filled = (curr_x - HEART_X) % 24 < 20;  // 20px block, 4px gap
    wire heart_on = in_heart && heart_filled && (heart_idx < lives);

    // Priority mux: determine font address and colour
    always @(*) begin
        pixel_on     = 1'b0;
        pixel_colour = COL_BG;
        font_addr    = 11'd0;

        if (is_border) begin
            pixel_colour = COL_BORDER;
            pixel_on     = 1'b1;

        end else if (in_title) begin
            font_addr = {title_char[title_idx], title_row};
            if (font_data[7 - title_col]) begin
                pixel_colour = COL_TEXT;
                pixel_on     = 1'b1;
            end

        end else if (in_id1) begin
            font_addr = {id1_char[id1_idx], id1_row};
            if (font_data[7 - id1_col]) begin
                pixel_colour = COL_TEXT;
                pixel_on     = 1'b1;
            end

        end else if (in_id2) begin
            font_addr = {id2_char[id2_idx], id2_row};
            if (font_data[7 - id2_col]) begin
                pixel_colour = COL_TEXT;
                pixel_on     = 1'b1;
            end

        end else if (in_scr_label) begin
            font_addr = {scr_label_char[scrl_idx], scrl_row};
            if (font_data[7 - scrl_col]) begin
                pixel_colour = COL_TEXT;
                pixel_on     = 1'b1;
            end

        end else if (in_scr_digit) begin
            // Selects between 100s, 10s, and 1s depending on index
            font_addr = {(scrd_idx == 0) ? score_huns_char :
                         (scrd_idx == 1) ? score_tens_char : score_ones_char,
                         scrd_row};
            if (font_data[7 - scrd_col]) begin
                pixel_colour = COL_SCORE;
                pixel_on     = 1'b1;
            end

        end else if (in_liv_label) begin
            font_addr = {liv_label_char[livl_idx], livl_row};
            if (font_data[7 - livl_col]) begin
                pixel_colour = COL_TEXT;
                pixel_on     = 1'b1;
            end

        end else if (heart_on) begin
            pixel_colour = COL_HEART;
            pixel_on     = 1'b1;
        end
    end

    // Output: text pixel or background
    wire [11:0] final_colour = pixel_on ? pixel_colour : COL_BG;

    assign pixel_r = final_colour[11:8];
    assign pixel_g = final_colour[7:4];
    assign pixel_b = final_colour[3:0];

endmodule
