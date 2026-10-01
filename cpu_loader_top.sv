`include "define.sv"

// CPU、串口下载器、两块 32 KiB RAM 和 LED 寄存器的系统顶层。
module cpu_loader_top #(
    parameter integer CLK_FREQ       = 100_000_000,
    parameter integer UART_BPS       = 115200,
    parameter integer CPU_UART_BPS   = 115200,
    parameter integer LOADER_TIMEOUT = 100_000_000
)(
    input  wire                 sys_clk_p,
    input  wire                 sys_clk_n,
    input  wire                 rst_n,
    input  wire                 irq_i,
    input  wire                 uart_rxd,
    output wire                 uart_txd,
    output wire                 pl_led1,
    output wire                 pl_led2,

    // 独立 CPU 打印串口；下载串口仍使用 uart_rxd/uart_txd。
    output wire                 cpu_uart_txd,

    //debug
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

// 板级差分时钟经过输入缓冲后，作为 CPU、RAM 和两路 UART 的内部时钟。
// IBUFDS 是 FPGA 原语，无需单独生成 .xci 文件；频率仍由板上时钟决定。
wire clk;
IBUFDS u_ibufds_sys_clk (
    .I  (sys_clk_p),
    .IB (sys_clk_n),
    .O  (clk)
);

wire loader_cpu_reset; // 低有效：loader 下载时拉低，启动时拉高。
reg  loader_reset_seen_q;
wire cpu_rst_n;

// loader 在 INIT 中会自动释放复位，所以不能直接让 CPU 跟随它启动。
// 初始化完成后，只需记住 loader 是否曾再次拉低复位，无须检测下降沿。
// 下载前导码或 B0/B1 都会拉低复位；此时置位标志，但 CPU 仍保持复位。
// 随后仅当 loader 因 B0 或 B1 清空完成而释放复位时，CPU 才开始运行。
// 标志一直保留到系统复位，后续重新下载直接由 loader_cpu_reset 控制。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        loader_reset_seen_q <= 1'b0;
    else if (loader_init_done_o && !loader_cpu_reset)
        loader_reset_seen_q <= 1'b1;
end

assign cpu_rst_n = rst_n && loader_reset_seen_q && loader_cpu_reset;
assign cpu_running_o = cpu_rst_n;

wire        ldr_req_valid;
wire        ldr_req_ready;
wire [31:0] ldr_req_addr;
wire [31:0] ldr_req_wdata;
wire [3:0]  ldr_req_wstrb;
wire        ldr_rsp_valid;
wire        ldr_rsp_ready;
wire        ldr_rsp_error;

// CPU 侧接口先接内部连线，再与 loader 共用下面的 RAM 接口。
wire imem_req_valid, imem_req_ready, imem_rsp_valid;
wire [31:0] imem_req_addr, imem_rsp_rdata;
wire dmem_req_valid, dmem_req_ready, dmem_req_write, dmem_rsp_valid;
wire [31:0] dmem_req_addr, dmem_req_wdata, dmem_rsp_rdata;
wire [3:0] dmem_req_wstrb;
wire mmio_req_valid, mmio_req_ready, mmio_req_write;
wire mmio_rsp_valid, mmio_rsp_ready;
wire [31:0] mmio_req_addr, mmio_req_wdata, mmio_rsp_rdata;
wire [3:0] mmio_req_wstrb;
wire [7:0] cpu_uart_tx_data;
wire cpu_uart_tx_valid, cpu_uart_tx_ready;
wire ldr_ram_sel; // loader 的目标存储区：0 为 IRAM，1 为 DRAM。

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
    .o_debug_ram_sel  (ldr_ram_sel)
);

// IRAM 请求选择：有 loader 指令写请求时优先，否则接收 CPU 取指。
// cpu_rst_n 为 0 时禁止新的 CPU 请求；RAM 自身的 ready 防止事务重叠。
wire iram_select_loader = ldr_req_valid && !ldr_ram_sel;
wire iram_req_valid = iram_select_loader || (cpu_rst_n && imem_req_valid);
wire iram_req_ready;
// 转成 RAM 内部的字节偏移；当前两个指令基地址都为 0。
wire [31:0] iram_req_addr = iram_select_loader
    ? ldr_req_addr - `DDR_INST_BASE : imem_req_addr - `CPU_INST_BASE;
// CPU 只读 IRAM，只有 loader 能写；读请求会忽略 wdata 和 wstrb，直接连线即可。
wire [31:0] iram_req_wdata = ldr_req_wdata;
wire [3:0] iram_req_wstrb = ldr_req_wstrb;
wire iram_req_write = iram_select_loader;
wire iram_rsp_valid, iram_rsp_ready;
wire [31:0] iram_rsp_rdata;
reg iram_owner_loader_q;

// 请求握手时记录来源：1 为 loader，0 为 CPU。
// RAM 在响应结束前不会接受下一笔请求，所以等待期间归属不会改变。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        iram_owner_loader_q <= 1'b0;
    else if (iram_req_valid && iram_req_ready)
        iram_owner_loader_q <= iram_select_loader;
end

assign imem_req_ready = cpu_rst_n && !iram_select_loader && iram_req_ready;
// loader 的响应等待 ldr_rsp_ready；CPU 响应总是接收。
// 若 CPU 已复位，旧响应仍被 RAM 正常完成，但不再交给 CPU，也不会交给 loader。
assign iram_rsp_ready = iram_owner_loader_q ? ldr_rsp_ready : 1'b1;
assign imem_rsp_valid = cpu_rst_n && !iram_owner_loader_q && iram_rsp_valid;
assign imem_rsp_rdata = iram_rsp_rdata;

iram u_iram (
    // RAM 接系统复位，下载时不能随 CPU 一起复位。
    .clk(clk), .rst_n(rst_n),
    .imem_req_valid(iram_req_valid),
    .imem_req_ready(iram_req_ready),
    .imem_req_addr(iram_req_addr),
    .imem_req_wdata(iram_req_wdata),
    .imem_req_wstrb(iram_req_wstrb),
    .imem_req_write(iram_req_write),
    .imem_rsp_valid(iram_rsp_valid),
    .imem_rsp_ready(iram_rsp_ready),
    .imem_rsp_rdata(iram_rsp_rdata)
);

// DRAM 请求选择：loader 写初始数据，CPU 可读写数据；loader 请求优先。
wire dram_select_loader = ldr_req_valid && ldr_ram_sel;
wire dram_req_valid = dram_select_loader || (cpu_rst_n && dmem_req_valid);
wire dram_req_ready;
// loader 地址减 0x1000_0000，CPU 地址减 0x8000_0000，得到相同的数据区偏移。
wire [31:0] dram_req_addr = dram_select_loader
    ? ldr_req_addr - `DDR_DATA_BASE : dmem_req_addr - `CPU_DATA_BASE;
wire [31:0] dram_req_wdata = dram_select_loader ? ldr_req_wdata : dmem_req_wdata;
wire [3:0] dram_req_wstrb = dram_select_loader ? ldr_req_wstrb : dmem_req_wstrb;
wire dram_req_write = dram_select_loader ? 1'b1 : dmem_req_write;
wire dram_rsp_valid, dram_rsp_ready;
wire [31:0] dram_rsp_rdata;
reg dram_owner_loader_q;

// 只在请求被接受时更新来源，不能用当前 cpu_rst_n 判断旧响应属于谁。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        dram_owner_loader_q <= 1'b0;
    else if (dram_req_valid && dram_req_ready)
        dram_owner_loader_q <= dram_select_loader;
end

assign dmem_req_ready = cpu_rst_n && !dram_select_loader && dram_req_ready;
// 和 IRAM 一样，CPU 复位后仍接收并丢弃属于 CPU 的旧响应，避免堵住 RAM。
assign dram_rsp_ready = dram_owner_loader_q ? ldr_rsp_ready : 1'b1;
assign dmem_rsp_valid = cpu_rst_n && !dram_owner_loader_q && dram_rsp_valid;
assign dmem_rsp_rdata = dram_rsp_rdata;

dram u_dram (
    .clk(clk), .rst_n(rst_n),
    .dmem_req_valid(dram_req_valid),
    .dmem_req_ready(dram_req_ready),
    .dmem_req_addr(dram_req_addr),
    .dmem_req_wdata(dram_req_wdata),
    .dmem_req_wstrb(dram_req_wstrb),
    .dmem_req_write(dram_req_write),
    .dmem_rsp_valid(dram_rsp_valid),
    .dmem_rsp_ready(dram_rsp_ready),
    .dmem_rsp_rdata(dram_rsp_rdata)
);

// 请求 ready 由当前目标 RAM 返回；响应按锁存的来源汇合。
// loader 同时最多有一笔未完成请求，因此两块 RAM 不会同时返回 loader 响应。
assign ldr_req_ready = ldr_ram_sel ? dram_req_ready : iram_req_ready;
assign ldr_rsp_valid = (iram_owner_loader_q && iram_rsp_valid) ||
                       (dram_owner_loader_q && dram_rsp_valid);
// 暂不增加地址范围检查。现有 RAM 没有错误接口，loader 内存错误输入固定为 0。
assign ldr_rsp_error = 1'b0;

wire [1:0] led_en;
// LED 跟随 CPU 复位清零，同时取消重新下载前尚未完成的 MMIO 请求。
led_reg u_led_reg (
    .clk(clk), .rst_n(cpu_rst_n),
    .mmio_req_valid(mmio_req_valid), .mmio_req_ready(mmio_req_ready),
    .mmio_req_addr(mmio_req_addr), .mmio_req_wdata(mmio_req_wdata),
    .mmio_req_wstrb(mmio_req_wstrb), .mmio_req_write(mmio_req_write),
    .mmio_rsp_valid(mmio_rsp_valid), .mmio_rsp_ready(mmio_rsp_ready),
    .mmio_rsp_rdata(mmio_rsp_rdata), .en(led_en)
);

// UART 发送器负责背压，CPU 只有在字节被接收后才完成打印写操作。
// 跟随 CPU 复位，重新下载时停止旧程序打印；下载串口不受影响。
uart_tx #(
    .clk_freq(CLK_FREQ), .uart_bps(CPU_UART_BPS)
) u_cpu_uart_tx (
    .clk(clk), .rst_n(cpu_rst_n), .uart_tx_en(1'b1),
    .uart_tx_data(cpu_uart_tx_data), .uart_tx_valid(cpu_uart_tx_valid),
    .uart_tx_ready(cpu_uart_tx_ready), .uart_txd(cpu_uart_txd)
);

led u_led (
    .en(led_en), .pl_led1(pl_led1), .pl_led2(pl_led2)
);

endmodule
 
