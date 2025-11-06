// instruction_memory.v
// Instruction BRAM (16KB = 4096 x 32-bit words)
// Dual-port: CPU reads, AXI writes

module instruction_memory (
    input  wire        clk,
    
    // CPU read port
    input  wire [11:0] cpu_addr,
    output wire [31:0] cpu_rdata,
    
    // AXI write port
    input  wire        axi_we,
    input  wire [11:0] axi_addr,
    input  wire [31:0] axi_wdata,
    output wire [31:0] axi_rdata
);

    parameter DEPTH = 4096;
    
    // Instruction memory storage
    reg [31:0] memory [0:DEPTH-1];
    
    // CPU read port (registered output)
    reg [31:0] cpu_rdata_reg;
    
    always @(posedge clk) begin
        cpu_rdata_reg <= memory[cpu_addr];
    end
    
    assign cpu_rdata = cpu_rdata_reg;
    
    // AXI port (read/write)
    reg [31:0] axi_rdata_reg;
    
    always @(posedge clk) begin
        if (axi_we) begin
            memory[axi_addr] <= axi_wdata;
        end
        axi_rdata_reg <= memory[axi_addr];
    end
    
    assign axi_rdata = axi_rdata_reg;

endmodule