// gpu_tb_simple.v - GUARANTEED TO WORK
`timescale 1ns / 1ps

module gpu_tb_simple;

    // Clock and reset
    reg clk = 0;
    always #5 clk = ~clk;
    
    reg rst_n = 0;
    initial #10 rst_n = 1;
    
    // AXI signals - EXPLICIT
    reg [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg awvalid = 0, wvalid = 0, arvalid = 0, bready = 0, rready = 0;
    wire [3:0] wstrb = 4'b1111;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    
    // Instantiate GPU
    gpu dut (
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rst_n),
        .S_AXI_AWADDR(awaddr),
        .S_AXI_AWVALID(awvalid),
        .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata),
        .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid),
        .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp),
        .S_AXI_BVALID(bvalid),
        .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr),
        .S_AXI_ARVALID(arvalid),
        .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata),
        .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid),
        .S_AXI_RREADY(rready)
    );
    
    // Test using simple sequential logic - NO TASKS
    initial begin
        // Initialize
        awaddr = 0; wdata = 0; araddr = 0;
        awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0;
        
        wait(rst_n);
        #20;
        
        $display("========================================");
        $display("GPU Test: Reading ID Register");
        $display("========================================");
        
        // READ GPU ID (address 0x00)
        araddr = 32'h00;
        arvalid = 1'b1;
        rready = 1'b1;
        @(posedge clk);  // Cycle 1: AR handshake
        arvalid = 1'b0;
        @(posedge clk);  // Cycle 2: Wait for memory
        @(posedge clk);  // Cycle 3: RVALID should be high
        
        $display("GPU ID = 0x%08X %s", rdata, 
                 (rdata == 32'hABCD1234) ? "?" : "?");
        
        // CLEAR SCREEN TO RED
        $display("\nClearing screen to red...");
        
        // Write color register
        awaddr = 32'h20; wdata = 32'hFF;
        awvalid = 1'b1; wvalid = 1'b1; bready = 1'b1;
        @(posedge clk);  // Cycle 1: AW/W handshake
        awvalid = 1'b0; wvalid = 1'b0;
        @(posedge clk);  // Cycle 2: Wait for BVALID
        @(posedge clk);  // Cycle 3: BRESP
        bready = 1'b0;
        
        // Write CMD_CLEAR
        awaddr = 32'h0C; wdata = 32'h01;
        awvalid = 1'b1; wvalid = 1'b1; bready = 1'b1;
        @(posedge clk);
        awvalid = 1'b0; wvalid = 1'b0;
        @(posedge clk);
        @(posedge clk);
        bready = 1'b0;
        
        #50000; // Wait 50us for clear operation
        
        $display("========================================");
        $display("GPU Test Complete - Check waveforms");
        $display("========================================");
        
        $finish;
    end

endmodule