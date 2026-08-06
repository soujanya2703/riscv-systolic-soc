module soc_top (
    input  wire       clk,
    input  wire       rst_n,
    output wire [7:0] led
);

    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire        mem_valid;
    wire        mem_ready;
    wire [31:0] mem_rdata;
    wire [3:0]  mem_wstrb;

    // ---- Address Map ----
    // 0x0000_0000 - 0x0000_0FFF : Program/Data RAM (4KB)
    // 0x8000_0000               : Accelerator control (bit0 = load_weight)
    // 0x8000_0004               : Accelerator weight register
    // 0x8000_0008               : Accelerator activation register
    // 0x8000_0010               : LED / GPIO output register
    // 0x8000_0020/24/28/2C      : Accelerator result readback (4 x 16b, one per PE)

    wire is_mem = (mem_addr[31] == 1'b0);
    wire is_axi = (mem_addr[31:8] == 24'h800000) &&
                  (mem_addr[7:0] == 8'h00 || mem_addr[7:0] == 8'h04 || mem_addr[7:0] == 8'h08);
    wire is_led = (mem_addr == 32'h8000_0010);
    wire is_res = (mem_addr[31:8] == 24'h800000) &&
                  (mem_addr[7:0] == 8'h20 || mem_addr[7:0] == 8'h24 ||
                   mem_addr[7:0] == 8'h28 || mem_addr[7:0] == 8'h2C);

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
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'b0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'b0), .eoi()
    );

    wire        mem_mod_ready;
    wire [31:0] mem_mod_rdata;

    mem #(.MEM_WORDS(1024), .INIT_FILE("firmware.hex")) program_mem (
        .clk       (clk),
        .mem_valid (mem_valid && is_mem),
        .mem_ready (mem_mod_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_mod_rdata)
    );

    wire [15:0] weight_stream;
    wire [15:0] act_stream;
    wire        ctrl_load;
    wire        S_AXI_BVALID_w;

    reg axi_busy;
    wire axi_start = mem_valid && is_axi && (|mem_wstrb) && !axi_busy;

    always @(posedge clk) begin
        if (!rst_n)
            axi_busy <= 1'b0;
        else if (axi_start)
            axi_busy <= 1'b1;
        else if (S_AXI_BVALID_w)
            axi_busy <= 1'b0;
    end

    // axi_interface's internal case-statement decodes raw offsets 0x0/0x4/0x8,
    // so translate our peripheral-space address (0x8000_0000 base) down to that
    // local offset before handing it to the (unmodified, already-verified) core.
    wire [31:0] axi_awaddr_local = {24'b0, mem_addr[7:0]};

    axi_interface #(.GRID_SIZE(2)) systolic_peripheral (
        .S_AXI_ACLK    (clk),
        .S_AXI_ARESETN (rst_n),
        .S_AXI_AWADDR  (axi_awaddr_local),
        .S_AXI_AWVALID (axi_start),
        .S_AXI_AWREADY (),
        .S_AXI_WDATA   (mem_wdata),
        .S_AXI_WVALID  (axi_start),
        .S_AXI_WREADY  (),
        .S_AXI_BVALID  (S_AXI_BVALID_w),
        .S_AXI_BREADY  (1'b1),
        .S_AXI_BRESP   (),
        .weight_data_out     (weight_stream),
        .act_data_out        (act_stream),
        .load_weight_control (ctrl_load)
    );

    wire [63:0] array_results;

    systolic_array #(.GRID_SIZE(2)) core_array (
        .clk               (clk),
        .rst               (!rst_n),
        .load_weight       (ctrl_load),
        .weight_inputs     (weight_stream),
        .act_inputs        (act_stream),
        .flattened_outputs (array_results)
    );

    reg [7:0] led_reg;
    reg       led_ready;
    always @(posedge clk) begin
        led_ready <= 1'b0;
        if (mem_valid && is_led && (|mem_wstrb) && !led_ready) begin
            led_reg   <= mem_wdata[7:0];
            led_ready <= 1'b1;
        end
    end
    assign led = led_reg;

    reg [31:0] res_rdata;
    reg        res_ready;
    always @(*) begin
        case (mem_addr[7:0])
            8'h20:   res_rdata = {16'b0, array_results[15:0]};
            8'h24:   res_rdata = {16'b0, array_results[31:16]};
            8'h28:   res_rdata = {16'b0, array_results[47:32]};
            8'h2C:   res_rdata = {16'b0, array_results[63:48]};
            default: res_rdata = 32'b0;
        endcase
    end
    always @(posedge clk)
        res_ready <= mem_valid && is_res;

    assign mem_ready = is_mem ? mem_mod_ready :
                        is_axi ? S_AXI_BVALID_w :
                        is_led ? led_ready :
                        is_res ? res_ready :
                        1'b0;

    assign mem_rdata = is_mem ? mem_mod_rdata :
                        is_res ? res_rdata :
                        32'b0;

endmodule