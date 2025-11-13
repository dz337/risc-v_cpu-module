// gpu_tb.v - MAXIMALLY COMPATIBLE VERSION
`timescale 1ns / 1ps

module gpu_tb;

    // Clock and reset
    reg clk = 0;
    always #5 clk = ~clk;
    
    reg rst_n = 0;
    initial begin
        #10 rst_n = 1;
    end
    
    // AXI signals (explicitly declared)
    reg [31:0] awaddr;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wvalid;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready;
    reg [31:0] araddr;
    reg arvalid;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready;
    
    // Instantiate GPU - EXPLICIT PORTS
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
    
    // Test tasks - FULLY COMPATIBLE
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            awaddr = addr;
            wdata = data;
            wstrb = 4'b1111;
            awvalid = 1'b1;
            wvalid = 1'b1;
            bready = 1'b1;
            
            @(posedge clk);
            while (!awready || !wready) @(posedge clk);
            awvalid = 1'b0;
            wvalid = 1'b0;
            
            while (!bvalid) @(posedge clk);
            bready = 1'b0;
            @(posedge clk);
        end
    endtask
    
    task axi_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            araddr = addr;
            arvalid = 1'b1;
            rready = 1'b1;
            
            @(posedge clk);
            while (!arready) @(posedge clk);
            arvalid = 1'b0;
            
            @(posedge clk); // Wait one cycle for GPU combinational logic
            
            while (!rvalid) @(posedge clk);
            data = rdata;
            rready = 1'b0;
            @(posedge clk);
        end
    endtask
    
    // Test stimulus
    integer i;
    reg [31:0] read_val;
    
    initial begin
        // Initialize all signals
        awaddr = 32'b0; awvalid = 1'b0;
        wdata = 32'b0; wvalid = 1'b0; wstrb = 4'b1111;
        araddr = 32'b0; arvalid = 1'b0;
        bready = 1'b0; rready = 1'b0;
        
        wait(rst_n);
        #20;
        
        $display("========================================");
        $display("GPU Testbench - Compatibility Mode");
        $display("========================================");
        
        // Test GPU ID
        axi_read(32'h00, read_val);
        $display("GPU ID: 0x%08X %s", read_val, 
                 (read_val == 32'hABCD1234) ? "?" : "?");
        
        // Clear screen to red
        axi_write(32'h20, 32'hFF);  // Color
        axi_write(32'h0C, 32'h01);  // CMD_CLEAR
        
        #1000; // Wait for clear
        
        // Draw line
        axi_write(32'h10, 32'h0014000A);  // Start (10,20)
        axi_write(32'h14, 32'h003200C8);  // End (200,50)
        axi_write(32'h20, 32'h55);       // Color
        axi_write(32'h0C, 32'h03);       // CMD_DRAW_LINE
        
        #2000; // Wait for line
        
        // Read pixel
        axi_write(32'h40, 32'h14*320 + 32'h0A);
        axi_read(32'h44, read_val);
        $display("Pixel at (10,20): 0x%02X", read_val & 8'hFF);
        
        $display("========================================");
        $display("GPU Testbench Complete");
        $display("========================================");
        
        $finish;
    end

endmodule