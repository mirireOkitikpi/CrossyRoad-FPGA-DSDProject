`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      debounce.v
// Description:
//   Debounces a raw asynchronous button input using a two-stage
//   synchroniser (to prevent metastability) followed by a saturating
//   counter that requires the input to be stable for 2^COUNTER_WIDTH
//   clock cycles (~10 ms at 100 MHz with COUNTER_WIDTH=20).
//
//   The output btn_out transitions only after the input has been
//   stable for the full counter period, filtering mechanical bounce.
//
// Parameters:
//   COUNTER_WIDTH : Number of counter bits. The debounce period is
//                   2^COUNTER_WIDTH / f_clk seconds.
//                   Default 20 → 2^20 / 100e6 ≈ 10.5 ms
//////////////////////////////////////////////////////////////////////////////////

module debounce #(
    parameter COUNTER_WIDTH = 20
)(
    input  clk,      // System clock (100 MHz)
    input  rst,      // Active-low reset
    input  btn_in,   // Raw button input (asynchronous)
    output btn_out   // Debounced, synchronised output
);

    // ──────────────────────────────────────────────────────────
    // Two-flip-flop synchroniser
    // Prevents metastability from the async button input crossing
    // into the clk domain (standard CDC technique)
    // ──────────────────────────────────────────────────────────
    reg btn_sync_0, btn_sync_1;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            btn_sync_0 <= 1'b0;
            btn_sync_1 <= 1'b0;
        end else begin
            btn_sync_0 <= btn_in;
            btn_sync_1 <= btn_sync_0;
        end
    end

    // ──────────────────────────────────────────────────────────
    // Saturating counter
    // Counts up while the synchronised input differs from the
    // stable output. When the counter saturates, the output
    // transitions. Any change resets the counter.
    // ──────────────────────────────────────────────────────────
    reg [COUNTER_WIDTH-1:0] counter;
    reg btn_stable;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            counter    <= {COUNTER_WIDTH{1'b0}};
            btn_stable <= 1'b0;
        end else begin
            if (btn_sync_1 != btn_stable) begin
                // Input differs from stable state — count up
                if (counter == {COUNTER_WIDTH{1'b1}}) begin
                    // Counter saturated: accept the new value
                    btn_stable <= btn_sync_1;
                    counter    <= {COUNTER_WIDTH{1'b0}};
                end else begin
                    counter <= counter + 1'b1;
                end
            end else begin
                // Input matches stable state — reset counter
                counter <= {COUNTER_WIDTH{1'b0}};
            end
        end
    end

    assign btn_out = btn_stable;

endmodule
