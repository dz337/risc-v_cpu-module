// riscv_cpu_top.v
// Top-level RISC-V CPU module with AXI interface
// Integrates all CPU components

module riscv_cpu_top (
    input  wire        clk,
    input  wire        rst_n,
    
    // AXI-Lite interface for ARM to load programs and control CPU
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
    
    // Optional GPIO for testing
    output wire [7:0]  gpio_out
);

    // Internal bus signals from AXI interface
    wire        bus_we;
    wire [31:0] bus_addr;
    wire [31:0] bus_wdata;
    wire [31:0] bus_rdata;
    
    // Control signals
    wire [31:0] cpu_ctrl;
    wire [31:0] cpu_status;
    wire [31:0] pc_read;
    wire [31:0] axi_pc_write;
    wire        axi_pc_we;
    
    // Instruction memory AXI interface
    wire        axi_instr_we;
    wire [11:0] axi_instr_addr;
    wire [31:0] axi_instr_wdata;
    wire [31:0] instr_rdata;
    
    // Data memory read
    wire [31:0] data_rdata;
    
    // Register file access
    wire [31:0] reg_rdata;
    
    // Pipeline to instruction memory
    wire [11:0] instr_addr;
    wire [31:0] instruction;
    
    // Pipeline to data memory
    wire        data_we;
    wire [11:0] data_addr;
    wire [31:0] data_wdata;
    wire [3:0]  data_wstrb;
    
    // Pipeline control/status
    wire        cpu_running;
    wire        cpu_halted;
    wire [2:0]  cpu_state;
    
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
        
        // Internal bus
        .bus_we(bus_we),
        .bus_addr(bus_addr),
        .bus_wdata(bus_wdata),
        .bus_rdata(bus_rdata),
        
        // CPU control/status
        .cpu_ctrl(cpu_ctrl),
        .cpu_status(cpu_status),
        .pc_read(pc_read),
        .axi_pc_write(axi_pc_write),
        .axi_pc_we(axi_pc_we),
        
        // Instruction memory interface
        .axi_instr_we(axi_instr_we),
        .axi_instr_addr(axi_instr_addr),
        .axi_instr_wdata(axi_instr_wdata),
        .instr_rdata(instr_rdata),
        
        // Data memory interface
        .data_rdata(data_rdata),
        
        // Register file interface
        .reg_addr(bus_addr[6:2]),
        .reg_rdata(reg_rdata),
        
        // Status inputs
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
        
        // Control
        .cpu_ctrl(cpu_ctrl),
        .axi_pc_write(axi_pc_write),
        .axi_pc_we(axi_pc_we),
        
        // Status outputs
        .cpu_running(cpu_running),
        .cpu_halted(cpu_halted),
        .cpu_state(cpu_state),
        .pc(pc_read),
        
        // Instruction memory interface
        .instr_addr(instr_addr),
        .instruction(instruction),
        
        // Data memory interface
        .data_we(data_we),
        .data_addr(data_addr),
        .data_wdata(data_wdata),
        .data_wstrb(data_wstrb),
        .data_rdata(data_rdata),
        
        // Register file interface
        .reg_rdata(reg_rdata),
        
        // GPIO
        .gpio_out(gpio_out)
    );
    
    //==========================================================================
    // Instruction Memory
    //==========================================================================
    instruction_memory imem (
        .clk(clk),
        
        // CPU interface
        .cpu_addr(instr_addr),
        .cpu_rdata(instruction),
        
        // AXI interface
        .axi_we(axi_instr_we),
        .axi_addr(axi_instr_addr),
        .axi_wdata(axi_instr_wdata),
        .axi_rdata(instr_rdata)
    );
    
    //==========================================================================
    // Data Memory
    //==========================================================================
    data_memory dmem (
        .clk(clk),
        
        // CPU interface
        .we(data_we),
        .addr(data_addr),
        .wdata(data_wdata),
        .wstrb(data_wstrb),
        .rdata(data_rdata)
    );
    
    // Status for AXI
    assign cpu_status = {29'b0, cpu_halted, cpu_running, cpu_state};

endmodule