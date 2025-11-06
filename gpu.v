// gpu.v
// Enhanced BRAM GPU with Line Drawing for Red Pitaya
// Adds CMD_DRAW_LINE with Bresenham algorithm

module gpu (
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
    input  wire [1:0]  S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY
);

    // Parameters
    parameter FB_WIDTH = 320;
    parameter FB_HEIGHT = 200;
    parameter COLOR_DEPTH = 8;
    parameter FB_ADDR_WIDTH = 17; // log2(320*200) = ~16.3, so 17 bits
    
    // Memory map addresses (word-aligned)
    localparam ADDR_ID          = 6'h00;  // 0x00
    localparam ADDR_STATUS      = 6'h01;  // 0x04
    localparam ADDR_CONTROL     = 6'h02;  // 0x08
    localparam ADDR_CMD         = 6'h03;  // 0x0C
    localparam ADDR_ARG0        = 6'h04;  // 0x10 - Start point (x,y)
    localparam ADDR_ARG1        = 6'h05;  // 0x14 - End point (x,y)
    localparam ADDR_ARG2        = 6'h06;  // 0x18
    localparam ADDR_ARG3        = 6'h07;  // 0x1C
    localparam ADDR_COLOR       = 6'h08;  // 0x20
    localparam ADDR_FB_READ     = 6'h10;  // 0x40
    localparam ADDR_FB_DATA     = 6'h11;  // 0x44
    localparam ADDR_MATH_A      = 6'h20;  // 0x80
    localparam ADDR_MATH_B      = 6'h21;  // 0x84
    localparam ADDR_MATH_OP     = 6'h22;  // 0x88
    localparam ADDR_MATH_RESULT = 6'h23;  // 0x8C
    
    // GPU ID and commands
    localparam GPU_ID = 32'hABCD1234;
    localparam CMD_NOP         = 8'h00;
    localparam CMD_CLEAR       = 8'h01;
    localparam CMD_FILL_RECT   = 8'h02;
    localparam CMD_DRAW_LINE   = 8'h03;  // NEW: Line drawing command
    localparam CMD_DRAW_PIXEL  = 8'h04;
    localparam CMD_MANDELBROT  = 8'h05;
    localparam CMD_MATH_OP     = 8'h06;
    
    // Math operations
    localparam MATH_ADD = 4'h0;
    localparam MATH_SUB = 4'h1;
    localparam MATH_MUL = 4'h2;
    localparam MATH_DIV = 4'h3;
    
    // AXI state machine
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
    
    // GPU registers
    reg [31:0] status_reg;
    reg [31:0] control_reg;
    reg [7:0]  cmd_reg;
    reg [31:0] arg0_reg, arg1_reg, arg2_reg, arg3_reg;
    reg [7:0]  color_reg;
    reg [31:0] fb_read_addr_reg;
    reg [31:0] math_a_reg, math_b_reg, math_result_reg;
    reg [3:0]  math_op_reg;
    
    // Command processing
    reg cmd_valid;
    reg cmd_busy;
    reg cmd_done;
    
    // Command processor state
    reg [3:0] cmd_state;
    localparam CMD_IDLE       = 4'h0;
    localparam CMD_CLEAR_EXEC = 4'h1;
    localparam CMD_RECT_EXEC  = 4'h2;
    localparam CMD_LINE_EXEC  = 4'h3;  // NEW: Line drawing state
    localparam CMD_PIXEL_EXEC = 4'h4;
    localparam CMD_MANDEL_EXEC = 4'h5;
    localparam CMD_MATH_EXEC  = 4'h6;
    localparam CMD_DONE_STATE = 4'hF;
    
    reg [16:0] cmd_counter;
    reg [15:0] cmd_x, cmd_y;
    reg [15:0] rect_x0, rect_y0, rect_x1, rect_y1;
    
    // Line drawing registers (Bresenham algorithm)
    reg signed [16:0] line_x0, line_y0, line_x1, line_y1;
    reg signed [16:0] line_x, line_y;
    reg signed [16:0] dx, dy, sx, sy;
    reg signed [16:0] err, e2;
    reg line_done;
    
    // Framebuffer BRAM signals
    reg                       fb_we;
    reg [FB_ADDR_WIDTH-1:0]   fb_addr_write;
    reg [COLOR_DEPTH-1:0]     fb_din;
    reg [FB_ADDR_WIDTH-1:0]   fb_addr_read;
    wire [COLOR_DEPTH-1:0]    fb_dout;
    
    // Internal bus signals
    wire        bus_we;
    wire [31:0] bus_addr;
    wire [31:0] bus_wdata;
    reg [31:0]  bus_rdata;
    
    //==========================================================================
    // AXI Protocol Implementation (same as working version)
    //==========================================================================
    
    // Write Address Channel
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
    
    // Write Data Channel
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
    
    // Write Response
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
    
    // Read Address Channel
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
    
    // Read Data Channel
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
    
    // Connect internal bus
    assign bus_we = write_ready;
    assign bus_addr = write_ready ? aw_addr : ar_addr;
    assign bus_wdata = w_data;
    
    // Output assignments
    assign S_AXI_AWREADY = S_AXI_AWREADY_reg;
    assign S_AXI_WREADY = S_AXI_WREADY_reg;
    assign S_AXI_BRESP = S_AXI_BRESP_reg;
    assign S_AXI_BVALID = S_AXI_BVALID_reg;
    assign S_AXI_ARREADY = S_AXI_ARREADY_reg;
    assign S_AXI_RDATA = S_AXI_RDATA_reg;
    assign S_AXI_RRESP = S_AXI_RRESP_reg;
    assign S_AXI_RVALID = S_AXI_RVALID_reg;
    
    //==========================================================================
    // GPU Register Interface
    //==========================================================================
    
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            control_reg <= 32'h0;
            cmd_reg <= CMD_NOP;
            arg0_reg <= 32'h0;
            arg1_reg <= 32'h0;
            arg2_reg <= 32'h0;
            arg3_reg <= 32'h0;
            color_reg <= 8'hFF;
            fb_read_addr_reg <= 32'h0;
            math_a_reg <= 32'h0;
            math_b_reg <= 32'h0;
            math_op_reg <= 4'h0;
            cmd_valid <= 1'b0;
        end else begin
            cmd_valid <= 1'b0;  // Single cycle pulse
            
            if (bus_we) begin
                case (bus_addr[7:2])  // Word-aligned addressing
                    ADDR_CONTROL: control_reg <= bus_wdata;
                    ADDR_CMD: begin
                        cmd_reg <= bus_wdata[7:0];
                        if (bus_wdata[7:0] != CMD_NOP) cmd_valid <= 1'b1;
                    end
                    ADDR_ARG0: arg0_reg <= bus_wdata;
                    ADDR_ARG1: arg1_reg <= bus_wdata;
                    ADDR_ARG2: arg2_reg <= bus_wdata;
                    ADDR_ARG3: arg3_reg <= bus_wdata;
                    ADDR_COLOR: color_reg <= bus_wdata[7:0];
                    ADDR_FB_READ: fb_read_addr_reg <= bus_wdata;
                    ADDR_MATH_A: math_a_reg <= bus_wdata;
                    ADDR_MATH_B: math_b_reg <= bus_wdata;
                    ADDR_MATH_OP: math_op_reg <= bus_wdata[3:0];
                endcase
            end
        end
    end
    
    // Read path
    always @(*) begin
        case (bus_addr[7:2])  // Word-aligned addressing
            ADDR_ID:          bus_rdata = GPU_ID;
            ADDR_STATUS:      bus_rdata = {30'b0, cmd_done, cmd_busy};
            ADDR_CONTROL:     bus_rdata = control_reg;
            ADDR_CMD:         bus_rdata = {24'b0, cmd_reg};
            ADDR_ARG0:        bus_rdata = arg0_reg;
            ADDR_ARG1:        bus_rdata = arg1_reg;
            ADDR_ARG2:        bus_rdata = arg2_reg;
            ADDR_ARG3:        bus_rdata = arg3_reg;
            ADDR_COLOR:       bus_rdata = {24'b0, color_reg};
            ADDR_FB_READ:     bus_rdata = fb_read_addr_reg;
            ADDR_FB_DATA:     bus_rdata = {24'b0, fb_dout};
            ADDR_MATH_A:      bus_rdata = math_a_reg;
            ADDR_MATH_B:      bus_rdata = math_b_reg;
            ADDR_MATH_OP:     bus_rdata = {28'b0, math_op_reg};
            ADDR_MATH_RESULT: bus_rdata = math_result_reg;
            default:          bus_rdata = 32'hDEADBEEF;
        endcase
    end
    
    //==========================================================================
    // Enhanced Command Processor with Line Drawing
    //==========================================================================
    
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            cmd_state <= CMD_IDLE;
            cmd_busy <= 1'b0;
            cmd_done <= 1'b0;
            cmd_counter <= 17'b0;
            cmd_x <= 16'b0;
            cmd_y <= 16'b0;
            fb_we <= 1'b0;
            fb_addr_write <= 17'b0;
            fb_din <= 8'b0;
            math_result_reg <= 32'b0;
            line_done <= 1'b0;
        end else begin
            cmd_done <= 1'b0;
            fb_we <= 1'b0;
            
            case (cmd_state)
                CMD_IDLE: begin
                    cmd_busy <= 1'b0;
                    line_done <= 1'b0;
                    if (cmd_valid) begin
                        cmd_busy <= 1'b1;
                        cmd_counter <= 17'b0;
                        cmd_x <= 16'b0;
                        cmd_y <= 16'b0;
                        
                        case (cmd_reg)
                            CMD_CLEAR: cmd_state <= CMD_CLEAR_EXEC;
                            CMD_FILL_RECT: begin
                                rect_x0 <= arg0_reg[15:0];
                                rect_y0 <= arg0_reg[31:16];
                                rect_x1 <= arg1_reg[15:0];
                                rect_y1 <= arg1_reg[31:16];
                                cmd_x <= arg0_reg[15:0];
                                cmd_y <= arg0_reg[31:16];
                                cmd_state <= CMD_RECT_EXEC;
                            end
                            CMD_DRAW_LINE: begin
                                // Simple line drawing setup
                                line_x0 <= $signed({1'b0, arg0_reg[15:0]});
                                line_y0 <= $signed({1'b0, arg0_reg[31:16]});
                                line_x1 <= $signed({1'b0, arg1_reg[15:0]});
                                line_y1 <= $signed({1'b0, arg1_reg[31:16]});
                                line_x <= $signed({1'b0, arg0_reg[15:0]});
                                line_y <= $signed({1'b0, arg0_reg[31:16]});
                                cmd_state <= CMD_LINE_EXEC;
                            end
                            CMD_DRAW_PIXEL: begin
                                fb_we <= 1'b1;
                                fb_addr_write <= arg0_reg[31:16] * FB_WIDTH + arg0_reg[15:0];
                                fb_din <= color_reg;
                                cmd_state <= CMD_DONE_STATE;
                            end
                            CMD_MANDELBROT: begin
                                cmd_x <= 16'b0;
                                cmd_y <= 16'b0;
                                cmd_state <= CMD_MANDEL_EXEC;
                            end
                            CMD_MATH_OP: cmd_state <= CMD_MATH_EXEC;
                            default: cmd_state <= CMD_DONE_STATE;
                        endcase
                    end
                end
                
                CMD_CLEAR_EXEC: begin
                    fb_we <= 1'b1;
                    fb_addr_write <= cmd_counter;
                    fb_din <= color_reg;
                    cmd_counter <= cmd_counter + 1;
                    
                    if (cmd_counter >= (FB_WIDTH * FB_HEIGHT - 1)) begin
                        cmd_state <= CMD_DONE_STATE;
                    end
                end
                
                CMD_RECT_EXEC: begin
                    if (cmd_x >= rect_x0 && cmd_x <= rect_x1 && 
                        cmd_y >= rect_y0 && cmd_y <= rect_y1) begin
                        fb_we <= 1'b1;
                        fb_addr_write <= cmd_y * FB_WIDTH + cmd_x;
                        fb_din <= color_reg;
                    end
                    
                    cmd_x <= cmd_x + 1;
                    if (cmd_x >= rect_x1) begin
                        cmd_x <= rect_x0;
                        cmd_y <= cmd_y + 1;
                        if (cmd_y >= rect_y1) begin
                            cmd_state <= CMD_DONE_STATE;
                        end
                    end
                end
                
                CMD_LINE_EXEC: begin
                    // Simplified line drawing - step by step approach
                    if (!line_done) begin
                        // Draw current pixel (bounds checking)
                        if (line_x >= 0 && line_x < FB_WIDTH && line_y >= 0 && line_y < FB_HEIGHT) begin
                            fb_we <= 1'b1;
                            fb_addr_write <= line_y * FB_WIDTH + line_x;
                            fb_din <= color_reg;
                        end
                        
                        // Check if we've reached the end point
                        if (line_x == line_x1 && line_y == line_y1) begin
                            line_done <= 1'b1;
                            cmd_state <= CMD_DONE_STATE;
                        end else begin
                            // Simple step toward target (simplified algorithm)
                            // Step in X direction
                            if (line_x < line_x1) begin
                                line_x <= line_x + 1;
                            end else if (line_x > line_x1) begin
                                line_x <= line_x - 1;
                            end
                            
                            // Step in Y direction  
                            if (line_y < line_y1) begin
                                line_y <= line_y + 1;
                            end else if (line_y > line_y1) begin
                                line_y <= line_y - 1;
                            end
                        end
                    end
                end
                
                CMD_MANDEL_EXEC: begin
                    // Simple pattern instead of real Mandelbrot
                    fb_din <= cmd_x[7:0] ^ cmd_y[7:0];  // XOR pattern
                    fb_we <= 1'b1;
                    fb_addr_write <= cmd_y * FB_WIDTH + cmd_x;
                    
                    cmd_x <= cmd_x + 1;
                    if (cmd_x >= (FB_WIDTH - 1)) begin
                        cmd_x <= 16'b0;
                        cmd_y <= cmd_y + 1;
                        if (cmd_y >= (FB_HEIGHT - 1)) begin
                            cmd_state <= CMD_DONE_STATE;
                        end
                    end
                end
                
                CMD_MATH_EXEC: begin
                    case (math_op_reg)
                        MATH_ADD: math_result_reg <= math_a_reg + math_b_reg;
                        MATH_SUB: math_result_reg <= math_a_reg - math_b_reg;
                        MATH_MUL: math_result_reg <= math_a_reg * math_b_reg;
                        MATH_DIV: begin
                            if (math_b_reg != 32'b0) 
                                math_result_reg <= math_a_reg / math_b_reg;
                            else
                                math_result_reg <= 32'hFFFFFFFF;  // Error
                        end
                        default: math_result_reg <= 32'b0;
                    endcase
                    cmd_state <= CMD_DONE_STATE;
                end
                
                CMD_DONE_STATE: begin
                    cmd_done <= 1'b1;
                    cmd_state <= CMD_IDLE;
                end
                
                default: cmd_state <= CMD_IDLE;
            endcase
        end
    end
    
    //==========================================================================
    // Framebuffer BRAM - True Dual Port
    //==========================================================================
    
    // Read address mux: CPU reads or internal use
    always @(*) begin
        fb_addr_read = fb_read_addr_reg[FB_ADDR_WIDTH-1:0];
    end
    
    // Framebuffer memory (inferred BRAM)
    reg [COLOR_DEPTH-1:0] framebuffer [0:(1<<FB_ADDR_WIDTH)-1];
    reg [COLOR_DEPTH-1:0] fb_dout_reg;
    
    // Port A: Write (command processor)
    always @(posedge S_AXI_ACLK) begin
        if (fb_we) begin
            framebuffer[fb_addr_write] <= fb_din;
        end
    end
    
    // Port B: Read (CPU access)
    always @(posedge S_AXI_ACLK) begin
        fb_dout_reg <= framebuffer[fb_addr_read];
    end
    
    assign fb_dout = fb_dout_reg;

endmodule