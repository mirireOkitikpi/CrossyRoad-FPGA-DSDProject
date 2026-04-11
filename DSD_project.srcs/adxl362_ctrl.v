`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module:      adxl362_ctrl.v
// Description: SPI Master for the ADXL362. Features a true 2-second debounce
//              timer that operates independently of the 20ms sample clock.
//////////////////////////////////////////////////////////////////////////////////

module adxl362_ctrl (
    input        clk,            
    input        rst,
    output reg   cs,             
    output reg   mosi,           
    output       sclk,           
    input        miso,           
    output reg   flick_detected  
);

    localparam FLICK_THRESHOLD = 16'd800; 

    reg [5:0] clk_div;
    wire spi_tick = (clk_div == 6'd49);

    always @(posedge clk or negedge rst) begin
        if (!rst) clk_div <= 0;
        else if (spi_tick) clk_div <= 0;
        else clk_div <= clk_div + 1;
    end

    reg sclk_reg;
    assign sclk = sclk_reg;

    localparam S_BOOT       = 3'd0;
    localparam S_INIT_CMD   = 3'd1;
    localparam S_WAIT       = 3'd2;
    localparam S_READ_CMD   = 3'd3;
    localparam S_CALC       = 3'd4;

    reg [2:0]  state;
    reg [6:0]  bit_count; 
    
    reg [63:0] shift_tx; 
    reg [63:0] shift_rx; 
    
    reg [23:0] delay_cnt;     // Max ~16 million (plenty for 2 million)
    reg [27:0] debounce_cnt;  // Max ~268 million (needed for 200 million)
    reg phase;

    reg signed [15:0] acc_x, acc_y, acc_z;
    reg signed [15:0] prev_acc_x, prev_acc_y, prev_acc_z;
    
    reg [15:0] diff_x, diff_y, diff_z;
    reg [15:0] magnitude;
    
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
            
            if (debounce_cnt > 0) 
                debounce_cnt <= debounce_cnt - 1;
            
            case (state)
                S_BOOT: begin
                    if (delay_cnt == 24'd1000000) begin
                        state <= S_INIT_CMD; delay_cnt <= 0;
                        shift_tx <= {8'h0A, 8'h2D, 8'h02, 40'h0}; 
                    end else delay_cnt <= delay_cnt + 1;
                end

                S_INIT_CMD: begin
                    if (spi_tick) begin
                        if (bit_count == 0 && phase == 0) begin
                            cs <= 0; mosi <= shift_tx[63]; 
                            phase <= 1;
                        end else if (phase == 1) begin
                            sclk_reg <= 1; 
                            phase <= 0; bit_count <= bit_count + 1;
                        end else begin
                            sclk_reg <= 0; 
                            if (bit_count < 24) begin
                                shift_tx <= {shift_tx[62:0], 1'b0};
                                mosi <= shift_tx[62];
                                phase <= 1;
                            end else begin
                                cs <= 1; state <= S_WAIT; bit_count <= 0;
                            end
                        end
                    end
                end

                S_WAIT: begin
                    // 20ms Sample Rate
                    if (delay_cnt == 24'd2000000) begin
                        state <= S_READ_CMD; delay_cnt <= 0;
                        
                        prev_acc_x <= acc_x;
                        prev_acc_y <= acc_y;
                        prev_acc_z <= acc_z;
                        
                        shift_tx <= {8'h0B, 8'h0E, 48'h0}; 
                    end else delay_cnt <= delay_cnt + 1;
                end

                S_READ_CMD: begin
                    if (spi_tick) begin
                        if (bit_count == 0 && phase == 0) begin
                            cs <= 0; mosi <= shift_tx[63]; 
                            phase <= 1;
                        end else if (phase == 1) begin
                            sclk_reg <= 1; 
                            shift_rx <= {shift_rx[62:0], miso};
                            phase <= 0; bit_count <= bit_count + 1;
                        end else begin
                            sclk_reg <= 0; 
                            if (bit_count < 64) begin
                                shift_tx <= {shift_tx[62:0], 1'b0};
                                mosi <= shift_tx[62];
                                phase <= 1;
                            end else begin
                                cs <= 1; state <= S_CALC; bit_count <= 0;
                                
                                acc_x <= {shift_rx[39:32], shift_rx[47:40]};
                                acc_y <= {shift_rx[23:16], shift_rx[31:24]};
                                acc_z <= {shift_rx[7:0],   shift_rx[15:8]};
                            end
                        end
                    end
                end

                S_CALC: begin
                    diff_x = (acc_x > prev_acc_x) ? (acc_x - prev_acc_x) : (prev_acc_x - acc_x);
                    diff_y = (acc_y > prev_acc_y) ? (acc_y - prev_acc_y) : (prev_acc_y - acc_y);
                    diff_z = (acc_z > prev_acc_z) ? (acc_z - prev_acc_z) : (prev_acc_z - acc_z);
                    
                    magnitude = diff_x + diff_y + diff_z;
                    
                    if (magnitude > FLICK_THRESHOLD && debounce_cnt == 0) begin
                        flick_detected <= 1;
                        debounce_cnt <= 28'd200000000; // Lock out jumps for 2 seconds
                    end
                    
                    delay_cnt <= 0; 
                    state <= S_WAIT;
                end
            endcase
        end
    end
endmodule
