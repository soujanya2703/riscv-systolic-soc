module mem #(
    parameter MEM_WORDS = 1024,          // 1024 words = 4KB
    parameter INIT_FILE = "firmware.hex"
)(
    input  wire        clk,
    input  wire         mem_valid,
    output reg          mem_ready,
    input  wire [31:0]  mem_addr,
    input  wire [31:0]  mem_wdata,
    input  wire [3:0]   mem_wstrb,
    output reg  [31:0]  mem_rdata
);

    reg [31:0] ram [0:MEM_WORDS-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, ram);
    end

    wire [31:0] word_addr = mem_addr[31:2]; // word-aligned index

    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_valid && !mem_ready) begin
            if (mem_wstrb[0]) ram[word_addr][7:0]   <= mem_wdata[7:0];
            if (mem_wstrb[1]) ram[word_addr][15:8]  <= mem_wdata[15:8];
            if (mem_wstrb[2]) ram[word_addr][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram[word_addr][31:24] <= mem_wdata[31:24];

            mem_rdata <= ram[word_addr];
            mem_ready <= 1'b1;
        end
    end

endmodule