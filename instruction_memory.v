// instruction_memory.v - FIXED VERSION
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
    
    // AXI readback register
    reg [31:0] axi_rdata_reg;
    assign axi_rdata = axi_rdata_reg;
    
    // CRITICAL FIX: No address latching here!
    // The address is already stable from cpu_axi_interface latching
    // Just use the address directly when we=1
    always @(posedge clk) begin
        // Write to current address when write enable is high
        if (axi_we) begin
            memory[axi_addr] <= axi_wdata;
        end
        
        // CPU read port (independent)
        cpu_rdata_reg <= memory[cpu_addr];
        
        // AXI readback of current address
        axi_rdata_reg <= memory[axi_addr];
    end

endmodule