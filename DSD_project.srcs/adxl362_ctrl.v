`timescale 1ns / 1ps
// Module: adxl362_ctrl.v
// Purpose: SPI master for the ADXL362 3-axis accelerometer on the Nexys 4DDR.
//          Initialises the device into measurement mode, then samples X/Y/Z
//          acceleration at ~50 Hz. A flick gesture is detected by computing
//          the L1-norm (sum of absolute differences) between consecutive samples
//          and comparing it to a threshold. A 2-second debounce prevents
//          repeated triggers from a single wrist motion.
//
// SPI: mode 0 (CPOL=0, CPHA=0), MSB first, ~1 MHz bit clock.
//   CS is de-asserted (high) between transactions.
//   shift_tx holds the outgoing frame; shift_rx captures incoming miso bits.
//
// State machine:
//   S_BOOT     — 10 ms power-on delay before the first SPI transaction
//   S_INIT_CMD — writes register 0x2D = 0x02 (POWER_CTL: measurement mode ON)
//   S_WAIT     — 20 ms inter-sample delay; latches previous acceleration values
//   S_READ_CMD — reads 6 bytes starting at register 0x0E (XDATA_L)
//   S_CALC     — computes L1-norm of frame-to-frame delta; fires flick_detected

module adxl362_ctrl (
    input        clk,
    input        rst,
    output reg   cs,
    output reg   mosi,
    output       sclk,
    input        miso,
    output reg   flick_detected
);

    localparam FLICK_THRESHOLD = 16'd800; // L1-norm threshold, tuned for wrist flick

    // SPI clock: divide 100 MHz by 100 → ~1 MHz tick
    reg [5:0] clk_div;
    wire spi_tick = (clk_div == 6'd49);

    always @(posedge clk or negedge rst) begin
        if (!rst) clk_div <= 0;
        else if (spi_tick) clk_div <= 0;
        else clk_div <= clk_div + 1;
    end

    reg  sclk_reg;
    assign sclk = sclk_reg;

    localparam S_BOOT     = 3'd0;
    localparam S_INIT_CMD = 3'd1;
    localparam S_WAIT     = 3'd2;
    localparam S_READ_CMD = 3'd3;
    localparam S_CALC     = 3'd4;

    reg [2:0]  state;
    reg [6:0]  bit_count;
    reg [63:0] shift_tx;
    reg [63:0] shift_rx;
    reg [23:0] delay_cnt;    // General countdown (max ~167 ms at 100 MHz)
    reg [27:0] debounce_cnt; // Post-detection lockout (max ~2.68 s at 100 MHz)
    reg        phase;        // SPI half-cycle: 0 = drive MOSI, 1 = toggle SCLK

    reg signed [15:0] acc_x, acc_y, acc_z;
    reg signed [15:0] prev_acc_x, prev_acc_y, prev_acc_z;

    reg [15:0] diff_x, diff_y, diff_z;
    reg [15:0] magnitude; // L1-norm = |Δx| + |Δy| + |Δz|

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            state <= S_BOOT;
            cs <= 1; mosi <= 0; sclk_reg <= 0;
            flick_detected <= 0; bit_count <= 0;
            delay_cnt <= 0; debounce_cnt <= 0; phase <= 0;
            acc_x <= 0; acc_y <= 0; acc_z <= 0;
            prev_acc_x <= 0; prev_acc_y <= 0; prev_acc_z <= 0;
        end else begin
            flick_detected <= 0;

            if (debounce_cnt > 0) debounce_cnt <= debounce_cnt - 1;

            case (state)

                // Wait 10 ms for ADXL362 power rail to stabilise
                S_BOOT: begin
                    if (delay_cnt == 24'd1000000) begin
                        state    <= S_INIT_CMD; delay_cnt <= 0;
                        // Write command: 0x0A (write) | 0x2D (POWER_CTL) | 0x02 (measure)
                        shift_tx <= {8'h0A, 8'h2D, 8'h02, 40'h0};
                    end else delay_cnt <= delay_cnt + 1;
                end

                // Transmit 24-bit write frame.
                // phase 0: assert CS and drive MSB onto MOSI.
                // phase 1: raise SCLK (slave latches on rising edge).
                // phase 0 (next): lower SCLK, shift next bit or deassert CS.
                S_INIT_CMD: begin
                    if (spi_tick) begin
                        if (bit_count == 0 && phase == 0) begin
                            cs <= 0; mosi <= shift_tx[63]; phase <= 1;
                        end else if (phase == 1) begin
                            sclk_reg <= 1; phase <= 0; bit_count <= bit_count + 1;
                        end else begin
                            sclk_reg <= 0;
                            if (bit_count < 24) begin
                                shift_tx <= {shift_tx[62:0], 1'b0};
                                mosi <= shift_tx[62]; phase <= 1;
                            end else begin
                                cs <= 1; state <= S_WAIT; bit_count <= 0;
                            end
                        end
                    end
                end

                // 20 ms inter-sample delay (50 Hz sample rate).
                // Previous values latched here so S_CALC computes consecutive delta.
                S_WAIT: begin
                    if (delay_cnt == 24'd2000000) begin
                        state <= S_READ_CMD; delay_cnt <= 0;
                        prev_acc_x <= acc_x; prev_acc_y <= acc_y; prev_acc_z <= acc_z;
                        // Burst-read: 0x0B (read) | 0x0E (XDATA_L) | 6 dummy bytes
                        shift_tx <= {8'h0B, 8'h0E, 48'h0};
                    end else delay_cnt <= delay_cnt + 1;
                end

                // 64-bit SPI read (16-bit command + 48-bit = 6 data bytes).
                // miso bits shift into shift_rx MSB-first.
                // Byte-swap on completion reconstructs little-endian 16-bit values:
                //   acc_x = {XDATA_H, XDATA_L} = {shift_rx[39:32], shift_rx[47:40]}
                S_READ_CMD: begin
                    if (spi_tick) begin
                        if (bit_count == 0 && phase == 0) begin
                            cs <= 0; mosi <= shift_tx[63]; phase <= 1;
                        end else if (phase == 1) begin
                            sclk_reg <= 1;
                            shift_rx <= {shift_rx[62:0], miso};
                            phase <= 0; bit_count <= bit_count + 1;
                        end else begin
                            sclk_reg <= 0;
                            if (bit_count < 64) begin
                                shift_tx <= {shift_tx[62:0], 1'b0};
                                mosi <= shift_tx[62]; phase <= 1;
                            end else begin
                                cs <= 1; state <= S_CALC; bit_count <= 0;
                                acc_x <= {shift_rx[39:32], shift_rx[47:40]};
                                acc_y <= {shift_rx[23:16], shift_rx[31:24]};
                                acc_z <= {shift_rx[7:0],   shift_rx[15:8]};
                            end
                        end
                    end
                end

                // L1-norm gesture detection.
                // L1 = |Δx| + |Δy| + |Δz| is cheaper than Euclidean (no sqrt) and
                // sufficient to distinguish a sharp wrist flick from ambient vibration.
                S_CALC: begin
                    diff_x    = (acc_x > prev_acc_x) ? (acc_x - prev_acc_x) : (prev_acc_x - acc_x);
                    diff_y    = (acc_y > prev_acc_y) ? (acc_y - prev_acc_y) : (prev_acc_y - acc_y);
                    diff_z    = (acc_z > prev_acc_z) ? (acc_z - prev_acc_z) : (prev_acc_z - acc_z);
                    magnitude = diff_x + diff_y + diff_z;

                    if (magnitude > FLICK_THRESHOLD && debounce_cnt == 0) begin
                        flick_detected <= 1;
                        debounce_cnt   <= 28'd200000000; // 2 s lockout at 100 MHz
                    end

                    delay_cnt <= 0;
                    state     <= S_WAIT;
                end

            endcase
        end
    end

endmodule
