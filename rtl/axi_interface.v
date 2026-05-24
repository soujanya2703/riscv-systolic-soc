module axi_interface #(
    parameter DATA_WIDTH = 8,
    parameter GRID_SIZE = 2
)(
    // Global Clock and Active-Low Reset
    input wire S_AXI_ACLK,
    input wire S_AXI_ARESETN,

    // AXI4-Lite Write Address Channel
    input wire [31:0] S_AXI_AWADDR,
    input wire S_AXI_AWVALID,
    output reg S_AXI_AWREADY,

    // AXI4-Lite Write Data Channel
    input wire [31:0] S_AXI_WDATA,
    input wire S_AXI_WVALID,
    output reg S_AXI_WREADY,

    // AXI4-Lite Write Response Channel
    output reg [1:0] S_AXI_BRESP,
    output reg S_AXI_BVALID,
    input wire S_AXI_BREADY,

    // Outward-facing Control signals wired directly to the Systolic Array
    output reg [(GRID_SIZE * DATA_WIDTH)-1:0] weight_data_out,
    output reg [(GRID_SIZE * DATA_WIDTH)-1:0] act_data_out,
    output reg load_weight_control
);

    // FSM State Encoding
    localparam IDLE  = 2'b00,
               WRITE = 2'b01,
               RESP  = 2'b10;

    reg [1:0] current_state;

    // Handshake Control State Machine
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            current_state       <= IDLE;
            S_AXI_AWREADY       <= 1'b0;
            S_AXI_WREADY        <= 1'b0;
            S_AXI_BVALID        <= 1'b0;
            S_AXI_BRESP         <= 2'b00;
            weight_data_out     <= 0;
            act_data_out        <= 0;
            load_weight_control <= 1'b0;
        end 
        else begin
            case (current_state)
                IDLE: begin
                    S_AXI_BVALID <= 1'b0;
                    // Wait for both Address and Data to be declared valid by the master CPU
                    if (S_AXI_AWVALID && S_AXI_WVALID) begin
                        S_AXI_AWREADY <= 1'b1; // Assert ready
                        S_AXI_WREADY  <= 1'b1; // Assert ready
                        current_state <= WRITE;
                    end
                end

                WRITE: begin
                    S_AXI_AWREADY <= 1'b0; // Clear handshake lines
                    S_AXI_WREADY  <= 1'b0;
                    
                    // Address Decoding Matrix
                    case (S_AXI_AWADDR)
                        32'h0000_0000: load_weight_control <= S_AXI_WDATA[0];   // Control Register (Bit 0 = Load signal)
                        32'h0000_0004: weight_data_out     <= S_AXI_WDATA[(GRID_SIZE*DATA_WIDTH)-1:0]; // Memory location for Weights
                        32'h0000_0008: act_data_out        <= S_AXI_WDATA[(GRID_SIZE*DATA_WIDTH)-1:0]; // Memory location for Activations
                    endcase
                    
                    S_AXI_BVALID <= 1'b1; // Assert that response status is ready
                    current_state <= RESP;
                end

                RESP: begin
                    if (S_AXI_BREADY) begin // Wait for master acknowledgment
                        S_AXI_BVALID  <= 1'b0;
                        current_state <= IDLE;
                    end
                end
                
                default: current_state <= IDLE;
            endcase
        end
    end
endmodule