// riscv_register_file.v
// RISC-V 32-register register file
// x0 is hardwired to 0, x1-x31 are general purpose

module riscv_register_file (
    input  wire        clk,
    input  wire        rst_n,
    
    // Read port 1 (rs1)
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,
    
    // Read port 2 (rs2)
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,
    
    // Write port (rd)
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data,
    input  wire        rd_we,
    
    // AXI read port (for debugging/monitoring)
    output wire [31:0] axi_rdata
);

    // Register storage
    reg [31:0] registers [0:31];
    
    // Asynchronous reads (combinational)
    assign rs1_data = (rs1_addr == 5'b0) ? 32'h0 : registers[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'h0 : registers[rs2_addr];
    
    // AXI read - reads from rs1_addr for simplicity
    assign axi_rdata = (rs1_addr == 5'b0) ? 32'h0 : registers[rs1_addr];
    
    // Synchronous write
    always @(posedge clk) begin
        if (!rst_n) begin
            // Initialize all registers to 0
            registers[0]  <= 32'h0;
            registers[1]  <= 32'h0;
            registers[2]  <= 32'h0;
            registers[3]  <= 32'h0;
            registers[4]  <= 32'h0;
            registers[5]  <= 32'h0;
            registers[6]  <= 32'h0;
            registers[7]  <= 32'h0;
            registers[8]  <= 32'h0;
            registers[9]  <= 32'h0;
            registers[10] <= 32'h0;
            registers[11] <= 32'h0;
            registers[12] <= 32'h0;
            registers[13] <= 32'h0;
            registers[14] <= 32'h0;
            registers[15] <= 32'h0;
            registers[16] <= 32'h0;
            registers[17] <= 32'h0;
            registers[18] <= 32'h0;
            registers[19] <= 32'h0;
            registers[20] <= 32'h0;
            registers[21] <= 32'h0;
            registers[22] <= 32'h0;
            registers[23] <= 32'h0;
            registers[24] <= 32'h0;
            registers[25] <= 32'h0;
            registers[26] <= 32'h0;
            registers[27] <= 32'h0;
            registers[28] <= 32'h0;
            registers[29] <= 32'h0;
            registers[30] <= 32'h0;
            registers[31] <= 32'h0;
        end else begin
            // Write to register (except x0)
            if (rd_we && rd_addr != 5'b0) begin
                registers[rd_addr] <= rd_data;
            end
        end
    end

endmodule