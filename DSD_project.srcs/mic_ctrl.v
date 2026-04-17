`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      mic_ctrl.v
// Description: Reads the ADMP421 PDM microphone on the Nexys A7.
//              Generates a 2MHz clock for the mic, counts the density of '1's 
//              over a small window, and fires a pulse if the volume spikes.
//////////////////////////////////////////////////////////////////////////////////

module mic_ctrl (
    input        clk,            // 100MHz system clock
    input        rst,
    
    // Physical Mic Pins
    output reg   m_clk,          // 2MHz clock driven to the mic
    input        m_data,         // PDM data coming from the mic
    output       m_lrsel,        // Left/Right channel select (tied to GND)
    
    // Game Engine Output
    output reg   shout_detected  // Pulses HIGH when a loud noise is detected
);

    // The ADMP421 requires m_lrsel to be grounded to output data on the falling edge
    assign m_lrsel = 1'b0; 

    // Generate the 2MHz Microphone Clock
    // 100MHz / 50 = 2MHz (Toggle every 25 cycles)
    reg [5:0] clk_div;
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            clk_div <= 0;
            m_clk <= 0;
        end else begin
            if (clk_div == 6'd24) begin
                m_clk <= ~m_clk;
                clk_div <= 0;
            end else begin
                clk_div <= clk_div + 1;
            end
        end
    end

    // Sample Data on Falling Edge of m_clk
    // We need to sample the m_data exactly when m_clk goes from 1 to 0
    reg m_clk_prev;
    wire sample_tick = (m_clk_prev == 1'b1 && m_clk == 1'b0);
    
    always @(posedge clk) begin
        m_clk_prev <= m_clk;
    end

    //PDM Density Counter
    // We will collect 65,536 samples. 
    // If silent, we should see ~32,768 ones. 
    // If loud, the ones count will swing wildly up or down.
    
    reg [15:0] sample_count;     // Counts from 0 to 65,535
    reg [15:0] ones_count;       // Counts how many '1's arrived in that window
    
    // Tuning Parameters
    localparam BASELINE = 16'd32768;
    localparam THRESHOLD = 16'd4000; // How far from baseline is considered a "shout"?
    
    reg [23:0] debounce_timer;   // Prevent machine-gun shouting

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            sample_count <= 0;
            ones_count <= 0;
            shout_detected <= 0;
            debounce_timer <= 0;
        end else begin
            shout_detected <= 0; // Default low
            
            if (debounce_timer > 0) begin
                debounce_timer <= debounce_timer - 1;
            end

            if (sample_tick) begin
                sample_count <= sample_count + 1;
                
                if (m_data) begin
                    ones_count <= ones_count + 1;
                end
                
                // End of the sample window
                if (sample_count == 16'hFFFF) begin
                    // Calculate absolute difference from the 50% baseline
                    if ((ones_count > BASELINE + THRESHOLD) || (ones_count < BASELINE - THRESHOLD)) begin
                        if (debounce_timer == 0) begin
                            shout_detected <= 1'b1;
                            debounce_timer <= 24'd50000000; // 0.5 second cooldown
                        end
                    end
                    
                    // Reset for the next window
                    ones_count <= 0;
                end
            end
        end
    end

endmodule
