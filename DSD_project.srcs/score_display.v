`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      score_display.v
// Description:
//   Displays current score and high score on the Nexys 4DDR's
//   8-digit multiplexed 7-segment display.
//
//   Layout across the 8 digits (AN7..AN0):
//     AN7  AN6  AN5  AN4  AN3  AN2  AN1  AN0
//      H    i   [hi_tens] [hi_ones]  S  c  [sc_tens] [sc_ones]
//
//   Uses a clock divider from the 100 MHz system clock to scan
//   through each digit at ~1 kHz (imperceptible flicker).
//
//   Adapted from the Flappy Bird reference project's score_display.v
//   with modifications for Crossy Road labelling.
//////////////////////////////////////////////////////////////////////////////////

module score_display (
    input        clk,         // System clock (100 MHz)
    input        rst,         // Active-low reset
    input  [7:0] score,       // Current score (0–99)
    input  [7:0] high_score,  // High score (0–99)
    output reg [6:0] seg,     // Segment outputs (active low: a–g)
    output reg [7:0] an       // Anode enables (active low, one per digit)
);

    // ──────────────────────────────────────────────────────────
    // Clock divider for digit scanning
    // bits [18:16] cycle through 8 states ≈ every 2.6 ms
    // Total scan period ≈ 8 × 2.6 ms = 20.8 ms (48 Hz)
    // ──────────────────────────────────────────────────────────
    reg [18:0] clkdiv;

    always @(posedge clk or negedge rst) begin
        if (!rst)
            clkdiv <= 19'd0;
        else
            clkdiv <= clkdiv + 19'd1;
    end

    wire [2:0] sel = clkdiv[18:16];

    // ──────────────────────────────────────────────────────────
    // Digit value selection
    // Special values: 10 = 'H', 11 = 'i', 12 = 'S', 13 = 'c'
    // ──────────────────────────────────────────────────────────
    reg [3:0] digit_val;

    always @(*) begin
        // Default: blank
        digit_val = 4'd15;
        an = 8'b11111111;

        case (sel)
            3'd0: begin  // AN0: score ones
                digit_val = score % 10;
                an = 8'b11111110;
            end
            3'd1: begin  // AN1: score tens
                digit_val = score / 10;
                an = 8'b11111101;
            end
            3'd2: begin  // AN2: 'c'
                digit_val = 4'd13;
                an = 8'b11111011;
            end
            3'd3: begin  // AN3: 'S'
                digit_val = 4'd12;
                an = 8'b11110111;
            end
            3'd4: begin  // AN4: high_score ones
                digit_val = high_score % 10;
                an = 8'b11101111;
            end
            3'd5: begin  // AN5: high_score tens
                digit_val = high_score / 10;
                an = 8'b11011111;
            end
            3'd6: begin  // AN6: 'i'
                digit_val = 4'd11;
                an = 8'b10111111;
            end
            3'd7: begin  // AN7: 'H'
                digit_val = 4'd10;
                an = 8'b01111111;
            end
        endcase
    end

    // ──────────────────────────────────────────────────────────
    // 7-segment decoder (active low outputs)
    //   Segment mapping: seg[6:0] = gfedcba
    //   A '0' lights the segment, '1' turns it off
    // ──────────────────────────────────────────────────────────
    always @(*) begin
        case (digit_val)
            4'd0:    seg = 7'b1000000;  // 0
            4'd1:    seg = 7'b1111001;  // 1
            4'd2:    seg = 7'b0100100;  // 2
            4'd3:    seg = 7'b0110000;  // 3
            4'd4:    seg = 7'b0011001;  // 4
            4'd5:    seg = 7'b0010010;  // 5
            4'd6:    seg = 7'b0000010;  // 6
            4'd7:    seg = 7'b1111000;  // 7
            4'd8:    seg = 7'b0000000;  // 8
            4'd9:    seg = 7'b0010000;  // 9
            4'd10:   seg = 7'b0001001;  // H
            4'd11:   seg = 7'b1110001;  // i (segments b, c only, plus dp area)
            4'd12:   seg = 7'b0010010;  // S (same as 5)
            4'd13:   seg = 7'b0100111;  // c (segments d, e, g)
            default: seg = 7'b1111111;  // blank
        endcase
    end

endmodule
