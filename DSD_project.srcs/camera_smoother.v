module camera_smoother (
    input clk,
    input rst,
    input [10:0] logical_y,
    output reg [10:0] render_y
);

    localparam PAN_SPEED = 11'd8; 

    // Notice: 'negedge rst' is REMOVED from the sensitivity list.
    // This makes the reset synchronous, which allows us to load a dynamic variable!
    always @(posedge clk) begin
        if (!rst) begin
            render_y <= logical_y; // Now it will snap instantly on reset!
        end else begin
            if (render_y < logical_y) begin
                if ((logical_y - render_y) < PAN_SPEED)
                    render_y <= logical_y;
                else
                    render_y <= render_y + PAN_SPEED;
            end 
            else if (render_y > logical_y) begin
                if ((render_y - logical_y) < PAN_SPEED)
                    render_y <= logical_y;
                else
                    render_y <= render_y - PAN_SPEED;
            end
        end
    end
endmodule
