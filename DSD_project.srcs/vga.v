`timescale 1ns / 1ps
// Module: vga.v
// Purpose: VGA timing controller for 1440x900 @ ~60 Hz on the Nexys 4DDR.
//          Generates hsync and vsync pulses and outputs visible-region pixel
//          coordinates (curr_x, curr_y) used by drawcon to determine pixel colour.
//          During the blanking interval RGB outputs are forced to zero.
//
// Timing (ES3B2 Lab 4 specification, pixel clock = 106.47 MHz):
//   Horizontal (hcount 0-1903, 1904 clocks per line):
//     hsync active  0-151    (152 clocks)
//     back porch  152-383    (232 clocks)
//     visible     384-1823   (1440 pixels)
//     front porch 1824-1903  (80 clocks)
//
//   Vertical (vcount 0-931, 932 lines per frame):
//     vsync active  0-2      (3 lines)
//     back porch    3-30     (28 lines)
//     visible      31-930    (900 lines)
//     front porch 931-931    (1 line)
//
//   Frame rate: 106.47 MHz / (1904 × 932) ≈ 60.0 Hz

module vga (
    input             clk,      // Pixel clock (106.47 MHz from Clocking Wizard)
    input             rst,      // Active-low reset
    input      [3:0]  draw_r,   // Red channel from drawcon
    input      [3:0]  draw_g,
    input      [3:0]  draw_b,
    output reg [10:0] curr_x,   // Visible pixel X (0-1439), 0 during blanking
    output reg [10:0] curr_y,   // Visible pixel Y (0-899), 0 during blanking
    output     [3:0]  pix_r,    // VGA red output (0 during blanking)
    output     [3:0]  pix_g,
    output     [3:0]  pix_b,
    output            hsync,    // Horizontal sync, active HIGH
    output            vsync     // Vertical sync, active HIGH
);

    // Timing parameters
    localparam H_SYNC_END  = 11'd151;   // hsync active: hcount in [0, 151]
    localparam H_BACK_END  = 11'd383;   // Back porch ends at 383
    localparam H_VIS_START = 11'd384;   // First visible column
    localparam H_VIS_END   = 11'd1823;  // Last visible column
    localparam H_MAX       = 11'd1903;  // hcount wraps after this value

    localparam V_SYNC_END  = 10'd2;     // vsync active: vcount in [0, 2]
    localparam V_BACK_END  = 10'd30;    // Back porch ends at 30
    localparam V_VIS_START = 10'd31;    // First visible row
    localparam V_VIS_END   = 10'd930;   // Last visible row
    localparam V_MAX       = 10'd931;   // vcount wraps after this value

    reg [10:0] hcount;
    reg [9:0]  vcount;

    // Horizontal and vertical counters
    // vcount increments each time hcount completes a full line (wraps at H_MAX).
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            hcount <= 11'd0;
            vcount <= 10'd0;
        end else begin
            if (hcount == H_MAX) begin
                hcount <= 11'd0;
                vcount <= (vcount == V_MAX) ? 10'd0 : vcount + 10'd1;
            end else begin
                hcount <= hcount + 11'd1;
            end
        end
    end

    // Sync pulse generation (active HIGH for Nexys 4DDR VGA DAC)
    assign hsync = (hcount <= H_SYNC_END);
    assign vsync = (vcount <= V_SYNC_END);

    // Visible region detection
    wire h_visible = (hcount >= H_VIS_START) && (hcount <= H_VIS_END);
    wire v_visible = (vcount >= V_VIS_START) && (vcount <= V_VIS_END);
    wire visible   = h_visible && v_visible;

    // Pixel coordinate outputs
    // (curr_x=0, curr_y=0) corresponds to the first visible pixel at
    // (hcount=384, vcount=31). Coordinates are held at 0 during blanking.
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            curr_x <= 11'd0;
            curr_y <= 11'd0;
        end else begin
            curr_x <= h_visible ? (hcount - H_VIS_START) : 11'd0;
            curr_y <= v_visible ? (vcount - V_VIS_START) : 11'd0;
        end
    end

    // RGB output gating: force outputs to zero during blanking to prevent
    // colour bleed into the sync and porch regions.
    assign pix_r = visible ? draw_r : 4'h0;
    assign pix_g = visible ? draw_g : 4'h0;
    assign pix_b = visible ? draw_b : 4'h0;

endmodule
