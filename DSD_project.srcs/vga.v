`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      vga.v
// Description:
//   VGA controller for 1440×900 @ ~60 Hz on the Nexys 4DDR.
//   Pixel clock = 106.47 MHz (from Clocking Wizard IP).
//
//   Generates horizontal and vertical sync pulses, and outputs
//   visible-region pixel coordinates (curr_x, curr_y) used by the
//   drawing logic to determine what colour each pixel should be.
//
//   During the blanking interval, RGB outputs are forced to zero
//   regardless of the draw_r/g/b inputs.
//
// Timing (from ES3B2 Lab 4 specification):
//   Horizontal: hcount 0–1903 (1904 total per line)
//     hsync active:    hcount in [0, 151]      (152 clocks)
//     back porch:      hcount in [152, 383]     (232 clocks)
//     visible:         hcount in [384, 1823]    (1440 pixels)
//     front porch:     hcount in [1824, 1903]   (80 clocks)
//
//   Vertical: vcount 0–931 (932 total per frame)
//     vsync active:    vcount in [0, 2]         (3 lines)
//     back porch:      vcount in [3, 30]        (28 lines)
//     visible:         vcount in [31, 930]      (900 lines)
//     front porch:     vcount in [931, 931]     (1 line)
//
//   Frame rate: 106.47 MHz / (1904 × 932) ≈ 60.0 Hz
//////////////////////////////////////////////////////////////////////////////////

module vga (
    input             clk,       // Pixel clock (106.47 MHz)
    input             rst,       // Active-low reset
    input      [3:0]  draw_r,    // Red channel from drawing logic
    input      [3:0]  draw_g,    // Green channel from drawing logic
    input      [3:0]  draw_b,    // Blue channel from drawing logic
    output reg [10:0] curr_x,    // Current visible pixel X (0–1439)
    output reg [10:0] curr_y,    // Current visible pixel Y (0–899)
    output     [3:0]  pix_r,     // VGA red output
    output     [3:0]  pix_g,     // VGA green output
    output     [3:0]  pix_b,     // VGA blue output
    output            hsync,     // Horizontal sync pulse
    output            vsync      // Vertical sync pulse
);

    // ──────────────────────────────────────────────────────────
    // Timing parameters (localparams — immutable, synthesis-safe)
    // ──────────────────────────────────────────────────────────
    localparam H_TOTAL      = 11'd1904;   // Total horizontal clocks per line
    localparam H_SYNC_END   = 11'd151;    // hsync active: 0..151
    localparam H_BACK_END   = 11'd383;    // Back porch ends at 383
    localparam H_VIS_START  = 11'd384;    // First visible pixel
    localparam H_VIS_END    = 11'd1823;   // Last visible pixel
    localparam H_MAX        = 11'd1903;   // hcount wraps after this

    localparam V_TOTAL      = 10'd932;    // Total vertical lines per frame
    localparam V_SYNC_END   = 10'd2;      // vsync active: 0..2
    localparam V_BACK_END   = 10'd30;     // Back porch ends at 30
    localparam V_VIS_START  = 10'd31;     // First visible line
    localparam V_VIS_END    = 10'd930;    // Last visible line
    localparam V_MAX        = 10'd931;    // vcount wraps after this

    // ──────────────────────────────────────────────────────────
    // Internal counters
    // ──────────────────────────────────────────────────────────
    reg [10:0] hcount;  // 0..1903
    reg [9:0]  vcount;  // 0..931

    // ──────────────────────────────────────────────────────────
    // Horizontal and vertical counters
    // Single always block: vcount increments when hcount wraps
    // ──────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            hcount <= 11'd0;
            vcount <= 10'd0;
        end else begin
            if (hcount == H_MAX) begin
                hcount <= 11'd0;
                if (vcount == V_MAX)
                    vcount <= 10'd0;
                else
                    vcount <= vcount + 10'd1;
            end else begin
                hcount <= hcount + 11'd1;
            end
        end
    end

    // ──────────────────────────────────────────────────────────
    // Sync pulse generation (active high for Nexys 4DDR VGA DAC)
    // ──────────────────────────────────────────────────────────
    assign hsync = (hcount <= H_SYNC_END);
    assign vsync = (vcount <= V_SYNC_END);

    // ──────────────────────────────────────────────────────────
    // Visible region detection
    // ──────────────────────────────────────────────────────────
    wire h_visible = (hcount >= H_VIS_START) && (hcount <= H_VIS_END);
    wire v_visible = (vcount >= V_VIS_START) && (vcount <= V_VIS_END);
    wire visible   = h_visible && v_visible;

    // ──────────────────────────────────────────────────────────
    // Visible pixel coordinate outputs
    // Offset so that (curr_x=0, curr_y=0) corresponds to the
    // first visible pixel at (hcount=384, vcount=31)
    // ──────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            curr_x <= 11'd0;
            curr_y <= 11'd0;
        end else begin
            if (h_visible)
                curr_x <= hcount - H_VIS_START;
            else
                curr_x <= 11'd0;

            if (v_visible)
                curr_y <= vcount - V_VIS_START;
            else
                curr_y <= 11'd0;
        end
    end

    // ──────────────────────────────────────────────────────────
    // RGB output gating
    // Force outputs to zero during blanking to prevent colour
    // bleed into the sync/porch regions
    // ──────────────────────────────────────────────────────────
    assign pix_r = visible ? draw_r : 4'h0;
    assign pix_g = visible ? draw_g : 4'h0;
    assign pix_b = visible ? draw_b : 4'h0;

endmodule
