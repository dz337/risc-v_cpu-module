// riscv_alu.v
// RISC-V Arithmetic Logic Unit
// Implements all RV32I ALU operations

module riscv_alu (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result
);

    // ALU operation codes
    localparam ALU_ADD  = 4'h0;
    localparam ALU_SUB  = 4'h1;
    localparam ALU_SLL  = 4'h2;
    localparam ALU_SLT  = 4'h3;
    localparam ALU_SLTU = 4'h4;
    localparam ALU_XOR  = 4'h5;
    localparam ALU_SRL  = 4'h6;
    localparam ALU_SRA  = 4'h7;
    localparam ALU_OR   = 4'h8;
    localparam ALU_AND  = 4'h9;
    
    always @(*) begin
        case (alu_op)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_SLL:  result = a << b[4:0];
            ALU_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;
            ALU_XOR:  result = a ^ b;
            ALU_SRL:  result = a >> b[4:0];
            ALU_SRA:  result = $signed(a) >>> b[4:0];
            ALU_OR:   result = a | b;
            ALU_AND:  result = a & b;
            default:  result = 32'h0;
        endcase
    end

endmodule