`timescale 1ns / 1ps

module score_display(
    input clk,
    input rst,
    input game_over,
    input [7:0] score,
    input [7:0] high_score,
    output reg [6:0] seg, // 7 segments (A-G)
    output reg [7:0] an   // 8 anodes
);

    reg [16:0] refresh_counter;
    always @(posedge clk or negedge rst) begin
        if (!rst) refresh_counter <= 0;
        else      refresh_counter <= refresh_counter + 1;
    end
    wire [2:0] digit_sel = refresh_counter[16:14];

    // Binary to BCD Conversion 
    wire [3:0] s_ones = score % 10;
    wire [3:0] s_tens = (score / 10) % 10;
    wire [3:0] s_huns = score / 100;
    
    wire [3:0] h_ones = high_score % 10;
    wire [3:0] h_tens = (high_score / 10) % 10;
    wire [3:0] h_huns = high_score / 100;

    // Digit Selection Mux 
    reg [3:0] current_digit;
    always @(*) begin
        case (digit_sel)
            3'd0: begin an = 8'b11111110; current_digit = s_ones; end // Rightmost (Score)
            3'd1: begin an = 8'b11111101; current_digit = s_tens; end
            3'd2: begin an = 8'b11111011; current_digit = s_huns; end
            3'd3: begin an = 8'b11110111; current_digit = 4'hA;   end // Blank Space
            3'd4: begin an = 8'b11101111; current_digit = 4'hA;   end // Blank Space
            3'd5: begin an = 8'b11011111; current_digit = h_ones; end // Leftmost (High Score)
            3'd6: begin an = 8'b10111111; current_digit = h_tens; end
            3'd7: begin an = 8'b01111111; current_digit = h_huns; end
        endcase
    end

    // ── 4. 7-Segment Hex Decoder & GAME OVER Override ──
    // Active LOW standard: 0 turns the LED segment ON.
    always @(*) begin
        if (game_over) begin
            // Displays "G A n E  O u E r" 
            case (digit_sel)
                3'd7: seg = 7'b0100001; // G 
                3'd6: seg = 7'b0001000; // A 
                3'd5: seg = 7'b0101010; // n (M)
                3'd4: seg = 7'b0000110; // E 
                3'd3: seg = 7'b1000000; // O 
                3'd2: seg = 7'b1100011; // u (V)
                3'd1: seg = 7'b0000110; // E 
                3'd0: seg = 7'b0101111; // r 
            endcase
        end else begin
            // Standard Numbers
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
                default: seg = 7'b1111111; // Blank for 4'hA
            endcase
        end
    end
endmodule
