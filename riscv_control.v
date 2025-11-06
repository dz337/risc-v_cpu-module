// riscv_control.v
// CPU control signal decoder
// Decodes control register bits

module riscv_control (
    input  wire [31:0] cpu_ctrl,
    
    output wire        ctrl_run,
    output wire        ctrl_reset,
    output wire        ctrl_step
);

    // CPU control bits
    localparam CTRL_RUN    = 0;
    localparam CTRL_RESET  = 1;
    localparam CTRL_STEP   = 2;
    
    // Extract control signals
    assign ctrl_run   = cpu_ctrl[CTRL_RUN];
    assign ctrl_reset = cpu_ctrl[CTRL_RESET];
    assign ctrl_step  = cpu_ctrl[CTRL_STEP];

endmodule