// cpu_axi_interface.v - FIXED ar_addr capture
// Key fix: ar_addr now properly captured and held throughout read transaction

module cpu_axi_interface (
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
    
    output wire        bus_we,
    output wire [31:0] bus_addr,
    output wire [31:0] bus_wdata,
    input  wire [31:0] bus_rdata,
    
    output reg  [31:0] cpu_ctrl,
    input  wire [31:0] cpu_status,
    input  wire [31:0] pc_read,
    output reg  [31:0] axi_pc_write,
    output reg         axi_pc_we,
    
    output reg         axi_instr_we,
    output reg  [11:0] axi_instr_addr,
    output reg  [31:0] axi_instr_wdata,
    input  wire [31:0] instr_rdata,
    
    output reg         axi_data_we,
    output reg  [11:0] axi_data_addr,
    output reg  [31:0] axi_data_wdata,
    output reg  [3:0]  axi_data_wstrb,
    input  wire [31:0] data_rdata,
    
    output wire [11:0] read_instr_addr,
    output wire [11:0] read_data_addr,
    
    input  wire [4:0]  reg_addr,
    input  wire [31:0] reg_rdata,
    
    input  wire        cpu_running,
    input  wire        cpu_halted,
    input  wire [2:0]  cpu_state
);

    // Parameters
    localparam ADDR_CPU_CTRL    = 6'h00;
    localparam ADDR_CPU_STATUS  = 6'h01;
    localparam ADDR_CPU_PC      = 6'h02;
    localparam ADDR_CPU_REG     = 6'h03;
    localparam ADDR_INSTR_BASE  = 6'h10;
    localparam ADDR_DATA_BASE   = 6'h20;
    
    // Write FSM
    localparam WR_IDLE = 2'b00;
    localparam WR_EXECUTE = 2'b10;
    localparam WR_DONE = 2'b11;
    
    // Read FSM
    localparam RD_IDLE = 2'b00;
    localparam RD_WAIT1 = 2'b01;
    localparam RD_WAIT2 = 2'b10;
    localparam RD_DONE = 2'b11;
    
    // Write types
    localparam TYPE_NONE  = 3'b000;
    localparam TYPE_CTRL  = 3'b001;
    localparam TYPE_PC    = 3'b010;
    localparam TYPE_INSTR = 3'b011;
    localparam TYPE_DATA  = 3'b100;
    
    // Registers
    reg [1:0] write_state;
    reg write_complete;
    reg [2:0] write_type;
    reg [1:0] read_state;
    
    reg        aw_done, w_done;
    reg [31:0] aw_addr, w_data;
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
    
    reg [11:0] read_instr_addr_reg;
    reg [11:0] read_data_addr_reg;
    
    //==========================================================================
    // CRITICAL FIX: Read Address Capture
    // ar_addr must be captured when ARREADY & ARVALID and held until read completes
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            ar_addr <= 32'd0;
        end else begin
            // Capture address when handshake occurs
            if (S_AXI_ARREADY_reg && S_AXI_ARVALID) begin
                ar_addr <= S_AXI_ARADDR;
            end
            // Hold ar_addr throughout the read transaction
            // It will only change on the next ARVALID handshake
        end
    end
    
    //==========================================================================
    // Read Address Computation (uses captured ar_addr, not ARADDR directly)
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            read_instr_addr_reg <= 12'h0;
            read_data_addr_reg <= 12'h0;
        end else if (S_AXI_ARREADY_reg && S_AXI_ARVALID) begin
            read_instr_addr_reg <= (S_AXI_ARADDR[7:2] >= ADDR_INSTR_BASE && 
                                   S_AXI_ARADDR[7:2] < ADDR_DATA_BASE) ? 
                                  ({6'b0, S_AXI_ARADDR[7:2]} - {6'b0, ADDR_INSTR_BASE}) : 12'h0;
            
            read_data_addr_reg <= (S_AXI_ARADDR[7:2] >= ADDR_DATA_BASE) ? 
                                 ({6'b0, S_AXI_ARADDR[7:2]} - {6'b0, ADDR_DATA_BASE}) : 12'h0;
        end
    end
    
    assign read_instr_addr = read_instr_addr_reg;
    assign read_data_addr = read_data_addr_reg;
    
    //==========================================================================
    // Write Address Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY_reg <= 1'b0;
            aw_done <= 1'b0;
            aw_addr <= 32'd0;
        end else begin
            if (!aw_done && S_AXI_AWVALID && (write_state == WR_IDLE)) begin
                S_AXI_AWREADY_reg <= 1'b1;
                aw_addr <= S_AXI_AWADDR;
                aw_done <= 1'b1;
            end else begin
                S_AXI_AWREADY_reg <= 1'b0;
            end
            
            if (write_complete) aw_done <= 1'b0;
        end
    end
    
    //==========================================================================
    // Write Data Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_WREADY_reg <= 1'b0;
            w_done <= 1'b0;
            w_data <= 32'd0;
            w_strb <= 4'b0000;
        end else begin
            if (!w_done && S_AXI_WVALID && (write_state == WR_IDLE)) begin
                S_AXI_WREADY_reg <= 1'b1;
                w_data <= S_AXI_WDATA;
                w_strb <= S_AXI_WSTRB;
                w_done <= 1'b1;
            end else begin
                S_AXI_WREADY_reg <= 1'b0;
            end
            
            if (write_complete) w_done <= 1'b0;
        end
    end
    
    //==========================================================================
    // Write State Machine
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            cpu_ctrl <= 32'h0;
            axi_pc_write <= 32'h0;
            axi_pc_we <= 1'b0;
            axi_instr_we <= 1'b0;
            axi_instr_addr <= 12'h0;
            axi_instr_wdata <= 32'h0;
            axi_data_we <= 1'b0;
            axi_data_addr <= 12'h0;
            axi_data_wdata <= 32'h0;
            axi_data_wstrb <= 4'h0;
            write_state <= WR_IDLE;
            write_complete <= 1'b0;
            write_type <= TYPE_NONE;
        end else begin
            axi_pc_we <= 1'b0;
            axi_instr_we <= 1'b0;
            axi_data_we <= 1'b0;
            write_complete <= 1'b0;
            
            case (write_state)
                WR_IDLE: begin
                    if (aw_done && w_done && !S_AXI_BVALID_reg) begin
                        case (aw_addr[7:2])
                            ADDR_CPU_CTRL: begin
                                cpu_ctrl <= w_data;
                                write_type <= TYPE_CTRL;
                                write_complete <= 1'b1;
                                write_state <= WR_DONE;
                            end
                            ADDR_CPU_PC: begin
                                axi_pc_write <= w_data;
                                write_type <= TYPE_PC;
                                write_state <= WR_EXECUTE;
                            end
                            default: begin
                                if (aw_addr[7:2] >= ADDR_INSTR_BASE && 
                                    aw_addr[7:2] < ADDR_DATA_BASE) begin
                                    axi_instr_addr <= {6'b0, aw_addr[7:2]} - {6'b0, ADDR_INSTR_BASE};
                                    axi_instr_wdata <= w_data;
                                    write_type <= TYPE_INSTR;
                                    write_state <= WR_EXECUTE;
                                end
                                else if (aw_addr[7:2] >= ADDR_DATA_BASE) begin
                                    axi_data_addr <= {6'b0, aw_addr[7:2]} - {6'b0, ADDR_DATA_BASE};
                                    axi_data_wdata <= w_data;
                                    axi_data_wstrb <= w_strb;
                                    write_type <= TYPE_DATA;
                                    write_state <= WR_EXECUTE;
                                end
                                else begin
                                    write_type <= TYPE_NONE;
                                    write_complete <= 1'b1;
                                    write_state <= WR_DONE;
                                end
                            end
                        endcase
                    end
                end
                WR_EXECUTE: begin
                    case (write_type)
                        TYPE_PC: axi_pc_we <= 1'b1;
                        TYPE_INSTR: axi_instr_we <= 1'b1;
                        TYPE_DATA: axi_data_we <= 1'b1;
                        default: ;
                    endcase
                    write_state <= WR_DONE;
                end
                WR_DONE: begin
                    write_complete <= 1'b1;
                    write_type <= TYPE_NONE;
                    write_state <= WR_IDLE;
                end
                default: write_state <= WR_IDLE;
            endcase
        end
    end
    
    //==========================================================================
    // Write Response Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_BVALID_reg <= 1'b0;
            S_AXI_BRESP_reg <= 2'b00;
        end else begin
            if (write_complete && !S_AXI_BVALID_reg) begin
                S_AXI_BVALID_reg <= 1'b1;
                S_AXI_BRESP_reg <= 2'b00;
            end else if (S_AXI_BVALID_reg && S_AXI_BREADY) begin
                S_AXI_BVALID_reg <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // Read State Machine  
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            read_state <= RD_IDLE;
            S_AXI_ARREADY_reg <= 1'b1;  // Start ready
        end else begin
            case (read_state)
                RD_IDLE: begin
                    if (S_AXI_ARVALID && S_AXI_ARREADY_reg) begin
                        read_state <= RD_WAIT1;
                        S_AXI_ARREADY_reg <= 1'b0;  // Not ready during processing
                    end else begin
                        S_AXI_ARREADY_reg <= 1'b1;  // Stay ready
                    end
                end
                RD_WAIT1: begin
                    S_AXI_ARREADY_reg <= 1'b0;
                    read_state <= RD_WAIT2;
                end
                RD_WAIT2: begin
                    S_AXI_ARREADY_reg <= 1'b0;
                    read_state <= RD_DONE;
                end
                RD_DONE: begin
                    S_AXI_ARREADY_reg <= 1'b0;
                    if (S_AXI_RVALID_reg && S_AXI_RREADY) begin
                        read_state <= RD_IDLE;
                        S_AXI_ARREADY_reg <= 1'b1;  // Ready for next transaction
                    end
                end
            endcase
        end
    end 
    
    //==========================================================================
    // Internal Read Data Mux (uses captured ar_addr)
    //==========================================================================
    reg [31:0] read_data_mux;
    
    always @(*) begin
        case (ar_addr[7:2])
            ADDR_CPU_CTRL:   read_data_mux = cpu_ctrl;
            ADDR_CPU_STATUS: read_data_mux = cpu_status;
            ADDR_CPU_PC:     read_data_mux = pc_read;
            ADDR_CPU_REG:    read_data_mux = reg_rdata;
            default:         read_data_mux = bus_rdata;
        endcase
    end
    
    //==========================================================================
    // Read Data Channel
    //==========================================================================
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RVALID_reg <= 1'b0;
            S_AXI_RRESP_reg <= 2'b00;
            S_AXI_RDATA_reg <= 32'd0;
        end else begin
            if (read_state == RD_DONE && !S_AXI_RVALID_reg) begin
                S_AXI_RVALID_reg <= 1'b1;
                S_AXI_RRESP_reg <= 2'b00;
                S_AXI_RDATA_reg <= read_data_mux;
            end else if (S_AXI_RVALID_reg && S_AXI_RREADY) begin
                S_AXI_RVALID_reg <= 1'b0;
                S_AXI_RDATA_reg <= 32'd0;
            end
        end
    end
    
    //==========================================================================
    // Output Assignments
    //==========================================================================
    assign bus_we = 1'b0;
    assign bus_addr = ar_addr;  // Uses captured address
    assign bus_wdata = 32'h0;
        
    assign S_AXI_AWREADY = S_AXI_AWREADY_reg;
    assign S_AXI_WREADY = S_AXI_WREADY_reg;
    assign S_AXI_BRESP = S_AXI_BRESP_reg;
    assign S_AXI_BVALID = S_AXI_BVALID_reg;
    assign S_AXI_ARREADY = S_AXI_ARREADY_reg;
    assign S_AXI_RDATA = S_AXI_RDATA_reg;
    assign S_AXI_RRESP = S_AXI_RRESP_reg;
    assign S_AXI_RVALID = S_AXI_RVALID_reg;

endmodule