`timescale 1ns / 1ps
// Module: score_display.v
// Purpose: Drives the Nexys 4DDR's eight 7-segment displays using time-division
//          multiplexing. The right three digits show the current score, the left
//          three show the high score, and digits 3-4 are blank separators.
//          When game_over is asserted the numeric display is replaced with the
//          text string "GAME OUEr" approximated in 7-segment glyphs.
//
// Multiplexing principle: only one anode is driven LOW at a time. Cycling
// through all eight digits faster than ~100 Hz exploits persistence of vision to
// make all digits appear simultaneously lit. Refresh rate:
//   100 MHz / 2^17 ≈ 763 Hz per full frame → ~95 Hz per individual digit.

module score_display (
    input             clk,
    input             rst,
    input             game_over,
    input      [7:0]  score,
    input      [7:0]  high_score,
    output reg [6:0]  seg,  // Segment drive lines A-G, active LOW
    output reg [7:0]  an    // Anode enable lines, active LOW (one bit per digit)
);

    // Refresh counter and digit select
    // Bits [16:14] divide the counter by 2^14 = 16,384, producing a 3-bit index
    // that cycles through all 8 digit positions at ~763 Hz.
    reg [16:0] refresh_counter;
    always @(posedge clk or negedge rst) begin
        if (!rst) refresh_counter <= 0;
        else      refresh_counter <= refresh_counter + 1;
    end
    wire [2:0] digit_sel = refresh_counter[16:14];

    // BCD extraction
    // Vivado synthesises integer division and modulo on constants to combinational
    // logic. Three-digit decomposition: hundreds = n/100, tens = (n/10)%10, ones = n%10.
    wire [3:0] s_ones = score      % 10;
    wire [3:0] s_tens = (score     / 10) % 10;
    wire [3:0] s_huns = score      / 100;

    wire [3:0] h_ones = high_score % 10;
    wire [3:0] h_tens = (high_score / 10) % 10;
    wire [3:0] h_huns = high_score / 100;

    // Digit select mux
    // an is active LOW: a single 0 bit enables that digit's common cathode.
    // Positions 3-4 are driven with 4'hA which the decoder maps to blank (all OFF).
    reg [3:0] current_digit;
    always @(*) begin
        case (digit_sel)
            3'd0: begin an = 8'b11111110; current_digit = s_ones; end // Rightmost — score ones
            3'd1: begin an = 8'b11111101; current_digit = s_tens; end // Score tens
            3'd2: begin an = 8'b11111011; current_digit = s_huns; end // Score hundreds
            3'd3: begin an = 8'b11110111; current_digit = 4'hA;   end // Blank separator
            3'd4: begin an = 8'b11101111; current_digit = 4'hA;   end // Blank separator
            3'd5: begin an = 8'b11011111; current_digit = h_ones; end // High score ones
            3'd6: begin an = 8'b10111111; current_digit = h_tens; end // High score tens
            3'd7: begin an = 8'b01111111; current_digit = h_huns; end // Leftmost — high score hundreds
        endcase
    end

    // 7-segment decoder with game-over override
    // Segment encoding is active LOW: bit = 0 turns that segment ON.
    // Bit order within seg[6:0]: {g, f, e, d, c, b, a} — standard Nexys mapping.
    //
    // When game_over is high the numeric decoder is bypassed and a fixed glyph
    // pattern spelling "GAME OUEr" (best 7-segment approximation) is displayed.
    always @(*) begin
        if (game_over) begin
            // "G A n E  O U E r" across all 8 digits (left to right = digit 7 to 0)
            case (digit_sel)
                3'd7: seg = 7'b0000010; // G — segments a,b,c,d,f,g
                3'd6: seg = 7'b0001000; // A — segments a,b,c,e,f,g
                3'd5: seg = 7'b0101010; // n — segments c,e,g (lower-case approximation)
                3'd4: seg = 7'b0000110; // E — segments a,d,e,f,g
                3'd3: seg = 7'b1000000; // O — segments a,b,c,d,e,f
                3'd2: seg = 7'b1000001; // U — segments b,c,d,e,f
                3'd1: seg = 7'b0000110; // E — segments a,d,e,f,g
                3'd0: seg = 7'b0101111; // r — segments e,g (lower-case approximation)
            endcase
        end else begin
            // Standard 0-9 numeric glyphs; 4'hA produces blank (all segments OFF).
            case (current_digit)
                4'h0: seg = 7'b1000000;
                4'h1: seg = 7'b1111001;
                4'h2: seg = 7'b0100100;
                4'h3: seg = 7'b0110000;
                4'h4: seg = 7'b0011001;
                4'h5: seg = 7'b0010010;
                4'h6: seg = 7'b0000010;
                4'h7: seg = 7'b1111000;
                4'h8: seg = 7'b0000000;
                4'h9: seg = 7'b0010000;
                default: seg = 7'b1111111; // Blank — all segments OFF
            endcase
        end
    end

endmodule
