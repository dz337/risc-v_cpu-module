// instruction_memory.v
// Instruction BRAM (16KB = 4096 x 32-bit words)
// Dual-port: CPU reads, AXI writes
module instruction_memory (
    input  wire        clk,
    
    // CPU read port
    input  wire [11:0] cpu_addr,
    output wire [31:0] cpu_rdata,
    
    // AXI write port (word-indexed)
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
    assign cpu_rdata = cpu_rdata_reg;
    
    // Latched AXI address and AXI readback register
    reg [11:0] axi_addr_reg;
    reg [31:0] axi_rdata_reg;
    assign axi_rdata = axi_rdata_reg;
    
    // Latch address and use latched address for write and readback
    always @(posedge clk) begin
        // latch incoming address each cycle
        axi_addr_reg <= axi_addr;
        
        // Use latched address for write so address and data align to the same cycle
        if (axi_we) begin
            memory[axi_addr_reg] <= axi_wdata;
        end
        
        // CPU read port (separate port)
        cpu_rdata_reg <= memory[cpu_addr];
        
        // AXI readback returns content at latched address
        axi_rdata_reg <= memory[axi_addr_reg];
    end

endmodule