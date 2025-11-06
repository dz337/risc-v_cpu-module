// riscv_branch_unit.v
// Branch comparison and target calculation
// Implements all RISC-V branch conditions

module riscv_branch_unit (
    input  wire [2:0]  funct3,
    input  wire [31:0] rs1_data,
    input  wire [31:0] rs2_data,
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    
    output reg         branch_taken,
    output wire [31:0] branch_target
);

    // Branch function codes
    localparam FUNCT3_BEQ  = 3'b000;
    localparam FUNCT3_BNE  = 3'b001;
    localparam FUNCT3_BLT  = 3'b100;
    localparam FUNCT3_BGE  = 3'b101;
    localparam FUNCT3_BLTU = 3'b110;
    localparam FUNCT3_BGEU = 3'b111;
    
    // Branch target is always PC + immediate
    assign branch_target = pc + imm;
    
    // Branch comparison logic
    always @(*) begin
        case (funct3)
            FUNCT3_BEQ:  branch_taken = (rs1_data == rs2_data);
            FUNCT3_BNE:  branch_taken = (rs1_data != rs2_data);
            FUNCT3_BLT:  branch_taken = ($signed(rs1_data) < $signed(rs2_data));
            FUNCT3_BGE:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
            FUNCT3_BLTU: branch_taken = (rs1_data < rs2_data);
            FUNCT3_BGEU: branch_taken = (rs1_data >= rs2_data);
            default:     branch_taken = 1'b0;
        endcase
    end

endmodule