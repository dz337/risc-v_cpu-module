// riscv_decoder.v
// RISC-V instruction decoder
// Extracts fields and immediate values from instructions

module riscv_decoder (
    input  wire [31:0] instruction,
    
    // Extracted fields
    output wire [6:0]  opcode,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [6:0]  funct7,
    
    // Decoded immediate values
    output wire [31:0] imm_i,
    output wire [31:0] imm_s,
    output wire [31:0] imm_b,
    output wire [31:0] imm_u,
    output wire [31:0] imm_j
);

    // Extract instruction fields
    assign opcode = instruction[6:0];
    assign rd     = instruction[11:7];
    assign funct3 = instruction[14:12];
    assign rs1    = instruction[19:15];
    assign rs2    = instruction[24:20];
    assign funct7 = instruction[31:25];
    
    // I-type immediate (12 bits, sign-extended)
    // Used by: ADDI, SLTI, XORI, ORI, ANDI, SLLI, SRLI, SRAI, LB, LH, LW, LBU, LHU, JALR
    assign imm_i = {{20{instruction[31]}}, instruction[31:20]};
    
    // S-type immediate (12 bits, sign-extended)
    // Used by: SB, SH, SW
    assign imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    
    // B-type immediate (13 bits, sign-extended, bit 0 = 0)
    // Used by: BEQ, BNE, BLT, BGE, BLTU, BGEU
    assign imm_b = {{19{instruction[31]}}, instruction[31], instruction[7], 
                    instruction[30:25], instruction[11:8], 1'b0};
    
    // U-type immediate (20 bits in upper, lower 12 bits = 0)
    // Used by: LUI, AUIPC
    assign imm_u = {instruction[31:12], 12'b0};
    
    // J-type immediate (21 bits, sign-extended, bit 0 = 0)
    // Used by: JAL
    assign imm_j = {{11{instruction[31]}}, instruction[31], instruction[19:12], 
                    instruction[20], instruction[30:21], 1'b0};

endmodule