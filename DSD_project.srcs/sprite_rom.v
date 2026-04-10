`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      sprite_rom.v
// Description:
//   Parameterised synchronous ROM for sprite data. Vivado infers
//   Block RAM automatically from this pattern (reg array + $readmemh
//   + synchronous read).
//
//   Each pixel is 12-bit RGB. Transparency key: 12'h000.
//
//   Usage: instantiate with appropriate WIDTH, HEIGHT, and MEM_FILE.
//   The address is computed externally as:
//     addr = (curr_y - sprite_y) * WIDTH + (curr_x - sprite_x)
//
// Parameters:
//   WIDTH    : Sprite width in pixels
//   HEIGHT   : Sprite height in pixels
//   MEM_FILE : Path to .mem file (hex, one 12-bit value per line)
//////////////////////////////////////////////////////////////////////////////////

module sprite_rom #(
    parameter WIDTH    = 32,
    parameter HEIGHT   = 32,
    parameter MEM_FILE = "chicken_up.mem"
)(
    input                          clk,     // Pixel clock for synchronous read
    input  [$clog2(WIDTH*HEIGHT)-1:0] addr, // Pixel address (row-major)
    output reg [11:0]              data     // 12-bit RGB pixel data
);

    // Storage: inferred as BRAM by Vivado
    reg [11:0] rom [0:WIDTH*HEIGHT-1];

    // Load sprite data from .mem file at elaboration time
    initial begin
        $readmemh(MEM_FILE, rom);
    end

    // Synchronous read (1-cycle latency — required for BRAM inference)
    always @(posedge clk) begin
        data <= rom[addr];
    end

endmodule
