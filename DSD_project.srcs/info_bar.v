`timescale 1ns / 1ps
// Module: info_bar.v
// Purpose: Renders the 100-pixel HUD strip at the top of the screen (rows 0-99).
//          All text is drawn by indexing into font_rom - an 8×16 IBM VGA glyph
//          bitmap ROM - and scaling each glyph to 2× (16×32 px) by halving the
//          pixel offset before the ROM lookup.
//
// Heart sprite sheet geometry (this revision):
//   File: heart_64x20.mem - actual used area is 60×20 px (3 frames × 20 px wide).
//   Frame stride: 20 px horizontally (heart_frame * 20 selects the frame column).
//   ROM address: row * 60 + local_x + frame_offset
//   Each heart is rendered into a 24-px-wide display slot (20 px sprite + 4 px gap).
//   The gap is clipped by the (heart_local_x < 20) guard in in_heart_box.
//
// Layout (x positions, left to right):
//   40   px - "CROSSY CHASM" title (2× scaled, white)
//   420  px - Student IDs 2217321 / 2233381 (2× scaled, stacked vertically)
//   800  px - "SCORE:" label and three-digit value
//   800  px - "LIVES:" label and heart sprite row
//
// Authors: 2217321 & 2233381

module info_bar (
    input             clk,
    input      [10:0] curr_x,
    input      [10:0] curr_y,
    input      [7:0]  score,
    input      [2:0]  lives,
    input             game_over,
    input      [1:0]  heart_frame,   // Selects one of three animation frames (0-2)
    output     [3:0]  pixel_r,
    output     [3:0]  pixel_g,
    output     [3:0]  pixel_b,
    output            in_info_bar
);

    localparam BAR_HEIGHT   = 11'd100;
    localparam BORDER_WIDTH = 11'd4;  // Amber border band at top and bottom of bar

    assign in_info_bar = (curr_y < BAR_HEIGHT);

    // Border band: top 4 rows and bottom 4 rows of the info bar
    wire is_border = (curr_y < BORDER_WIDTH) || (curr_y >= BAR_HEIGHT - BORDER_WIDTH);

    // Colour palette (12-bit R4G4B4)
    localparam [11:0] COL_BORDER = 12'hFB0; // Amber
    localparam [11:0] COL_BG     = 12'h165; // Dark teal background
    localparam [11:0] COL_TEXT   = 12'hFFF; // White - title and ID strings
    localparam [11:0] COL_SCORE  = 12'hFF0; // Yellow - score digit highlight
    localparam [11:0] COL_DEAD   = 12'hF44; // Red (reserved)

    // Title string: "CROSSY CHASM" (12 characters, ASCII)
    localparam TITLE_X     = 11'd40;
    localparam TITLE_Y     = 11'd10;
    localparam TITLE_LEN   = 5'd12;
    localparam TITLE_SCALE = 2;     // Each glyph rendered at 16×32 px (2× the 8×16 ROM glyph)

    wire [6:0] title_char [0:11];
    assign title_char[0]  = 7'h43; // C
    assign title_char[1]  = 7'h52; // R
    assign title_char[2]  = 7'h4F; // O
    assign title_char[3]  = 7'h53; // S
    assign title_char[4]  = 7'h53; // S
    assign title_char[5]  = 7'h59; // Y
    assign title_char[6]  = 7'h20; // (space)
    assign title_char[7]  = 7'h43; // C
    assign title_char[8]  = 7'h48; // H
    assign title_char[9]  = 7'h41; // A
    assign title_char[10] = 7'h53; // S
    assign title_char[11] = 7'h4D; // M

    // Student ID 1: 2217321
    localparam ID1_X   = 11'd420;
    localparam ID1_Y   = 11'd14;
    localparam ID1_LEN = 5'd7;

    wire [6:0] id1_char [0:6];
    assign id1_char[0] = 7'h32; // 2
    assign id1_char[1] = 7'h32; // 2
    assign id1_char[2] = 7'h31; // 1
    assign id1_char[3] = 7'h37; // 7
    assign id1_char[4] = 7'h33; // 3
    assign id1_char[5] = 7'h32; // 2
    assign id1_char[6] = 7'h31; // 1

    // Student ID 2: 2233380
    localparam ID2_X   = 11'd420;
    localparam ID2_Y   = 11'd52;  // Second row, 38 px below ID1
    localparam ID2_LEN = 5'd7;

    wire [6:0] id2_char [0:6];
    assign id2_char[0] = 7'h32; // 2
    assign id2_char[1] = 7'h32; // 2
    assign id2_char[2] = 7'h33; // 3
    assign id2_char[3] = 7'h33; // 3
    assign id2_char[4] = 7'h33; // 3
    assign id2_char[5] = 7'h38; // 8
    assign id2_char[6] = 7'h30; // 0

    // "SCORE:" label
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

    // Score digit positions - three 16-px-wide glyphs (2× scaled)
    localparam SCR_DIGIT_X = 11'd896;
    localparam SCR_DIGIT_Y = 11'd14;

    // BCD decomposition: 7'h30 = ASCII '0'; adding the BCD digit gives the correct glyph index
    wire [6:0] score_huns_char = 7'h30 + (score / 8'd100);
    wire [6:0] score_tens_char = 7'h30 + ((score / 8'd10) % 8'd10);
    wire [6:0] score_ones_char = 7'h30 + (score % 8'd10);

    // "LIVES:" label
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

    // font_rom interface
    // Address format: {ascii[6:0], row[3:0]} = 11 bits.
    // Output font_data is an 8-bit row bitmap; bit 7 is the leftmost pixel.
    reg  [10:0] font_addr;
    wire [7:0]  font_data;

    font_rom font_inst (.addr(font_addr), .font_data(font_data));

    reg [11:0] pixel_colour;
    reg        pixel_on;

    // Title region hit-test and glyph decode (2× scale)
    // At TITLE_SCALE=2 each glyph is 16×32 screen pixels.
    // title_idx = character within string; title_col/row = pixel within 8×16 glyph (pre-scale).
    wire [10:0] dx_title  = curr_x - TITLE_X;
    wire [10:0] dy_title  = curr_y - TITLE_Y;
    wire        in_title  = (curr_x >= TITLE_X) && (curr_x < TITLE_X + TITLE_LEN * 8 * TITLE_SCALE)
                         && (curr_y >= TITLE_Y) && (curr_y < TITLE_Y + 16 * TITLE_SCALE);
    wire [3:0]  title_idx = dx_title / (8 * TITLE_SCALE);
    wire [2:0]  title_col = (dx_title / TITLE_SCALE) % 8;
    wire [3:0]  title_row = (dy_title / TITLE_SCALE) % 16;

    // ID1 text region - 2× scale, 16×32 px per glyph
    wire [10:0] dx_id1 = curr_x - ID1_X;
    wire [10:0] dy_id1 = curr_y - ID1_Y;
    wire        in_id1 = (curr_x >= ID1_X) && (curr_x < ID1_X + ID1_LEN * 16)
                      && (curr_y >= ID1_Y) && (curr_y < ID1_Y + 32);
    wire [3:0]  id1_idx = dx_id1 / 16;
    wire [2:0]  id1_col = (dx_id1 / 2) % 8;
    wire [3:0]  id1_row = (dy_id1 / 2) % 16;

    // ID2 text region
    wire [10:0] dx_id2 = curr_x - ID2_X;
    wire [10:0] dy_id2 = curr_y - ID2_Y;
    wire        in_id2 = (curr_x >= ID2_X) && (curr_x < ID2_X + ID2_LEN * 16)
                      && (curr_y >= ID2_Y) && (curr_y < ID2_Y + 32);
    wire [3:0]  id2_idx = dx_id2 / 16;
    wire [2:0]  id2_col = (dx_id2 / 2) % 8;
    wire [3:0]  id2_row = (dy_id2 / 2) % 16;

    // "SCORE:" label region
    wire [10:0] dx_scrl      = curr_x - SCR_LABEL_X;
    wire [10:0] dy_scrl      = curr_y - SCR_LABEL_Y;
    wire        in_scr_label = (curr_x >= SCR_LABEL_X) && (curr_x < SCR_LABEL_X + SCR_LABEL_LEN * 16)
                            && (curr_y >= SCR_LABEL_Y) && (curr_y < SCR_LABEL_Y + 32);
    wire [3:0]  scrl_idx     = dx_scrl / 16;
    wire [2:0]  scrl_col     = (dx_scrl / 2) % 8;
    wire [3:0]  scrl_row     = (dy_scrl / 2) % 16;

    // Score digit region - three digits, each 16 px wide
    wire [10:0] dx_scrd      = curr_x - SCR_DIGIT_X;
    wire [10:0] dy_scrd      = curr_y - SCR_DIGIT_Y;
    wire        in_scr_digit = (curr_x >= SCR_DIGIT_X) && (curr_x < SCR_DIGIT_X + 3 * 16)
                            && (curr_y >= SCR_DIGIT_Y) && (curr_y < SCR_DIGIT_Y + 32);
    wire [3:0]  scrd_idx     = dx_scrd / 16; // 0=hundreds, 1=tens, 2=ones
    wire [2:0]  scrd_col     = (dx_scrd / 2) % 8;
    wire [3:0]  scrd_row     = (dy_scrd / 2) % 16;

    // "LIVES:" label region
    wire [10:0] dx_livl      = curr_x - LIV_LABEL_X;
    wire [10:0] dy_livl      = curr_y - LIV_LABEL_Y;
    wire        in_liv_label = (curr_x >= LIV_LABEL_X) && (curr_x < LIV_LABEL_X + LIV_LABEL_LEN * 16)
                            && (curr_y >= LIV_LABEL_Y) && (curr_y < LIV_LABEL_Y + 32);
    wire [3:0]  livl_idx     = dx_livl / 16;
    wire [2:0]  livl_col     = (dx_livl / 2) % 8;
    wire [3:0]  livl_row     = (dy_livl / 2) % 16;


    // Heart sprite rendering
    // Sprite sheet: 60×20 px - three 20-px-wide animation frames laid horizontally.
    //   Frame 0: columns  0-19
    //   Frame 1: columns 20-39
    //   Frame 2: columns 40-59
    //
    // Display layout: three hearts side by side, each in a 24-px-wide slot.
    //   Slot structure: 20 px sprite | 4 px gap
    //   heart_local_x = column within the current 24-px slot (wraps at 24)
    //   heart_idx     = which of the three heart positions (0, 1, or 2)
    //
    // in_heart_box clips the 4-px gap with (heart_local_x < 20) so only the
    // 20-px sprite region of each slot reaches the ROM.
    // heart_on additionally gates on heart_idx < lives so lost lives render nothing.
    //
    // ROM address:
    //   row_offset   = (curr_y - HEART_Y) * 60    - row stride is full sheet width
    //   col_offset   = heart_local_x               - column within current heart slot
    //   frame_offset = heart_frame * 20            - selects the active animation frame
    //   hrt_addr     = row_offset + col_offset + frame_offset
    localparam HEART_X = 11'd896;
    localparam HEART_Y = 11'd56;

    // Column within a 24-px slot (mod 24 via % operator - synthesises to subtractor chain)
    wire [10:0] heart_local_x = (curr_x - HEART_X) % 24;
    // Which of the three hearts is the beam currently over?
    wire [1:0]  heart_idx     = (curr_x - HEART_X) / 24;

    // Valid sprite pixel: inside the 20-px sprite sub-region of a slot, within the
    // 20-row height, and within the 3-heart horizontal span
    wire in_heart_box = (curr_y >= HEART_Y) && (curr_y < HEART_Y + 20)
                     && (curr_x >= HEART_X) && (curr_x < HEART_X + 3 * 24)
                     && (heart_local_x < 20);         // Clip the 4-px inter-heart gap
    wire heart_on = in_heart_box && (heart_idx < lives);

    // Row stride is 60 (full sheet width, not 20) because all three frames share
    // the same row in the .mem file.  frame_offset shifts into the correct frame column.
    wire [10:0] hrt_addr = ((curr_y - HEART_Y) * 60) + heart_local_x + (heart_frame * 20);
    wire [11:0] heart_pixel;

    // Sheet is 60×20; WIDTH=60 sets the ROM depth to 60*20=1200 entries.
    sprite_rom #(.WIDTH(60), .HEIGHT(20), .MEM_FILE("heart_60x20.mem")) heart_rom (
        .clk(clk), .addr(hrt_addr), .data(heart_pixel)
    );

    // Info bar priority pixel mux (combinational)
    // Evaluated every pixel clock for scan positions within the info bar.
    // Priority: border > title > ID1 > ID2 > score label > score digits >
    //           lives label > heart sprite > background.
    // font_addr is driven combinationally; the ROM output is valid one cycle later -
    // drawcon adds the matching pipeline stage for its registered hit signals.
    always @(*) begin
        pixel_on     = 1'b0;
        pixel_colour = COL_BG;
        font_addr    = 11'd0;

        if (is_border) begin
            pixel_colour = COL_BORDER;
            pixel_on     = 1'b1;

        end else if (in_title) begin
            // font_addr = {7-bit ASCII, 4-bit glyph row}
            // font_data[7 - title_col] selects the column bit MSB-first
            font_addr = {title_char[title_idx], title_row};
            if (font_data[7 - title_col]) begin pixel_colour = COL_TEXT; pixel_on = 1'b1; end

        end else if (in_id1) begin
            font_addr = {id1_char[id1_idx], id1_row};
            if (font_data[7 - id1_col]) begin pixel_colour = COL_TEXT; pixel_on = 1'b1; end

        end else if (in_id2) begin
            font_addr = {id2_char[id2_idx], id2_row};
            if (font_data[7 - id2_col]) begin pixel_colour = COL_TEXT; pixel_on = 1'b1; end

        end else if (in_scr_label) begin
            font_addr = {scr_label_char[scrl_idx], scrl_row};
            if (font_data[7 - scrl_col]) begin pixel_colour = COL_TEXT; pixel_on = 1'b1; end

        end else if (in_scr_digit) begin
            // Select hundreds, tens, or ones ASCII glyph based on scrd_idx
            font_addr = {(scrd_idx == 0) ? score_huns_char :
                         (scrd_idx == 1) ? score_tens_char : score_ones_char,
                         scrd_row};
            if (font_data[7 - scrd_col]) begin pixel_colour = COL_SCORE; pixel_on = 1'b1; end

        end else if (in_liv_label) begin
            font_addr = {liv_label_char[livl_idx], livl_row};
            if (font_data[7 - livl_col]) begin pixel_colour = COL_TEXT; pixel_on = 1'b1; end

        end else if (heart_on && heart_pixel != 12'hF0F) begin
            // Magenta (F0F) is the transparency key - fall through to COL_BG for those pixels
            pixel_colour = heart_pixel;
            pixel_on     = 1'b1;
        end
    end

    // Drive output channels from the selected colour, defaulting to background
    wire [11:0] final_colour = pixel_on ? pixel_colour : COL_BG;
    assign pixel_r = final_colour[11:8];
    assign pixel_g = final_colour[7:4];
    assign pixel_b = final_colour[3:0];

endmodule
