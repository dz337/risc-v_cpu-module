// data_memory.v
// Data BRAM (16KB = 4096 x 32-bit words)
// Byte-addressable with write strobes

module data_memory (
    input  wire        clk,
    
    // CPU port
    input  wire        we,
    input  wire [11:0] addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output wire [31:0] rdata
);

    parameter DEPTH = 4096;
    
    // Data memory storage
    reg [31:0] memory [0:DEPTH-1];
    
    // Read port (registered output)
    reg [31:0] rdata_reg;
    
    always @(posedge clk) begin
        if (we) begin
            // Byte-addressable write with strobe
            if (wstrb[0]) memory[addr][7:0]   <= wdata[7:0];
            if (wstrb[1]) memory[addr][15:8]  <= wdata[15:8];
            if (wstrb[2]) memory[addr][23:16] <= wdata[23:16];
            if (wstrb[3]) memory[addr][31:24] <= wdata[31:24];
        end
        rdata_reg <= memory[addr];
    end
    
    assign rdata = rdata_reg;

endmodule