`timescale 1ns / 1ps

module tb_soc();
    reg clk;
    reg rst_n;
    wire [7:0] led;

    soc_top DUT (
        .clk   (clk),
        .rst_n (rst_n),
        .led   (led)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    initial begin
        $dumpfile("dump_soc.vcd");
        $dumpvars(0, tb_soc);
    end

    initial begin
        clk = 0; rst_n = 0;
        #50 rst_n = 1;

        $monitor("t=%0t addr=%h valid=%b ready=%b wstrb=%b wdata=%h | axi_start=%b busy=%b bvalid=%b ctrl_load=%b weight=%h act=%h",
                  $time, DUT.mem_addr, DUT.mem_valid, DUT.mem_ready, DUT.mem_wstrb, DUT.mem_wdata,
                  DUT.axi_start, DUT.axi_busy, DUT.S_AXI_BVALID_w, DUT.ctrl_load,
                  DUT.weight_stream, DUT.act_stream);

        // Give the CPU enough cycles to run the 15-instruction firmware
        // (fetch+execute over multiple cycles each on picorv32, plus
        // AXI write handshakes of a few cycles each)
        #6000;
        $display("DEBUG mem_addr=%h mem_valid=%b mem_ready=%b mem_wstrb=%b mem_wdata=%h mem_rdata=%h",
                  DUT.mem_addr, DUT.mem_valid, DUT.mem_ready, DUT.mem_wstrb, DUT.mem_wdata, DUT.mem_rdata);
        $display("DEBUG led_reg=%h led_ready=%b array_results=%h ctrl_load=%b",
                  DUT.led_reg, DUT.led_ready, DUT.array_results, DUT.ctrl_load);

        $display("--- FULL SoC SIMULATION RESULT ---");
        $display("LED register value : %d (0x%0h)", led, led);
        $display("-----------------------------------");
        $finish;
    end
endmodule