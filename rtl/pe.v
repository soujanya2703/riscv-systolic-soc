module pe #(
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire rst,
    input wire load_weight,                       // 1 = Load/Freeze Weight, 0 = Compute
    input wire [DATA_WIDTH-1:0] weight_in,        // Weight data from left neighbor
    input wire [DATA_WIDTH-1:0] act_in,           // Activation data from top neighbor
    output reg [DATA_WIDTH-1:0] weight_out,       // Pass weight right
    output reg [DATA_WIDTH-1:0] act_out,          // Pass activation down
    output reg [(2*DATA_WIDTH)-1:0] accum         // 16-bit Accumulator to prevent overflow
);

    // Internal register to freeze the weight in place (Weight-Stationary)
    reg [DATA_WIDTH-1:0] stationary_weight;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            stationary_weight <= {DATA_WIDTH{1'b0}};
            weight_out        <= {DATA_WIDTH{1'b0}};
            act_out           <= {DATA_WIDTH{1'b0}};
            accum             <= {(2*DATA_WIDTH){1'b0}};
        end 
        else begin
            if (load_weight) begin
                stationary_weight <= weight_in;   // Phase 1: Lock the weight in memory
            end 
            else begin
                // Phase 2: Multiply incoming activation with stationary weight and accumulate
                accum <= accum + (act_in * stationary_weight);
            end
            
            // Pipelined data propagation: Pass inputs to neighbors on the next clock edge
            weight_out <= weight_in;
            act_out    <= act_in;
        end
    end
endmodule