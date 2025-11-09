// cpu_axi_interface.v - COMPLETE FIX
// BUG FIX: Added write_type register to track what kind of write we're doing

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
    
    // NEW: Output computed read addresses
    output wire [11:0] read_instr_addr,
    output wire [11:0] read_data_addr,
    
    input  wire [4:0]  reg_addr,
    input  wire [31:0] reg_rdata,
    
    input  wire        cpu_running,
    input  wire        cpu_halted,
    input  wire [2:0]  cpu_state
);

    localparam ADDR_CPU_CTRL    = 6'h00;
    localparam ADDR_CPU_STATUS  = 6'h01;
    localparam ADDR_CPU_PC      = 6'h02;
    localparam ADDR_CPU_REG     = 6'h03;
    localparam ADDR_INSTR_BASE  = 6'h10;
    localparam ADDR_DATA_BASE   = 6'h20;
    localparam ADDR_DEBUG_LAST_ADDR = 6'h0C;
    localparam ADDR_DEBUG_LAST_DATA = 6'h0D;
    localparam ADDR_DEBUG_WRITE_CNT = 6'h0E;
    localparam ADDR_DEBUG_STATE     = 6'h0F;
    
    // State machine states
    localparam WR_IDLE = 2'b00;
    localparam WR_EXECUTE = 2'b10;
    localparam WR_DONE = 2'b11;
    
    // Write type encoding - CRITICAL NEW ADDITION
    localparam TYPE_NONE  = 3'b000;
    localparam TYPE_CTRL  = 3'b001;
    localparam TYPE_PC    = 3'b010;
    localparam TYPE_INSTR = 3'b011;
    localparam TYPE_DATA  = 3'b100;
    
    // Write state machine registers
    reg [1:0] write_state;
    reg write_complete;
    reg [2:0] write_type;  // NEW: Track what kind of write this is
    
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
    
    reg [31:0] debug_last_addr;
    reg [31:0] debug_last_data;
    reg [31:0] debug_write_count;
    
    //==========================================================================
    // AXI Write Address Channel
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
            
            if (write_complete) begin
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
            if (!w_done && S_AXI_WVALID && (write_state == WR_IDLE)) begin
                S_AXI_WREADY_reg <= 1'b1;
                w_data <= S_AXI_WDATA;
                w_strb <= S_AXI_WSTRB;
                w_done <= 1'b1;
            end else begin
                S_AXI_WREADY_reg <= 1'b0;
            end
            
            if (write_complete) begin
                w_done <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // Write State Machine - FIXED VERSION
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
            debug_last_addr <= 32'h0;
            debug_last_data <= 32'h0;
            debug_write_count <= 32'h0;
        end else begin
            axi_pc_we <= 1'b0;
            axi_instr_we <= 1'b0;
            axi_data_we <= 1'b0;
            write_complete <= 1'b0;
            
            case (write_state)
                WR_IDLE: begin
                    if (aw_done && w_done && !S_AXI_BVALID_reg) begin
                        // DEBUG
                        debug_last_addr <= aw_addr;
                        debug_last_data <= w_data;
                        debug_write_count <= debug_write_count + 1;
                        
                        // Decode address and setup registers + write type
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
                                    // Instruction memory write
                                    axi_instr_addr <= {6'b0, aw_addr[7:2]} - {6'b0, ADDR_INSTR_BASE};
                                    axi_instr_wdata <= w_data;
                                    write_type <= TYPE_INSTR;
                                    write_state <= WR_EXECUTE;
                                end
                                else if (aw_addr[7:2] >= ADDR_DATA_BASE) begin
                                    // Data memory write
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
                    // CRITICAL FIX: Use write_type instead of guessing from data
                    case (write_type)
                        TYPE_PC: begin
                            axi_pc_we <= 1'b1;
                        end
                        TYPE_INSTR: begin
                            axi_instr_we <= 1'b1;
                        end
                        TYPE_DATA: begin
                            axi_data_we <= 1'b1;
                        end
                        default: begin
                            // Do nothing
                        end
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
    // AXI Write Response
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
    
    assign bus_we = 1'b0;
    assign bus_addr = ar_addr;
    assign bus_wdata = 32'h0;
    
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
            ADDR_DEBUG_LAST_ADDR: bus_rdata_reg = debug_last_addr;
            ADDR_DEBUG_LAST_DATA: bus_rdata_reg = debug_last_data;
            ADDR_DEBUG_WRITE_CNT: bus_rdata_reg = debug_write_count;
            ADDR_DEBUG_STATE:     bus_rdata_reg = {27'b0, write_type, write_state};
            default: begin
                if (bus_addr[7:2] >= ADDR_INSTR_BASE && 
                    bus_addr[7:2] < ADDR_DATA_BASE) begin
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
    
    assign S_AXI_AWREADY = S_AXI_AWREADY_reg;
    assign S_AXI_WREADY = S_AXI_WREADY_reg;
    assign S_AXI_BRESP = S_AXI_BRESP_reg;
    assign S_AXI_BVALID = S_AXI_BVALID_reg;
    assign S_AXI_ARREADY = S_AXI_ARREADY_reg;
    assign S_AXI_RDATA = S_AXI_RDATA_reg;
    assign S_AXI_RRESP = S_AXI_RRESP_reg;
    assign S_AXI_RVALID = S_AXI_RVALID_reg;

endmodule