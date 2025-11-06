// cpu_axi_interface.v
// AXI-Lite interface handler for RISC-V CPU
// Handles memory-mapped control, status, and memory access

module cpu_axi_interface (
    // AXI-Lite signals
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
    
    // Internal bus
    output wire        bus_we,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_wdata,
    input  wire [31:0] bus_rdata,
    
    // CPU control/status
    output reg  [31:0] cpu_ctrl,
    input  wire [31:0] cpu_status,
    input  wire [31:0] pc_read,
    output reg  [31:0] axi_pc_write,
    output reg         axi_pc_we,
    
    // Instruction memory interface
    output reg         axi_instr_we,
    output reg  [11:0] axi_instr_addr,
    output reg  [31:0] axi_instr_wdata,
    input  wire [31:0] instr_rdata,
    
    // Data memory interface
    input  wire [31:0] data_rdata,
    
    // Register file interface
    input  wire [4:0]  reg_addr,
    input  wire [31:0] reg_rdata,
    
    // Status inputs
    input  wire        cpu_running,
    input  wire        cpu_halted,
    input  wire [2:0]  cpu_state
);

    // Memory map addresses (word-aligned)
    localparam ADDR_CPU_CTRL    = 6'h00;  // 0x00
    localparam ADDR_CPU_STATUS  = 6'h01;  // 0x04
    localparam ADDR_CPU_PC      = 6'h02;  // 0x08
    localparam ADDR_CPU_REG     = 6'h03;  // 0x0C
    localparam ADDR_INSTR_BASE  = 6'h10;  // 0x40+
    localparam ADDR_DATA_BASE   = 6'h20;  // 0x80+
    
    // AXI protocol state
    reg        aw_done;
    reg [31:0] aw_addr;
    reg        w_done;
    reg [31:0] w_data;
    reg [3:0]  w_strb;
    reg [31:0] ar_addr;
    
    reg        S_AXI_AWREADY_reg;
    reg        S_AXI_WREADY_reg;
    reg [1:0]  S_AXI_BRESP_reg;
    reg        S_AXI_BVALID_reg;
    reg        S_AXI_ARREADY_reg;
    reg [31:0] S_AXI_RDATA_reg;
    reg [1:0]  S_AXI_RRESP_reg;
    reg        S_AXI_RVALID_reg;
    
    //==========================================================================
    // AXI Write Address Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY_reg <= 1'b0;
            aw_done <= 1'b0;
            aw_addr <= 32'd0;
        end else begin
            if (!aw_done && S_AXI_AWVALID) begin
                S_AXI_AWREADY_reg <= 1'b1;
                aw_addr <= S_AXI_AWADDR;
                aw_done <= 1'b1;
            end else begin
                S_AXI_AWREADY_reg <= 1'b0;
            end
            if (S_AXI_BVALID_reg && S_AXI_BREADY) begin
                aw_done <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // AXI Write Data Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_WREADY_reg <= 1'b0;
            w_done <= 1'b0;
            w_data <= 32'd0;
            w_strb <= 4'b0000;
        end else begin
            if (!w_done && S_AXI_WVALID) begin
                S_AXI_WREADY_reg <= 1'b1;
                w_data <= S_AXI_WDATA;
                w_strb <= S_AXI_WSTRB;
                w_done <= 1'b1;
            end else begin
                S_AXI_WREADY_reg <= 1'b0;
            end
            if (S_AXI_BVALID_reg && S_AXI_BREADY) begin
                w_done <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // AXI Write Response Channel
    //==========================================================================
    wire write_ready = aw_done && w_done && !S_AXI_BVALID_reg;
    
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_BVALID_reg <= 1'b0;
            S_AXI_BRESP_reg <= 2'b00;
        end else begin
            if (write_ready) begin
                S_AXI_BVALID_reg <= 1'b1;
                S_AXI_BRESP_reg <= 2'b00;
            end else if (S_AXI_BVALID_reg && S_AXI_BREADY) begin
                S_AXI_BVALID_reg <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // AXI Read Address Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY_reg <= 1'b0;
            ar_addr <= 32'd0;
        end else begin
            if (!S_AXI_ARREADY_reg && S_AXI_ARVALID && !S_AXI_RVALID_reg) begin
                S_AXI_ARREADY_reg <= 1'b1;
                ar_addr <= S_AXI_ARADDR;
            end else begin
                S_AXI_ARREADY_reg <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // AXI Read Data Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID_reg <= 1'b0;
            S_AXI_RRESP_reg <= 2'b00;
            S_AXI_RDATA_reg <= 32'd0;
        end else begin
            if (S_AXI_ARREADY_reg && S_AXI_ARVALID && !S_AXI_RVALID_reg) begin
                S_AXI_RVALID_reg <= 1'b1;
                S_AXI_RRESP_reg <= 2'b00;
                S_AXI_RDATA_reg <= bus_rdata;
            end else if (S_AXI_RVALID_reg && S_AXI_RREADY) begin
                S_AXI_RVALID_reg <= 1'b0;
                S_AXI_RDATA_reg <= 32'd0;
            end
        end
    end
    
    //==========================================================================
    // Internal Bus Connections
    //==========================================================================
    assign bus_we = write_ready;
    assign bus_addr = write_ready ? aw_addr : ar_addr;
    assign bus_wdata = w_data;
    
    //==========================================================================
    // Register Write Logic
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            cpu_ctrl <= 32'h0;
            axi_pc_write <= 32'h0;
            axi_pc_we <= 1'b0;
            axi_instr_we <= 1'b0;
            axi_instr_addr <= 12'h0;
            axi_instr_wdata <= 32'h0;
        end else begin
            axi_pc_we <= 1'b0;
            axi_instr_we <= 1'b0;
            
            if (bus_we) begin
                case (bus_addr[7:2])
                    ADDR_CPU_CTRL: cpu_ctrl <= bus_wdata;
                    ADDR_CPU_PC: begin
                        axi_pc_write <= bus_wdata;
                        axi_pc_we <= 1'b1;
                    end
                    default: begin
                        // Instruction memory write
                        if (bus_addr[7:2] >= ADDR_INSTR_BASE && 
                            bus_addr[7:2] < ADDR_INSTR_BASE + 16) begin
                            axi_instr_we <= 1'b1;
                            axi_instr_addr <= (bus_addr[7:2] - ADDR_INSTR_BASE);
                            axi_instr_wdata <= bus_wdata;
                        end
                    end
                endcase
            end
        end
    end
    
    //==========================================================================
    // Register Read Logic
    //==========================================================================
    reg [31:0] bus_rdata_reg;
    
    always @(*) begin
        case (bus_addr[7:2])
            ADDR_CPU_CTRL:   bus_rdata_reg = cpu_ctrl;
            ADDR_CPU_STATUS: bus_rdata_reg = cpu_status;
            ADDR_CPU_PC:     bus_rdata_reg = pc_read;
            ADDR_CPU_REG:    bus_rdata_reg = reg_rdata;
            default: begin
                if (bus_addr[7:2] >= ADDR_INSTR_BASE && 
                    bus_addr[7:2] < ADDR_INSTR_BASE + 16) begin
                    bus_rdata_reg = instr_rdata;
                end else if (bus_addr[7:2] >= ADDR_DATA_BASE) begin
                    bus_rdata_reg = data_rdata;
                end else begin
                    bus_rdata_reg = 32'h52495343;  // "RISC" signature
                end
            end
        endcase
    end
    
    assign bus_rdata = bus_rdata_reg;
    
    //==========================================================================
    // Output Assignments
    //==========================================================================
    assign S_AXI_AWREADY = S_AXI_AWREADY_reg;
    assign S_AXI_WREADY = S_AXI_WREADY_reg;
    assign S_AXI_BRESP = S_AXI_BRESP_reg;
    assign S_AXI_BVALID = S_AXI_BVALID_reg;
    assign S_AXI_ARREADY = S_AXI_ARREADY_reg;
    assign S_AXI_RDATA = S_AXI_RDATA_reg;
    assign S_AXI_RRESP = S_AXI_RRESP_reg;
    assign S_AXI_RVALID = S_AXI_RVALID_reg;

endmodule