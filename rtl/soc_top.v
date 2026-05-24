module soc_top (
    input wire clk,
    input wire rst_n
);

    // Internal System Bus Wires linking CPU to our Accelerator Interface
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire mem_valid;
    wire mem_ready;
    wire [31:0] mem_rdata;
    wire [3:0]  mem_wstrb;

    // 1. Instantiate the RISC-V CPU Core (The Master)
    picorv32 #(
        .ENABLE_MUL(1),
        .ENABLE_DIV(0)
    ) cpu_core (
        .clk       (clk),
        .resetn    (rst_n),
        .mem_valid (mem_valid),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        // Unused CPU signals tied to zero
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'b0), .eoi()
    );

    // 2. Instantiate Your Custom AXI Interface + Systolic Array (The Slave)
    wire [15:0] weight_stream;
    wire [15:0] act_stream;
    wire ctrl_load;
    wire [63:0] array_results;

    axi_interface #(.GRID_SIZE(2)) systolic_peripheral (
        .S_AXI_ACLK    (clk),
        .S_AXI_ARESETN (rst_n),
        // Hook up directly to the CPU memory bus!
        .S_AXI_AWADDR  (mem_addr),
        .S_AXI_AWVALID (mem_valid && (|mem_wstrb)), // CPU wants to write
        .S_AXI_AWREADY (mem_ready),
        .S_AXI_WDATA   (mem_wdata),
        .S_AXI_WVALID  (mem_valid && (|mem_wstrb)),
        .S_AXI_WREADY  (),
        .S_AXI_BVALID  (),
        .S_AXI_BREADY  (1'b1),
        .S_AXI_BRESP   (),
        // Internal connections to the computing core
        .weight_data_out     (weight_stream),
        .act_data_out        (act_stream),
        .load_weight_control (ctrl_load)
    );

    // 3. Instantiate the Compute Core
    systolic_array #(.GRID_SIZE(2)) core_array (
        .clk               (clk),
        .rst               (!rst_n),
        .load_weight       (ctrl_load),
        .weight_inputs     (weight_stream),
        .act_inputs        (act_stream),
        .flattened_outputs (array_results)
    );

endmodule