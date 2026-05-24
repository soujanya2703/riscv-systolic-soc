module systolic_array #(
    parameter DATA_WIDTH = 8,
    parameter GRID_SIZE = 2 // Change to 4 for a 4x4 array
)(
    input wire clk,
    input wire rst,
    input wire load_weight,
    
    // Flat 1D arrays to interface with external pins/buses
    input wire [(GRID_SIZE * DATA_WIDTH)-1:0] weight_inputs, // Inputs to the left column
    input wire [(GRID_SIZE * DATA_WIDTH)-1:0] act_inputs,    // Inputs to the top row
    output wire [((GRID_SIZE * GRID_SIZE) * (2*DATA_WIDTH))-1:0] flattened_outputs
);

    // Create 2D wire matrices to interconnect internal PEs horizontally and vertically
    wire [DATA_WIDTH-1:0] horiz_wires [0:GRID_SIZE][0:GRID_SIZE];
    wire [DATA_WIDTH-1:0] vert_wires  [0:GRID_SIZE][0:GRID_SIZE];
    wire [(2*DATA_WIDTH)-1:0] pe_accum [0:GRID_SIZE-1][0:GRID_SIZE-1];

    // Unpack flat 1D inputs into the 2D wire network boundaries
    genvar b;
    generate
        for (b = 0; b < GRID_SIZE; b = b + 1) begin: input_bind
            assign horiz_wires[b][0] = weight_inputs[(b+1)*DATA_WIDTH-1 : b*DATA_WIDTH];
            assign vert_wires[0][b]  = act_inputs[(b+1)*DATA_WIDTH-1 : b*DATA_WIDTH];
        end
    endgenerate

    // Generate Loop Matrix to construct and wire the grid
    genvar i, j;
    generate
        for (i = 0; i < GRID_SIZE; i = i + 1) begin: row
            for (j = 0; j < GRID_SIZE; j = j + 1) begin: col
                pe #(.DATA_WIDTH(DATA_WIDTH)) PE_inst (
                    .clk(clk),
                    .rst(rst),
                    .load_weight(load_weight),
                    .weight_in(horiz_wires[i][j]),
                    .act_in(vert_wires[i][j]),
                    .weight_out(horiz_wires[i][j+1]),
                    .act_out(vert_wires[i+1][j]),
                    .accum(pe_accum[i][j])
                );
                
                // Pack 2D accumulation matrix back into a single flat output channel
                assign flattened_outputs[((i*GRID_SIZE+j)+1)*(2*DATA_WIDTH)-1 : (i*GRID_SIZE+j)*(2*DATA_WIDTH)] = pe_accum[i][j];
            end
        end
    endgenerate

endmodule