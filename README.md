# 五级流水线 CPU 核

`cpu_top.sv` 例化 IF、IF/ID、ID、ID/EX、EX、EX/MEM、MEM、MEM/WB、WB 及暂停/冲刷流水线控制。`cpu_loader_top.sv` 在此基础上例化串口 loader，将取指、访存和下载写入汇到一个对外的 DDR 原生握手接口。本目录包含 loader 和上位机下载脚本；不包含 Cache、DDR 控制器、AXI 或板级 IP。`rtl.f` 列出了全部 RTL；编译时将本目录加入 Verilog include path，以便找到 `define.sv`。

复位为低有效 `rst_n`，时钟上升沿采样。复位后取指 PC 从 `0x0000_0000` 开始，因此解除复位前应准备好指令存储器内容。`irq_i` 是高电平有效的外部机器中断输入；不使用时接 `1'b0`。

## `cpu_loader_top` 外部接口

这是带下载功能的推荐顶层。以下方向均相对于顶层，未注明的信号为 1 位。

| 接口 | 信号和方向 | 说明 |
| --- | --- | --- |
| 时钟/复位/中断 | `clk` 输入，`rst_n` 输入，`irq_i` 输入 | `rst_n=0` 复位；未用中断时接 0。顶层参数 `CLK_FREQ`、`UART_BPS`、`LOADER_TIMEOUT` 默认分别为 100 MHz、115200、100000000 个时钟周期。 |
| 下载串口 | `uart_rxd` 输入，`uart_txd` 输出 | 接上位机 `peqflash.py` 的 UART，8N1。 |
| DDR 请求 | `ddr_req_valid` 输出，`ddr_req_ready` 输入，`ddr_req_addr[31:0]` 输出，`ddr_req_write` 输出，`ddr_req_wdata[31:0]` 输出，`ddr_req_wstrb[3:0]` 输出 | 单个 32 位原生读写口。`valid && ready` 时接受请求；读时 `write=0`、`wstrb=0`。地址为字节地址，按 4 字节对齐。 |
| DDR 应答 | `ddr_rsp_valid` 输入，`ddr_rsp_ready` 输出，`ddr_rsp_rdata[31:0]` 输入，`ddr_rsp_error` 输入 | 每个读写请求都返回一次应答。最早在请求握手后的下一周期拉高 `valid`，保持到 `valid && ready`；写应答的数据可置 0。下载写入错误会反馈给 loader。 |
| MMIO 请求 | `mmio_req_valid` 输出，`mmio_req_ready` 输入，`mmio_req_addr[31:0]`、`mmio_req_wdata[31:0]`、`mmio_req_wstrb[3:0]`、`mmio_req_write` 输出 | CPU 对 `0x4000_0000`～`0x4000_FFFF` 的访问，UART 输出地址除外。 |
| MMIO 应答 | `mmio_rsp_valid` 输入，`mmio_rsp_ready` 输出，`mmio_rsp_rdata[31:0]` 输入 | 与下方纯 CPU 顶层的 MMIO 应答规则相同。 |
| CPU UART 字节流 | `cpu_uart_tx_data[7:0]`、`cpu_uart_tx_valid` 输出，`cpu_uart_tx_ready` 输入 | CPU 向 `0x4000_0000` 写入时输出字节；这是与下载串口独立的接口。未使用时可将 `ready` 接 1。 |
| loader 状态 | `loader_init_done_o`、`loader_busy_o`、`loader_pgm_done_o`、`loader_error_o`、`cpu_running_o` 输出，`loader_error_code_o[4:0]` 输出 | 可用于 LED、波形或上层状态监控。 |
| CPU 写回调试 | `wb_we_o`、`wb_waddr_o[4:0]`、`wb_wdata_o[31:0]` 输出 | 观察通用寄存器写回。 |

仲裁器同时最多允许一个 DDR 请求在途，优先级为 loader、CPU 数据、CPU 取指。取指从物理 `0x0000_0000` 开始，loader 指令写入使用相同地址；CPU 数据地址 `0x8000_0000` 起映射到外部物理 `0x1000_0000` 起，loader 数据写入也使用后者。32 位字内的 byte/halfword 写入由 `ddr_req_wstrb` 选择字节槽。DDR 控制器和实际存储器需要在顶层外连接。

上电后 `cpu_running_o=0`，CPU 保持复位；loader 收到启动命令 `B0`（或清指令存储器命令 `B1`）后才释放 CPU。下载期间 CPU 重新进入复位。DDR 握手口在 loader 下载期间仍须工作。

## `cpu_top` 外部接口

以下方向均相对于 CPU，未注明的单比特信号宽度均为 1 位。

| 接口 | 信号和方向 | 说明 |
| --- | --- | --- |
| 时钟/复位/中断 | `clk` 输入，`rst_n` 输入，`irq_i` 输入 | `rst_n=0` 复位；`irq_i` 为电平中断。 |
| 取指请求 | `imem_req_valid` 输出，`imem_req_ready` 输入，`imem_req_addr[31:0]` 输出 | `valid && ready` 在时钟上升沿接受一个取指请求，地址为字节地址。 |
| 取指应答 | `imem_rsp_valid` 输入，`imem_rsp_rdata[31:0]` 输入 | 每个已接受请求返回一次 32 位指令；应答最早在请求握手后的下一个周期给出。 |
| 数据请求 | `dmem_req_valid` 输出，`dmem_req_ready` 输入，`dmem_req_addr[31:0]` 输出，`dmem_req_write` 输出，`dmem_req_wdata[31:0]` 输出，`dmem_req_wstrb[3:0]` 输出 | `write=1` 为写。地址为字节地址，数据和写使能按 32 位字的小端字节槽排列；读时写使能为 0。 |
| 数据应答 | `dmem_rsp_valid` 输入，`dmem_rsp_rdata[31:0]` 输入 | 读写请求都必须应答一次；写应答时数据可置 0。读数据应是包含请求地址的对齐 32 位字。应答最早在请求握手后的下一个周期给出。 |
| MMIO 请求 | `mmio_req_valid` 输出，`mmio_req_ready` 输入，`mmio_req_addr[31:0]` 输出，`mmio_req_write` 输出，`mmio_req_wdata[31:0]` 输出，`mmio_req_wstrb[3:0]` 输出 | 用于 `0x4000_0000`～`0x4000_FFFF` 区间，UART 发送地址除外。请求握手规则与数据存储器相同。 |
| MMIO 应答 | `mmio_rsp_valid` 输入，`mmio_rsp_ready` 输出，`mmio_rsp_rdata[31:0]` 输入 | 已接受的读写请求都须应答；应答最早在请求握手后的下一个周期给出，并保持 `valid` 直至 `valid && ready` 完成握手。读数据按 32 位对齐字提供。 |
| UART 字节流 | `uart_tx_valid` 输出，`uart_tx_ready` 输入，`uart_tx_data[7:0]` 输出 | CPU 向 `0x4000_0000` 写时发送写入数据的低 8 位；`valid && ready` 接受一个字节。CPU 内部在下一周期完成该写事务。 |
| 调试：中断/跳转 | `trap_enter_o`、`irq_request_o`、`redirect_o` 输出；`trap_pc_o[31:0]`、`mtvec_o[31:0]`、`mepc_o[31:0]`、`redirect_pc_o[31:0]` 输出 | 观察中断接受、CSR 地址和 PC 跳转。 |
| 调试：流水线 | `stall_o[5:0]`、`flush_if_id_o`、`flush_id_ex_o`、`flush_ex_mem_o`、`flush_mem_wb_o`、`ex_valid_o` 输出；`ex_pc_o[31:0]` 输出 | 观察暂停、冲刷和 EX 阶段。 |
| 调试：写回 | `wb_we_o` 输出，`wb_waddr_o[4:0]` 输出，`wb_wdata_o[31:0]` 输出 | 观察通用寄存器写回。 |

每个取指和数据端口同时最多保留一个未完成请求。请求端在握手前保持 `valid`、地址和写数据稳定；存储器在接受请求后返回一次应答，不应提前或重复应答。若不使用 MMIO，程序也不应访问该区间，否则 CPU 会一直等待应答。`uart_tx_ready` 不使用时可以接 `1'b1`。

常规数据地址由程序产生，本核不作片选地址转换；源工程程序通常把数据区放在 `0x8000_0000` 起始。`0x4000_0000` 为 UART 输出地址，`0x4000_0000`～`0x4000_FFFF` 的其余地址走 MMIO，其他 load/store 走数据端口。

## 加入仿真/综合工程

使用 Icarus Verilog 时，在本目录执行：

```sh
iverilog -g2012 -s cpu_loader_top -I . -o cpu_loader_top.vvp -c rtl.f
```

在 Vivado 等工具中，将 `rtl.f` 的 27 个 `.sv` 文件加入工程，设 `cpu_loader_top` 为顶层，并把本目录设为 include directory。`define.sv` 是头文件，不需单独作为设计模块例化。若只使用 CPU 核，可改用 `cpu_top` 为顶层。

可运行 `python check_rtl.py` 核对文件清单、模块依赖和命名端口连接。

## 串口下载

`peqflash.py` 是与 RTL loader 协议配套的上位机脚本，依赖 Python 的 `pyserial`。它接收带头部的 `.bin` 镜像；若手头是普通 RISC-V 小端原始指令和数据文件，先运行：

```sh
python pack_flash.py --imem program_iram.bin --dmem program_dram.bin --out-dir images
```

脚本按每 4 字节逆序打包正文，并生成 `C0 C0 C0 C0`/`D0 D0 D0 D0` 前导码、4 字节大端长度、4 字节大端存储区偏移、正文及 `E0 E0 E0 E0` 结束码。原始文件长度及偏移需 4 字节对齐，单个存储区最大 128 KiB。若程序需要从非零偏移装入，可使用 `--imem-offset 0x...` 或 `--dmem-offset 0x...`；偏移均相对于各自存储区起始地址。

```sh
python peqflash.py -serport COM3 -baud 115200 -imembin images/imem.flash.bin -dmembin images/dmem.flash.bin
```

`peqflash.py` 会检查设备签名，依次下载指令和数据，再发送 `B0` 启动 CPU。`-cleanimem` 会在下载前用 NOP 清空整个指令区；`-rebootonly` 只发送启动命令。上位机波特率要与顶层的 `UART_BPS` 参数一致。

下面示例展示功能端口的连接形式；调试输出可按需单独连接或悬空：

```systemverilog
cpu_top u_cpu (
    .clk(clk), .rst_n(rst_n), .irq_i(1'b0),
    .imem_req_valid(imem_req_valid), .imem_req_ready(imem_req_ready),
    .imem_req_addr(imem_req_addr), .imem_rsp_valid(imem_rsp_valid),
    .imem_rsp_rdata(imem_rsp_rdata),
    .dmem_req_valid(dmem_req_valid), .dmem_req_ready(dmem_req_ready),
    .dmem_req_addr(dmem_req_addr), .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_wstrb(dmem_req_wstrb), .dmem_req_write(dmem_req_write),
    .dmem_rsp_valid(dmem_rsp_valid), .dmem_rsp_rdata(dmem_rsp_rdata),
    .mmio_req_valid(mmio_req_valid), .mmio_req_ready(mmio_req_ready),
    .mmio_req_addr(mmio_req_addr), .mmio_req_wdata(mmio_req_wdata),
    .mmio_req_wstrb(mmio_req_wstrb), .mmio_req_write(mmio_req_write),
    .mmio_rsp_valid(mmio_rsp_valid), .mmio_rsp_ready(mmio_rsp_ready),
    .mmio_rsp_rdata(mmio_rsp_rdata),
    .uart_tx_valid(uart_tx_valid), .uart_tx_ready(uart_tx_ready),
    .uart_tx_data(uart_tx_data)
);
```
