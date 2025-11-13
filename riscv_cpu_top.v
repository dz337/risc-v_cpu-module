// riscv_cpu_top.v - COMPLETE FIXED VERSION
// Top-level RISC-V CPU module with AXI interface
// FIX: Added bus_rdata mux and address muxing

module riscv_cpu_top (
    input  wire        clk,
    input  wire        rst_n,
    
    // AXI-Lite interface
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [31:0] S_AXI_AWADDR,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output wire        S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [31:0] S_AXI_ARADDR,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output wire [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY,
    
    output wire [7:0]  gpio_out
);

    // Internal signals
    wire        bus_we;
    wire [31:0] bus_addr;
    wire [31:0] bus_wdata;
    wire [31:0] bus_rdata;  // Will be driven by bus_rdata_mux
    
    wire [31:0] cpu_ctrl;
    wire [31:0] cpu_status;
    wire [31:0] pc_read;
    wire [31:0] axi_pc_write;
    wire        axi_pc_we;
    
    wire        axi_instr_we;
    wire [11:0] axi_instr_addr;
    wire [31:0] axi_instr_wdata;
    wire [31:0] instr_rdata;
    
    wire        axi_data_we;
    wire [11:0] axi_data_addr;
    wire [31:0] axi_data_wdata;
    wire [3:0]  axi_data_wstrb;
    wire [31:0] data_rdata_axi;
    
    wire [11:0] read_instr_addr;
    wire [11:0] read_data_addr;
    
    wire [31:0] reg_rdata;
    
    wire [11:0] instr_addr;
    wire [31:0] instruction;
    
    wire        data_we;
    wire [11:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_wstrb;
    wire [31:0] data_rdata_cpu;
    
    wire        cpu_running;
    wire        cpu_halted;
    wire [2:0]  cpu_state;
    
    // Muxed memory addresses
    wire [11:0] final_instr_addr;
    wire [11:0] final_data_addr;
    
    assign final_instr_addr = axi_instr_we ? axi_instr_addr : read_instr_addr;
    assign final_data_addr = axi_data_we ? axi_data_addr : read_data_addr;
    
    //==========================================================================
    // CRITICAL FIX: bus_rdata mux
    // This is what was missing! CPU has external memories, so mux is here.
    //==========================================================================
    reg [31:0] bus_rdata_mux;
    
    always @(*) begin
        case (bus_addr[7:2])
            6'h00:   bus_rdata_mux = cpu_ctrl;
            6'h01:   bus_rdata_mux = cpu_status;
            6'h02:   bus_rdata_mux = pc_read;
            6'h03:   bus_rdata_mux = reg_rdata;
            default: begin
                if (bus_addr[7:2] >= 6'h10 && bus_addr[7:2] < 6'h20)
                    bus_rdata_mux = instr_rdata;
                else if (bus_addr[7:2] >= 6'h20)
                    bus_rdata_mux = data_rdata_axi;
                else
                    bus_rdata_mux = 32'h52495343;
            end
        endcase
    end
    
    assign bus_rdata = bus_rdata_mux;
    
    //==========================================================================
    // AXI Interface Module
    //==========================================================================
    cpu_axi_interface axi_if (
        .S_AXI_ACLK(S_AXI_ACLK),
        .S_AXI_ARESETN(S_AXI_ARESETN),
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),
        
        .bus_we(bus_we),
        .bus_addr(bus_addr),
        .bus_wdata(bus_wdata),
        .bus_rdata(bus_rdata),  // From our mux above!
        
        .cpu_ctrl(cpu_ctrl),
        .cpu_status(cpu_status),
        .pc_read(pc_read),
        .axi_pc_write(axi_pc_write),
        .axi_pc_we(axi_pc_we),
        
        .axi_instr_we(axi_instr_we),
        .axi_instr_addr(axi_instr_addr),
        .axi_instr_wdata(axi_instr_wdata),
        .instr_rdata(instr_rdata),
        
        .axi_data_we(axi_data_we),
        .axi_data_addr(axi_data_addr),
        .axi_data_wdata(axi_data_wdata),
        .axi_data_wstrb(axi_data_wstrb),
        .data_rdata(data_rdata_axi),
        
        .read_instr_addr(read_instr_addr),
        .read_data_addr(read_data_addr),
        
        .reg_addr(bus_addr[6:2]),
        .reg_rdata(reg_rdata),
        
        .cpu_running(cpu_running),
        .cpu_halted(cpu_halted),
        .cpu_state(cpu_state)
    );
    
    //==========================================================================
    // CPU Pipeline
    //==========================================================================
    riscv_cpu_pipeline pipeline (
        .clk(clk),
        .rst_n(rst_n),
        .cpu_ctrl(cpu_ctrl),
        .axi_pc_write(axi_pc_write),
        .axi_pc_we(axi_pc_we),
        .cpu_running(cpu_running),
        .cpu_halted(cpu_halted),
        .cpu_state(cpu_state),
        .pc(pc_read),
        .instr_addr(instr_addr),
        .instruction(instruction),
        .data_we(data_we),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_wstrb(data_wstrb),
        .data_rdata(data_rdata_cpu),
        .reg_rdata(reg_rdata),
        .gpio_out(gpio_out)
    );
    
    //==========================================================================
    // Instruction Memory
    //==========================================================================
    instruction_memory imem (
        .clk(clk),
        .cpu_addr(instr_addr),
        .cpu_rdata(instruction),
        .axi_we(axi_instr_we),
        .axi_addr(final_instr_addr),
        .axi_wdata(axi_instr_wdata),
        .axi_rdata(instr_rdata)
    );
    
    //==========================================================================
    // Data Memory
    //==========================================================================
    data_memory_dual_port dmem (
        .clk(clk),
        .cpu_we(data_we),
        .cpu_addr(data_addr),
        .cpu_wdata(data_wdata),
        .cpu_wstrb(data_wstrb),
        .cpu_rdata(data_rdata_cpu),
        .axi_we(axi_data_we),
        .axi_addr(final_data_addr),
        .axi_wdata(axi_data_wdata),
        .axi_wstrb(axi_data_wstrb),
        .axi_rdata(data_rdata_axi)
    );
    
    assign cpu_status = {29'b0, cpu_halted, cpu_running, cpu_state};

endmodule

// (Include data_memory_dual_port module as in your document)
//==============================================================================
// NEW: True Dual Port Data Memory
//==============================================================================
// data_memory.v - FIXED DUAL PORT VERSION
// Data BRAM (16KB = 4096 x 32-bit words)
// Byte-addressable with write strobes
// True dual port: CPU port A, AXI port B

module data_memory_dual_port (
    input  wire        clk,
    
    // CPU port (Port A)
    input  wire        cpu_we,
    input  wire [11:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_wstrb,
    output wire [31:0] cpu_rdata,
    
    // AXI port (Port B)
    input  wire        axi_we,
    input  wire [11:0] axi_addr,
    input  wire [31:0] axi_wdata,
    input  wire [3:0]  axi_wstrb,
    output wire [31:0] axi_rdata
);

    parameter DEPTH = 4096;
    
    // Data memory storage
    reg [31:0] memory [0:DEPTH-1];
    
    // Port A (CPU) - registered output
    reg [31:0] cpu_rdata_reg;
    
    always @(posedge clk) begin
        if (cpu_we) begin
            // Byte-addressable write with strobe (CPU port)
            if (cpu_wstrb[0]) memory[cpu_addr][7:0]   <= cpu_wdata[7:0];
            if (cpu_wstrb[1]) memory[cpu_addr][15:8]  <= cpu_wdata[15:8];
            if (cpu_wstrb[2]) memory[cpu_addr][23:16] <= cpu_wdata[23:16];
            if (cpu_wstrb[3]) memory[cpu_addr][31:24] <= cpu_wdata[31:24];
        end
        cpu_rdata_reg <= memory[cpu_addr];
    end
    
    assign cpu_rdata = cpu_rdata_reg;
    
    // Port B (AXI) - independent read/write port
    reg [31:0] axi_rdata_reg;
    
    always @(posedge clk) begin
        // AXI write uses current address when write enable is high
        if (axi_we) begin
            if (axi_wstrb[0]) memory[axi_addr][7:0]   <= axi_wdata[7:0];
            if (axi_wstrb[1]) memory[axi_addr][15:8]  <= axi_wdata[15:8];
            if (axi_wstrb[2]) memory[axi_addr][23:16] <= axi_wdata[23:16];
            if (axi_wstrb[3]) memory[axi_addr][31:24] <= axi_wdata[31:24];
        end
        
        // AXI readback of current address
        axi_rdata_reg <= memory[axi_addr];
    end
    
    assign axi_rdata = axi_rdata_reg;

endmodule