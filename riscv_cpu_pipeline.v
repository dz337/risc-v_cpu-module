// riscv_cpu_pipeline.v
// Main CPU pipeline controller
// Integrates decoder, ALU, branch unit, register file, and control

module riscv_cpu_pipeline (
    input  wire        clk,
    input  wire        rst_n,
    
    // Control interface
    input  wire [31:0] cpu_ctrl,
    input  wire [31:0] axi_pc_write,
    input  wire        axi_pc_we,
    
    // Status outputs
    output reg         cpu_running,
    output reg         cpu_halted,
    output reg  [2:0]  cpu_state,
    output wire [31:0] pc,
    
    // Instruction memory interface
    output wire [11:0] instr_addr,
    input  wire [31:0] instruction,
    
    // Data memory interface
    output reg         data_we,
    output reg  [11:0] data_addr,
    output reg  [31:0] data_wdata,
    output reg  [3:0]  data_wstrb,
    input  wire [31:0] data_rdata,
    
    // Register file interface (for AXI reads)
    input  wire [31:0] reg_rdata,
    
    // GPIO
    output reg  [7:0]  gpio_out
);

    // CPU control bits
    localparam CTRL_RUN    = 0;
    localparam CTRL_RESET  = 1;
    localparam CTRL_STEP   = 2;
    
    // CPU states
    localparam STATE_IDLE   = 3'b000;
    localparam STATE_FETCH  = 3'b001;
    localparam STATE_DECODE = 3'b010;
    localparam STATE_EXEC   = 3'b011;
    localparam STATE_MEM    = 3'b100;
    localparam STATE_WB     = 3'b101;
    
    // Internal signals
    reg [31:0] pc_reg;
    reg [31:0] instruction_reg;
    reg [31:0] next_pc;
    reg [31:0] mem_data;
    reg [31:0] wb_data;
    
    // Decoder outputs
    wire [6:0]  opcode;
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    
    // Register file signals
    wire [31:0] rs1_data, rs2_data;
    reg  [4:0]  rd_addr;
    reg  [31:0] rd_data;
    reg         rd_we;
    
    // ALU signals
    wire [31:0] alu_result;
    reg  [31:0] alu_a, alu_b;
    reg  [3:0]  alu_op;
    
    // Branch unit signals
    wire        branch_taken;
    wire [31:0] branch_target;
    reg  [2:0]  branch_funct3;
    reg  [31:0] branch_rs1_data, branch_rs2_data;
    reg  [31:0] branch_pc, branch_imm;
    
    // Control signals
    wire        ctrl_run, ctrl_reset;
    
    // Initialization
    reg [4:0] init_counter;
    reg       init_done;
    
    assign pc = pc_reg;
    assign instr_addr = pc_reg[13:2];  // Word-aligned
    
    //==========================================================================
    // Decoder Instance
    //==========================================================================
    riscv_decoder decoder (
        .instruction(instruction_reg),
        .opcode(opcode),
        .rd(rd),
        .rs1(rs1),
        .rs2(rs2),
        .funct3(funct3),
        .funct7(funct7),
        .imm_i(imm_i),
        .imm_s(imm_s),
        .imm_b(imm_b),
        .imm_u(imm_u),
        .imm_j(imm_j)
    );
    
    //==========================================================================
    // Register File Instance
    //==========================================================================
    riscv_register_file reg_file (
        .clk(clk),
        .rst_n(rst_n && init_done),
        
        // Read ports
        .rs1_addr(rs1),
        .rs2_addr(rs2),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        
        // Write port
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .rd_we(rd_we),
        
        // AXI read port
        .axi_rdata(reg_rdata)
    );
    
    //==========================================================================
    // ALU Instance
    //==========================================================================
    riscv_alu alu (
        .a(alu_a),
        .b(alu_b),
        .alu_op(alu_op),
        .result(alu_result)
    );
    
    //==========================================================================
    // Branch Unit Instance
    //==========================================================================
    riscv_branch_unit branch_unit (
        .funct3(branch_funct3),
        .rs1_data(branch_rs1_data),
        .rs2_data(branch_rs2_data),
        .pc(branch_pc),
        .imm(branch_imm),
        .branch_taken(branch_taken),
        .branch_target(branch_target)
    );
    
    //==========================================================================
    // Control Instance
    //==========================================================================
    riscv_control control (
        .cpu_ctrl(cpu_ctrl),
        .ctrl_run(ctrl_run),
        .ctrl_reset(ctrl_reset)
    );
    
    //==========================================================================
    // Pipeline State Machine
    //==========================================================================
    
    // RISC-V Opcodes
    localparam OPCODE_LUI    = 7'b0110111;
    localparam OPCODE_AUIPC  = 7'b0010111;
    localparam OPCODE_JAL    = 7'b1101111;
    localparam OPCODE_JALR   = 7'b1100111;
    localparam OPCODE_BRANCH = 7'b1100011;
    localparam OPCODE_LOAD   = 7'b0000011;
    localparam OPCODE_STORE  = 7'b0100011;
    localparam OPCODE_OP_IMM = 7'b0010011;
    localparam OPCODE_OP     = 7'b0110011;
    localparam OPCODE_SYSTEM = 7'b1110011;
    
    // Load/Store function codes
    localparam FUNCT3_LB  = 3'b000;
    localparam FUNCT3_LH  = 3'b001;
    localparam FUNCT3_LW  = 3'b010;
    localparam FUNCT3_LBU = 3'b100;
    localparam FUNCT3_LHU = 3'b101;
    
    // ALU operation codes (internal)
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
    
    always @(posedge clk) begin
        if (!rst_n) begin
            cpu_state <= STATE_IDLE;
            cpu_running <= 1'b0;
            cpu_halted <= 1'b0;
            pc_reg <= 32'h0;
            gpio_out <= 8'h0;
            data_we <= 1'b0;
            rd_we <= 1'b0;
            init_counter <= 5'b0;
            init_done <= 1'b0;
            instruction_reg <= 32'h0;
        end else begin
            data_we <= 1'b0;
            rd_we <= 1'b0;
            
            // Register file initialization
            if (!init_done) begin
                if (init_counter == 5'd31) begin
                    init_done <= 1'b1;
                end else begin
                    init_counter <= init_counter + 1;
                end
            end else begin
                // Handle AXI PC write
                if (axi_pc_we) begin
                    pc_reg <= axi_pc_write;
                end
                
                // Control logic
                if (ctrl_reset) begin
                    cpu_state <= STATE_IDLE;
                    cpu_running <= 1'b0;
                    cpu_halted <= 1'b0;
                    pc_reg <= 32'h0;
                end else if (ctrl_run && !cpu_halted) begin
                    cpu_running <= 1'b1;
                end else if (!ctrl_run) begin
                    cpu_running <= 1'b0;
                end
                
                // Pipeline execution
                if (cpu_running) begin
                    case (cpu_state)
                        STATE_IDLE: begin
                            cpu_state <= STATE_FETCH;
                        end
                        
                        STATE_FETCH: begin
                            cpu_state <= STATE_DECODE;
                        end
                        
                        STATE_DECODE: begin
                            instruction_reg <= instruction;
                            cpu_state <= STATE_EXEC;
                        end
                        
                        STATE_EXEC: begin
                            // Default next PC
                            next_pc = pc_reg + 4;
                            
                            case (opcode)
                                OPCODE_LUI: begin
                                    wb_data = imm_u;
                                    rd_addr = rd;
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_WB;
                                end
                                
                                OPCODE_AUIPC: begin
                                    wb_data = pc_reg + imm_u;
                                    rd_addr = rd;
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_WB;
                                end
                                
                                OPCODE_JAL: begin
                                    wb_data = pc_reg + 4;
                                    rd_addr = rd;
                                    next_pc = pc_reg + imm_j;
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_WB;
                                end
                                
                                OPCODE_JALR: begin
                                    wb_data = pc_reg + 4;
                                    rd_addr = rd;
                                    next_pc = (rs1_data + imm_i) & ~32'h1;
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_WB;
                                end
                                
                                OPCODE_BRANCH: begin
                                    // Setup branch unit
                                    branch_funct3 = funct3;
                                    branch_rs1_data = rs1_data;
                                    branch_rs2_data = rs2_data;
                                    branch_pc = pc_reg;
                                    branch_imm = imm_b;
                                    
                                    if (branch_taken) begin
                                        pc_reg <= branch_target;
                                    end else begin
                                        pc_reg <= next_pc;
                                    end
                                    cpu_state <= STATE_FETCH;
                                end
                                
                                OPCODE_LOAD: begin
                                    data_addr <= (rs1_data + imm_i) >> 2;
                                    cpu_state <= STATE_MEM;
                                end
                                
                                OPCODE_STORE: begin
                                    data_addr <= (rs1_data + imm_s) >> 2;
                                    data_wdata <= rs2_data;
                                    data_we <= 1'b1;
                                    data_wstrb <= 4'b1111;
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_FETCH;
                                end
                                
                                OPCODE_OP_IMM: begin
                                    alu_a = rs1_data;
                                    alu_b = imm_i;
                                    
                                    // Map funct3 to ALU op
                                    case (funct3)
                                        3'b000: alu_op = ALU_ADD;   // ADDI
                                        3'b010: alu_op = ALU_SLT;   // SLTI
                                        3'b011: alu_op = ALU_SLTU;  // SLTIU
                                        3'b100: alu_op = ALU_XOR;   // XORI
                                        3'b110: alu_op = ALU_OR;    // ORI
                                        3'b111: alu_op = ALU_AND;   // ANDI
                                        3'b001: alu_op = ALU_SLL;   // SLLI
                                        3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRLI/SRAI
                                    endcase
                                    
                                    wb_data = alu_result;
                                    rd_addr = rd;
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_WB;
                                end
                                
                                OPCODE_OP: begin
                                    alu_a = rs1_data;
                                    alu_b = rs2_data;
                                    
                                    // Map funct3/funct7 to ALU op
                                    case (funct3)
                                        3'b000: alu_op = funct7[5] ? ALU_SUB : ALU_ADD; // ADD/SUB
                                        3'b001: alu_op = ALU_SLL;   // SLL
                                        3'b010: alu_op = ALU_SLT;   // SLT
                                        3'b011: alu_op = ALU_SLTU;  // SLTU
                                        3'b100: alu_op = ALU_XOR;   // XOR
                                        3'b101: alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRL/SRA
                                        3'b110: alu_op = ALU_OR;    // OR
                                        3'b111: alu_op = ALU_AND;   // AND
                                    endcase
                                    
                                    wb_data = alu_result;
                                    rd_addr = rd;
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_WB;
                                end
                                
                                OPCODE_SYSTEM: begin
                                    // ECALL/EBREAK - halt CPU
                                    cpu_halted <= 1'b1;
                                    cpu_running <= 1'b0;
                                    cpu_state <= STATE_IDLE;
                                end
                                
                                default: begin
                                    pc_reg <= next_pc;
                                    cpu_state <= STATE_FETCH;
                                end
                            endcase
                        end
                        
                        STATE_MEM: begin
                            mem_data <= data_rdata;
                            
                            // Sign-extend based on load type
                            case (funct3)
                                FUNCT3_LB:  wb_data = {{24{data_rdata[7]}}, data_rdata[7:0]};
                                FUNCT3_LH:  wb_data = {{16{data_rdata[15]}}, data_rdata[15:0]};
                                FUNCT3_LW:  wb_data = data_rdata;
                                FUNCT3_LBU: wb_data = {24'b0, data_rdata[7:0]};
                                FUNCT3_LHU: wb_data = {16'b0, data_rdata[15:0]};
                                default:    wb_data = data_rdata;
                            endcase
                            
                            rd_addr = rd;
                            pc_reg <= next_pc;
                            cpu_state <= STATE_WB;
                        end
                        
                        STATE_WB: begin
                            if (rd_addr != 5'b0) begin
                                rd_we <= 1'b1;
                                rd_data <= wb_data;
                            end
                            cpu_state <= STATE_FETCH;
                        end
                        
                        default: cpu_state <= STATE_IDLE;
                    endcase
                end
            end
        end
    end

endmodule