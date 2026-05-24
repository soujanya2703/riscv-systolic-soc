`timescale 1ns / 1ps

module tb_systolic();
    reg clk;
    reg rst_n;
    
    // AXI Bus Simulation Signals
    reg [31:0] awaddr;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg wvalid;
    wire wready;
    wire bvalid;
    reg bready;

    wire [15:0] weight_stream;
    wire [15:0] act_stream;
    wire ctrl_load;
    wire [63:0] results; // Holds four 16-bit outputs from the 2x2 grid

    // Instantiate AXI Interface Wrapper
    axi_interface #(.GRID_SIZE(2)) DUT_AXI (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready), .S_AXI_BRESP(),
        .weight_data_out(weight_stream), .act_data_out(act_stream), .load_weight_control(ctrl_load)
    );

    // Instantiate Compute Core
    systolic_array #(.GRID_SIZE(2)) DUT_ARRAY (
        .clk(clk), .rst(!rst_n), .load_weight(ctrl_load),
        .weight_inputs(weight_stream), .act_inputs(act_stream),
        .flattened_outputs(results)
    );

    // Generate 100MHz clock signal
    always #5 clk = ~clk;

    // Automated Icarus Verilog waveform logging block
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_systolic);
    end

    initial begin
        // Initialize lines
        clk = 0; rst_n = 0; awaddr = 0; awvalid = 0; wdata = 0; wvalid = 0; bready = 1;
        #20 rst_n = 1; // Release reset
        #10;

        // Transaction 1: Turn ON load_weight control bit
        awaddr = 32'h0000_0000; wdata = 32'h0000_0001; awvalid = 1; wvalid = 1;
        @(posedge clk); while(!awready) @(posedge clk);
        #5 awvalid = 0; wvalid = 0; #20;

        // Transaction 2: Stream weights into memory space (Load weight vector Hex 04 and 02)
        awaddr = 32'h0000_0004; wdata = 32'h0000_0402; awvalid = 1; wvalid = 1;
        @(posedge clk); while(!awready) @(posedge clk);
        #5 awvalid = 0; wvalid = 0; #20;

        // Transaction 3: Turn OFF load_weight to lock them in place
        awaddr = 32'h0000_0000; wdata = 32'h0000_0000; awvalid = 1; wvalid = 1;
        @(posedge clk); while(!awready) @(posedge clk);
        #5 awvalid = 0; wvalid = 0; #20;

        // Transaction 4: Stream activations into computing channels (Inputs Hex 03 and 06)
        awaddr = 32'h0000_0008; wdata = 32'h0000_0306; awvalid = 1; wvalid = 1;
        @(posedge clk); while(!awready) @(posedge clk);
        #5 awvalid = 0; wvalid = 0; 
        
        // Wait 4 clock cycles for processing array pipeline calculation latency
        repeat(4) @(posedge clk);

        // Print final computations out directly to simulation terminal console
        $display("--- SIMULATION VERIFICATION OUTPUTS ---");
        $display("PE[0][0] Accumulation Result: %d", results[15:0]);
        $display("PE[0][1] Accumulation Result: %d", results[31:16]);
        $display("PE[1][0] Accumulation Result: %d", results[47:32]);
        $display("PE[1][1] Accumulation Result: %d", results[63:48]);
        $display("---------------------------------------");
        $finish;
    end
endmodule