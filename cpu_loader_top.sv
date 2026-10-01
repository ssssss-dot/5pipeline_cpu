`include "define.sv"

// CPU + UART program loader. One native memory port is exported for a future
// DDR controller; this module does not instantiate a controller or a cache.
module cpu_loader_top #(
    parameter integer CLK_FREQ       = 100_000_000,
    parameter integer UART_BPS       = 115200,
    parameter integer LOADER_TIMEOUT = 100_000_000
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 irq_i,
    input  wire                 uart_rxd,
    output wire                 uart_txd,

    output wire                 ddr_req_valid,
    input  wire                 ddr_req_ready,
    output reg  [31:0]          ddr_req_addr,
    output reg  [31:0]          ddr_req_wdata,
    output reg  [3:0]           ddr_req_wstrb,
    output reg                  ddr_req_write,
    input  wire                 ddr_rsp_valid,
    output wire                 ddr_rsp_ready,
    input  wire [31:0]          ddr_rsp_rdata,
    input  wire                 ddr_rsp_error,

    output wire                 mmio_req_valid,
    input  wire                 mmio_req_ready,
    output wire [31:0]          mmio_req_addr,
    output wire [31:0]          mmio_req_wdata,
    output wire [3:0]           mmio_req_wstrb,
    output wire                 mmio_req_write,
    input  wire                 mmio_rsp_valid,
    output wire                 mmio_rsp_ready,
    input  wire [31:0]          mmio_rsp_rdata,

    output wire [7:0]           cpu_uart_tx_data,
    output wire                 cpu_uart_tx_valid,
    input  wire                 cpu_uart_tx_ready,

    output wire                 loader_init_done_o,
    output wire                 loader_busy_o,
    output wire                 loader_pgm_done_o,
    output wire                 loader_error_o,
    output wire [4:0]           loader_error_code_o,
    output wire                 cpu_running_o,
    output wire                 wb_we_o,
    output wire [4:0]           wb_waddr_o,
    output wire [31:0]          wb_wdata_o
);

localparam [1:0] IDLE = 2'd0, SEND = 2'd1, WAIT_RSP = 2'd2;
localparam [1:0] INST = 2'd0, DATA = 2'd1, LOADER = 2'd2;

wire loader_cpu_reset;
reg  loader_reset_prev_q;
reg  boot_command_seen_q;
wire cpu_rst_n;

// The original loader releases reset during its INIT state. Hold the CPU in
// reset until a later B0/B1 command has first asserted loader_cpu_reset low.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        loader_reset_prev_q <= 1'b0;
        boot_command_seen_q <= 1'b0;
    end else begin
        loader_reset_prev_q <= loader_cpu_reset;
        if (loader_init_done_o && loader_reset_prev_q && !loader_cpu_reset)
            boot_command_seen_q <= 1'b1;
    end
end

assign cpu_rst_n    = rst_n && boot_command_seen_q && loader_cpu_reset;
assign cpu_running_o = cpu_rst_n;

wire        imem_req_valid;
wire        imem_req_ready;
wire [31:0] imem_req_addr;
wire        imem_rsp_valid;
wire [31:0] imem_rsp_rdata;

wire        dmem_req_valid;
wire        dmem_req_ready;
wire [31:0] dmem_req_addr;
wire [31:0] dmem_req_wdata;
wire [3:0]  dmem_req_wstrb;
wire        dmem_req_write;
wire        dmem_rsp_valid;
wire [31:0] dmem_rsp_rdata;

wire        ldr_req_valid;
wire        ldr_req_ready;
wire [31:0] ldr_req_addr;
wire [31:0] ldr_req_wdata;
wire [3:0]  ldr_req_wstrb;
wire        ldr_rsp_valid;
wire        ldr_rsp_ready;
wire        ldr_rsp_error;

cpu_top u_cpu (
    .clk                (clk),
    .rst_n              (cpu_rst_n),
    .irq_i              (irq_i),
    .imem_req_valid     (imem_req_valid),
    .imem_req_ready     (imem_req_ready),
    .imem_req_addr      (imem_req_addr),
    .imem_rsp_valid     (imem_rsp_valid),
    .imem_rsp_rdata     (imem_rsp_rdata),
    .dmem_req_valid     (dmem_req_valid),
    .dmem_req_ready     (dmem_req_ready),
    .dmem_req_addr      (dmem_req_addr),
    .dmem_req_wdata     (dmem_req_wdata),
    .dmem_req_wstrb     (dmem_req_wstrb),
    .dmem_req_write     (dmem_req_write),
    .dmem_rsp_valid     (dmem_rsp_valid),
    .dmem_rsp_rdata     (dmem_rsp_rdata),
    .mmio_req_valid     (mmio_req_valid),
    .mmio_req_ready     (mmio_req_ready),
    .mmio_req_addr      (mmio_req_addr),
    .mmio_req_wdata     (mmio_req_wdata),
    .mmio_req_wstrb     (mmio_req_wstrb),
    .mmio_req_write     (mmio_req_write),
    .mmio_rsp_valid     (mmio_rsp_valid),
    .mmio_rsp_ready     (mmio_rsp_ready),
    .mmio_rsp_rdata     (mmio_rsp_rdata),
    .uart_tx_data       (cpu_uart_tx_data),
    .uart_tx_valid      (cpu_uart_tx_valid),
    .uart_tx_ready      (cpu_uart_tx_ready),
    .trap_enter_o       (),
    .trap_pc_o          (),
    .mtvec_o            (),
    .mepc_o             (),
    .irq_request_o      (),
    .redirect_o         (),
    .redirect_pc_o      (),
    .stall_o            (),
    .flush_if_id_o      (),
    .flush_id_ex_o      (),
    .flush_ex_mem_o     (),
    .flush_mem_wb_o     (),
    .wb_we_o            (wb_we_o),
    .wb_waddr_o         (wb_waddr_o),
    .wb_wdata_o         (wb_wdata_o),
    .ex_pc_o            (),
    .ex_valid_o         ()
);

loader #(
    .clk_freq (CLK_FREQ),
    .uart_bps (UART_BPS),
    .TIMEOUT  (LOADER_TIMEOUT)
) u_loader (
    .clk              (clk),
    .rst_n            (rst_n),
    .i_halt_cpu       (1'b0),
    .o_ldr_cpu_stall  (),
    .o_ldr_cpu_reset  (loader_cpu_reset),
    .o_init_done      (loader_init_done_o),
    .o_busy           (loader_busy_o),
    .o_pgm_done       (loader_pgm_done_o),
    .o_err            (loader_error_o),
    .o_err_code       (loader_error_code_o),
    .i_uart_rx        (uart_rxd),
    .o_uart_tx        (uart_txd),
    .ldr_req_valid    (ldr_req_valid),
    .ldr_req_ready    (ldr_req_ready),
    .ldr_req_addr     (ldr_req_addr),
    .ldr_req_wdata    (ldr_req_wdata),
    .ldr_req_wstrb    (ldr_req_wstrb),
    .ldr_rsp_valid    (ldr_rsp_valid),
    .ldr_rsp_ready    (ldr_rsp_ready),
    .ldr_rsp_error    (ldr_rsp_error),
    .o_debug_ram_sel  ()
);

reg [1:0] state_q;
reg [1:0] owner_q;
wire selected_valid = owner_q == LOADER ? ldr_req_valid :
                      owner_q == DATA   ? dmem_req_valid : imem_req_valid;

// Latch the winning master before asserting DDR valid, so the selected
// transaction stays stable while DDR is not ready. An unaccepted IF request
// may be canceled on redirect by inst_ram; SEND then returns to IDLE.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IDLE;
        owner_q <= INST;
    end else begin
        case (state_q)
            IDLE: begin
                if (ldr_req_valid) begin
                    owner_q <= LOADER;
                    state_q <= SEND;
                end else if (dmem_req_valid) begin
                    owner_q <= DATA;
                    state_q <= SEND;
                end else if (imem_req_valid) begin
                    owner_q <= INST;
                    state_q <= SEND;
                end
            end
            SEND: begin
                if (!selected_valid)
                    state_q <= IDLE;
                else if (ddr_req_ready)
                    state_q <= WAIT_RSP;
            end
            WAIT_RSP: begin
                if (ddr_rsp_valid && ddr_rsp_ready)
                    state_q <= IDLE;
            end
            default: state_q <= IDLE;
        endcase
    end
end

assign ddr_req_valid = (state_q == SEND) && selected_valid;
assign ldr_req_ready = (state_q == SEND) && (owner_q == LOADER) && ddr_req_ready;
assign dmem_req_ready = (state_q == SEND) && (owner_q == DATA) && ddr_req_ready;
assign imem_req_ready = (state_q == SEND) && (owner_q == INST) && ddr_req_ready;

always @(*) begin
    ddr_req_addr  = 32'b0;
    ddr_req_wdata = 32'b0;
    ddr_req_wstrb = 4'b0;
    ddr_req_write = 1'b0;
    case (owner_q)
        LOADER: begin
            ddr_req_addr  = ldr_req_addr;
            ddr_req_wdata = ldr_req_wdata;
            ddr_req_wstrb = ldr_req_wstrb;
            ddr_req_write = 1'b1;
        end
        DATA: begin
            ddr_req_addr  = `DDR_DATA_BASE + {dmem_req_addr[31:2], 2'b00} - `CPU_DATA_BASE;
            ddr_req_wdata = dmem_req_wdata;
            ddr_req_wstrb = dmem_req_wstrb;
            ddr_req_write = dmem_req_write;
        end
        default: begin
            ddr_req_addr  = `DDR_INST_BASE + imem_req_addr - `CPU_INST_BASE;
        end
    endcase
end

assign ddr_rsp_ready = (state_q == WAIT_RSP) &&
                       ((owner_q == LOADER) ? ldr_rsp_ready : 1'b1);
wire response_fire = ddr_rsp_valid && ddr_rsp_ready;
assign ldr_rsp_valid  = response_fire && (owner_q == LOADER);
assign ldr_rsp_error  = ddr_rsp_error;
assign dmem_rsp_valid = response_fire && (owner_q == DATA);
assign dmem_rsp_rdata = ddr_rsp_rdata;
assign imem_rsp_valid = response_fire && (owner_q == INST);
assign imem_rsp_rdata = ddr_rsp_rdata;

endmodule
