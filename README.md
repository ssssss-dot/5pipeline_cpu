# 五级流水线 CPU：串口下载、片上 RAM、LED 与独立串口打印

本工程以 `cpu_loader_top.sv` 为系统顶层，内部连接五级流水线 CPU、UART loader、两块各 32 KiB 的 RAM、LED 寄存器和独立的 CPU UART 发送器。程序由下载串口写入 RAM，CPU 从地址 0 开始取指，通过访存指令控制 LED、输出字符。

当前系统使用片上 RAM，不需要外接 DDR、Cache、AXI 总线或 MIG。代码中 `DDR_INST_BASE`、`DDR_DATA_BASE` 是沿用的 loader 地址宏名称，实际连接的是 `iram.sv` 和 `dram.sv`。此处 DRAM 指数据 RAM，不是外部动态存储器。

## 1. 目录与模块职责

所有命令均在本 README 所在目录执行。

```text
cpu_loader_top.sv       系统顶层：例化模块、复位、内存请求选择与响应返回
cpu.tcl                 Vivado 建工程、综合、实现和生成 bitstream 的脚本
cpu.xdc                 板级时钟与引脚约束（尚需补齐 LED 等端口）
core/
├── cpu_top.sv          五级流水线 CPU 核
├── if/、id/、ex_stage/  取指、译码、执行模块
├── mem_stage/、wb_stage/ 访存与写回模块
├── Ctrl.sv            流水线暂停、冲刷控制
├── if_id.sv 等         流水线级间寄存器
├── iram.sv、dram.sv    两块各 32 KiB RAM
├── led_reg.sv、led.sv  LED MMIO 寄存器与输出
└── define.sv          数据宽度、地址和容量等宏定义
loader/                下载状态机、UART 收发和同步模块
rtl.f                  RTL 文件列表，包含 core/ 和 loader/ 相对路径
software/
└── led_uart.c         唯一的测试源文件：LED 和串口打印裸机 C 程序
platform/
├── start.S            裸机启动代码：设置栈、清 BSS、调用 main
└── link.ld            IRAM/DRAM 段布局和栈空间约束
python_tools/
└── peqflash.py         下载、启动、独立打印串口监视
bin2pqr5bin.py          原版重排工具，固定生成 C0 帧头；数据帧头单独处理
README.md              架构、裸机程序、Linux LLVM 构建和下载说明
LICENSE                许可证
.gitignore             忽略软件构建结果与 Python 缓存
```

`software/` 只保留 [led_uart.c](software/led_uart.c)。启动代码与链接脚本位于 `platform/`。当前目录没有 Makefile，按第 6 节的 Linux 命令直接调用 LLVM；执行后才会创建 `build/led_uart/`，生成结果不写回 `software/`。

两个 Python 脚本保留原版。`bin2pqr5bin.py` 负责重排；`peqflash.py` 仍依赖当前缺失的 `pack_flash.py`，下载前需要补齐该依赖，详见第 7 节。

## 2. 当前硬件架构

```text
下载串口 RX/TX ↔ loader ──写请求─────┬─→ IRAM 请求选择 → IRAM
                                  └─→ DRAM 请求选择 → DRAM
CPU 取指请求 ─────────────────────────→ IRAM 请求选择
CPU 数据请求 ─────────────────────────→ DRAM 请求选择

CPU MMIO 请求 → led_reg → led → pl_led1 / pl_led2
CPU 打印字节  → 独立 uart_tx  → cpu_uart_txd

每块 RAM 的响应根据请求接受时记录的来源，返回 CPU 或 loader。
```

### 顶层与 CPU 核的区别

`cpu_top` 只包含 CPU 核，露出取指、数据访存、MMIO 和 UART 字节握手接口；`cpu_loader_top` 已把这些接口接到具体存储器和外设，RAM 接口成为内部连线。

`core/if/inst_ram.sv` 是 CPU 的取指请求控制模块；`core/iram.sv` 才是保存指令的 RAM 数组。

### 系统顶层接口

| 信号 | 方向 | 说明 |
| --- | --- | --- |
| `sys_clk_p`、`sys_clk_n` | 输入 | 板级差分时钟，经顶层 IBUFDS 转成内部 clk |
| `rst_n` | 输入 | 系统低有效复位 |
| `irq_i` | 输入 | 高电平有效的外部机器中断，不使用时接 0 |
| `uart_rxd` | 输入 | 下载串口 RX |
| `uart_txd` | 输出 | loader 应答串口 TX |
| `cpu_uart_txd` | 输出 | 独立 CPU 打印串口 TX |
| `pl_led1`、`pl_led2` | 输出 | LED 寄存器 bit 0、bit 1，直接输出、不反相 |
| `loader_init_done_o`、`loader_busy_o`、`loader_pgm_done_o` | 输出 | loader 初始化、忙、操作完成状态 |
| `loader_error_o`、`loader_error_code_o[4:0]` | 输出 | loader 错误状态与错误码 |
| `cpu_running_o` | 输出 | CPU 是否解除复位，不等同于程序已执行成功 |
| `wb_we_o`、`wb_waddr_o[4:0]`、`wb_wdata_o[31:0]` | 输出 | 通用寄存器写回调试 |

原来的 `cpu_uart_tx_data/valid/ready` 已是顶层内部信号，由 `u_cpu_uart_tx` 接收，不再需要外部给出 `ready`。

| 顶层参数 | 默认值 | 含义 |
| --- | --- | --- |
| `CLK_FREQ` | `100_000_000` | 实际输入时钟频率，单位 Hz |
| `UART_BPS` | `115200` | loader 串口波特率 |
| `CPU_UART_BPS` | `115200` | 独立打印串口波特率 |
| `LOADER_TIMEOUT` | `100_000_000` | loader 等待超时的时钟周期数 |

两个串口均为 8N1。`CLK_FREQ` 参数不会生成时钟，必须与板上差分输入时钟的真实频率一致。顶层 `IBUFDS` 只做差分输入缓冲，输出内部 `clk`，不改变频率；它是 FPGA 原语，不需要另外生成 IP 文件。当前 `cpu.xdc` 使用 10 ns 周期，即 100 MHz。

## 3. 地址与 RAM 握手

| 用途 | CPU 地址 | loader 地址 | 大小/行为 |
| --- | --- | --- | --- |
| IRAM | `0x0000_0000～0x0000_7FFF` | 同左 | 32 KiB，CPU 读指令，loader 写指令/NOP |
| DRAM | `0x8000_0000～0x8000_7FFF` | `0x1000_0000～0x1000_7FFF` | 32 KiB，CPU 读写，loader 写初始数据 |
| CPU UART 输出 | 写 `0x4000_0000` | 无 | 将写入数据低 8 位交给独立 UART 发送器 |
| LED 寄存器 | `0x4000_1000～0x4000_1003` | 无 | 同一个 32 位寄存器，支持按字节读写，低两位控制引脚 |

CPU 将 UART 地址的写操作送到字节发送接口，将 MMIO 区域内的其他访问送到 `led_reg`。当前没有其他 MMIO 外设，LED 地址未命中的请求读回零、写入无效，并正常应答。向 UART 地址读数据并不是读取 UART 状态寄存器。

顶层把 CPU 数据地址减去 `0x8000_0000`，把 loader 数据地址减去 `0x1000_0000`，都转换为 RAM 内部字节偏移。两块 RAM 各为 `8192 × 32 bit`，使用地址 `[14:2]` 索引数组。

RAM 使用 `IDLE` 和 `RESP` 两个状态，每块同时最多处理一笔请求：

1. `req_valid && req_ready` 的上升沿接受请求，随后进入 RESP。
2. 当前实现读请求在接受时同步读取数组；写请求先锁存地址、数据和字节使能，下一上升沿执行一次写入。
3. RESP 期间保持 `rsp_valid`，读响应数据保持稳定。写响应的数据不使用。
4. `rsp_valid && rsp_ready` 完成响应后回到 IDLE。写入最早与写响应接收发生在同一上升沿。

RAM 使用同步数组读写并带 `ram_style="block"` 属性，目标是由 Vivado 推断为 BRAM；实际映射结果以综合报告为准。复位清除握手状态，不清空数组内容；程序必须先下载所需的指令与数据。

目前没有硬件 RAM 地址范围检查，高地址被数组索引截断后可能映射回低地址；`ldr_rsp_error` 固定为 0。loader 自身和上位机脚本仍检查下载镜像长度、偏移和容量。

## 4. 顶层关键控制逻辑

### CPU 启动保护

```verilog
if (!rst_n)
    loader_reset_seen_q <= 1'b0;
else if (loader_init_done_o && !loader_cpu_reset)
    loader_reset_seen_q <= 1'b1;

assign cpu_rst_n = rst_n && loader_reset_seen_q && loader_cpu_reset;
```

loader 在 INIT 中会释放复位，因此顶层先用 `loader_reset_seen_q=0` 阻止 CPU 提前启动。loader 初始化完成后，下载前导码或启动命令使它再次拉低复位，顶层记住这一事件。之后必须等 loader 再次释放复位，CPU 才运行。

`loader_reset_seen_q` 表示“初始化后见过 loader 主动复位”，不是“程序下载成功”。通常流程是下载指令、下载数据、发送 `B0`。直接发送 `B0` 也能启动已有 RAM 内容。

### 请求选择和 ready 返回

```verilog
iram_select_loader = ldr_req_valid && !ldr_ram_sel;
dram_select_loader = ldr_req_valid &&  ldr_ram_sel;
```

`ldr_ram_sel=0` 选择 IRAM，`=1` 选择 DRAM。loader 对新请求有优先权；CPU 复位时禁止新的 CPU 内存请求。请求地址、写数据、写使能随选择信号切换，被选中的请求方得到目标 RAM 的 `req_ready`。

IRAM 的写数据和字节使能直接来自 loader，只有选中 loader 时才允许写；CPU 只读 IRAM。DRAM 的数据、字节使能和读写方向需要在 CPU 与 loader 之间选择。

### 响应归属记录

`iram_owner_loader_q`、`dram_owner_loader_q` 在对应请求握手时更新：1 表示 loader，0 表示 CPU。RAM 未完成响应前不会接受新请求，因此归属在等待期间保持不变。

属于 loader 的响应等待 `ldr_rsp_ready`；属于 CPU 的响应总是接收。若 CPU 已因重新下载而复位，之前的 CPU 响应被接收并丢弃，不会误交给 loader，也不会阻塞 RAM。

### 复位分配

| 模块 | 使用的复位 | 效果 |
| --- | --- | --- |
| CPU | `cpu_rst_n` | 下载期间停止程序执行 |
| `led_reg` | `cpu_rst_n` | LED 寄存器清零，取消旧 MMIO 事务 |
| 独立 CPU UART | `cpu_rst_n` | 重新下载时停止旧程序发送，可能中断当时正在发送的字符 |
| loader、IRAM、DRAM | `rst_n` | CPU 复位期间仍工作，RAM 内容不因 CPU 复位而清空 |

LED 清零表示两个引脚输出低电平；如果板卡 LED 低电平有效，此时可能已经点亮。

## 5. 裸机 C 测试程序与启动过程

源文件：[software/led_uart.c](software/led_uart.c)。程序使用标准 C 控制 MMIO，由 LLVM 编译成 RV32I 指令，不使用操作系统、libc、printf 或系统调用。

```text
PC=0 → _start 设置 SP/GP → 清零 BSS → 调用 C main
    → 打印 LED test start → 设置 LED → 读回检查
                                  ├─ 相同：打印寄存器值和成功信息
                                  └─ 不同：打印期望值、实际值及错误信息
    → main 返回 → 启动代码原地循环，保持 LED 输出
```

### C 程序各部分的作用

| 代码 | 作用 |
| --- | --- |
| `UART_TX_REG` | `0x4000_0000` 的 volatile 8 位寄存器，写一个字节交给 UART 发送器 |
| `LED_REG` | `0x4000_1000` 的 volatile 32 位寄存器，控制两路 LED，并支持读回 |
| `LED_ACTIVE_LOW` | 编译时选择 LED 极性；0 时写 3，1 时写 0 |
| `led_on_value` | 保存 LED 输出值的变量，CPU 从 DRAM 读取 |
| `led_readback` | 保存 LED 读回值的零初始化变量，位于 BSS，由启动代码清零 |
| `uart_putc` | 把字符写入 UART 寄存器；CPU 的硬件握手负责等待发送器接收 |
| `uart_puts` | 遍历以零结尾的字符串，逐字节调用 uart_putc，结束零不发送 |
| `uart_put_hex32` | 用移位和按位与取出八个十六进制数字，不使用乘除法 |
| `main` | 打印开始信息，写 LED、读回比较，输出成功或失败信息并返回 |

`volatile` 确保编译器保留 MMIO 和测试变量的实际读写，不把寄存器访问当作普通常量优化掉。`uint8_t` 用于 UART 字节写，`uint32_t` 用于 LED 字读写；函数调用所需的栈由启动代码提供。

默认高电平点亮版本的预期输出：

```text
LED test start
RV32I bare-metal C test
LED_REG=0x00000003, readback OK
UART OK
```

低电平点亮版本显示 `LED_REG=0x00000000, readback OK`。失败路径会打印 `ERROR: LED register readback mismatch`，以及期望值、实际值。这里检查的是寄存器读回，实际 LED 亮灭还取决于引脚与板级有效电平。

程序只打印一次。main 返回后 CPU 继续执行原地循环，不会关机；最后一个 UART 字节仍可由发送器继续发送。

### 启动代码为何不能省略

[platform/start.S](platform/start.S) 的 `_start` 固定放在 IRAM 地址 0。CPU 复位后的通用寄存器不能直接当作有效的 C 运行环境，因此入口先执行：

1. `la sp, __stack_top`：SP 设为 `0x8000_8000`，满足 16 字节对齐，栈向低地址增长。
2. `la gp, __global_pointer$`：初始化全局指针；本构建同时关闭小数据优化和链接松弛，避免隐式依赖未准备好的 GP。
3. 使用 t0/t1 遍历 `__bss_start` 到 `__bss_end`，每次 `sw zero` 清除 4 字节。
4. `call main`：进入 C 测试程序，main 的返回值留在 a0。
5. main 返回后通过 `j` 原地循环，保持外设设置。

`.data` 不需要在启动时从 IRAM 复制：下载器已经单独把数据镜像写入 DRAM。BSS 不放入下载镜像，由启动代码每次清零，因此只发送 B0 重新启动时也能重新初始化 BSS；普通已初始化数据则不会在 B0 时自动恢复成最初镜像。本示例不修改 `led_on_value`。

### 链接脚本与两个镜像

[platform/link.ld](platform/link.ld) 分配如下：

| 内容 | 地址/区域 | 下载与初始化方式 |
| --- | --- | --- |
| `.text.start`、`.text` | IRAM，从 `0x0000_0000` 开始 | 提取 `imem.raw.bin`，转换为 `imem.flash.bin` 后下载 |
| 字符串常量、只读表、已初始化变量 | 合并进 `.data`，DRAM 从 `0x8000_0000` 开始 | 提取 `dmem.raw.bin`，转换为 `dmem.flash.bin` 后下载 |
| `.bss` | 紧接 DRAM 的数据段，按 4 字节对齐 | 不进入镜像，由启动代码清零 |
| 栈 | 预留 `0x8000_7000～0x8000_7FFF` | 初始 SP 为 `0x8000_8000`，向低地址增长 |

**字符串必须放在 DRAM。** 当前 CPU 取指使用 IRAM 端口，普通 load/store 使用 DRAM 端口；不能像统一存储器系统那样默认把 `.rodata` 放在代码后面，再通过数据端口去读 IRAM。

链接脚本检查代码是否超过 32 KiB、数据和 BSS 是否侵入预留栈空间；这属于构建时的布局限制，没有新增硬件地址范围检查。栈运行时是否越界仍由程序使用情况决定。

原汇编版的固定字符串偏移和 21 条指令表不再适用于 C 版本。字符串地址、寄存器分配、指令数量由编译器和链接器决定，构建后查看 `led_uart.map` 与 `program.lst`。

## 6. Linux 下使用 LLVM 编译裸机 C 程序

独立操作文档：[Linux LLVM 编译指南](LLVM_LINUX_BUILD.md)，包含整段 Bash 构建命令、工具链选择、参数解释和结果检查。该指南按服务器 `led_test/` 中平铺的 `led_uart.c`、`start.s`、`linker.ld` 编写；本节命令则用于完整仓库的 `software/`、`platform/` 目录布局。

### 安装工具

Linux 是编译主机，FPGA 上运行的是 RV32I 裸机程序。需要带 RISC-V 后端的 `clang`、`ld.lld`、`llvm-objcopy` 和 `llvm-objdump`，本示例不需要 RISC-V Linux 根文件系统或 libc。

Ubuntu / Debian 可使用发行版软件源安装：

```sh
sudo apt update
sudo apt install clang lld llvm python3 python3-venv
```

以下命令在本 README 所在目录执行，使用同一个 Bash 终端。按你提供的 `/home/shenjiexiang/llvm-project` 配置工具路径，默认可执行文件在其 `build/bin` 下。先设置工具路径、输出目录和 LED 极性：

```bash
LLVM_BIN="${LLVM_BIN:-/home/shenjiexiang/llvm-project/build/bin}"
CLANG="$LLVM_BIN/clang"
LLD="$LLVM_BIN/ld.lld"
OBJCOPY="$LLVM_BIN/llvm-objcopy"
OBJDUMP="$LLVM_BIN/llvm-objdump"
BUILD=build/led_uart
LED_ACTIVE_LOW=0
mkdir -p "$BUILD"
```

如果工具位于其他目录，先设置 `export LLVM_BIN=实际的可执行文件目录`，再执行上面的代码块；若名称带版本后缀，修改对应文件名。板上 LED 低电平点亮时，将 `LED_ACTIVE_LOW` 设为 `1`。每次修改程序或极性后，都重新执行下面的编译、链接、镜像提取和重排步骤。

实际可执行文件位置的检查方法见 [Linux LLVM 编译指南](LLVM_LINUX_BUILD.md#2-准备-linux-工具)。当前未连接你的 Linux 服务器，需确认默认的 `build/bin` 目录存在。

### 第一步：编译启动汇编和 C 源文件

```bash
CPU_FLAGS=(
    --target=riscv32-unknown-elf
    -march=rv32i
    -mabi=ilp32
    -mno-relax
    -msmall-data-limit=0
)

"$CLANG" "${CPU_FLAGS[@]}" -g \
    -c platform/start.S -o "$BUILD/start.o"

"$CLANG" "${CPU_FLAGS[@]}" \
    -std=c11 -O1 -g \
    -ffreestanding -fno-builtin -fno-stack-protector \
    -fno-pic -fno-pie -fno-unwind-tables -fno-asynchronous-unwind-tables \
    -Wall -Wextra -DLED_ACTIVE_LOW="$LED_ACTIVE_LOW" \
    -c software/led_uart.c -o "$BUILD/led_uart.o"
```

| 参数 | 在本工程中的作用 |
| --- | --- |
| `--target=riscv32-unknown-elf` | 指定 32 位 RISC-V 裸机目标，避免生成主机的 x86/ARM 程序 |
| `-march=rv32i`、`-mabi=ilp32` | 使用 RV32I 基础整数指令与对应 ABI，不启用压缩、乘除法或浮点扩展 |
| `-mno-relax`、`-msmall-data-limit=0` | 关闭编译端松弛和小数据优化，使地址访问方式与当前启动、链接方案保持一致 |
| `-ffreestanding`、`-fno-builtin` | 使用裸机编译环境，禁用普通库函数的内建优化；不会自动提供 libc |
| `-fno-stack-protector` | 避免额外依赖栈保护运行库 |
| `-fno-pic`、`-fno-pie` | 按链接脚本确定的固定地址生成代码 |
| `-fno-unwind-tables`、`-fno-asynchronous-unwind-tables` | 不生成本示例不使用的栈展开表 |
| `-O1`、`-g` | 开启基础优化，同时保留调试信息 |
| `-DLED_ACTIVE_LOW=0/1` | 选择板级 LED 的有效电平 |

跨编译必须显式指定目标，Clang 默认使用宿主目标，见 [Clang 跨编译说明](https://clang.llvm.org/docs/CrossCompilation.html)。本示例使用 `<stdint.h>` 提供的整数类型，不调用标准库函数；以后若加入 `printf`、动态内存分配或可能生成运行库调用的运算，还需提供相应裸机实现。

### 第二步：按 IRAM/DRAM 布局链接

```bash
"$LLD" -m elf32lriscv --no-relax --build-id=none \
    -T platform/link.ld -Map="$BUILD/led_uart.map" \
    "$BUILD/start.o" "$BUILD/led_uart.o" \
    -o "$BUILD/led_uart.elf"
```

`-T` 指定本工程的链接脚本，入口由其中的 `ENTRY(_start)` 指定。直接调用 `ld.lld` 链接两个对象文件，不自动加入主机启动文件或标准库。`--no-relax` 关闭链接阶段的松弛，`-Map` 输出地址布局。LLD 支持 RISC-V ELF，见 [LLD 官方说明](https://lld.llvm.org/)。

### 第三步：分别提取指令和数据镜像

```bash
"$OBJCOPY" -O binary --only-section=.text \
    "$BUILD/led_uart.elf" "$BUILD/imem.raw.bin"

"$OBJCOPY" -O binary --only-section=.data \
    "$BUILD/led_uart.elf" "$BUILD/dmem.raw.bin"

"$OBJDUMP" -d -S "$BUILD/led_uart.elf" > "$BUILD/program.lst"
```

`--only-section` 只提取指定输出段，`-O binary` 生成原始二进制，见 [llvm-objcopy 说明](https://llvm.org/docs/CommandGuide/llvm-objcopy.html)。链接脚本已把字符串和只读表合并进 `.data`，所以提取该段即可包含它们；`.bss` 不需要下载。

### 第四步：最后用 bin2pqr5bin.py 重排

```bash
python3 bin2pqr5bin.py -binfile "$BUILD/imem.raw.bin" \
    -baseaddr 0 -outfile "$BUILD/imem.flash.bin"

python3 bin2pqr5bin.py -binfile "$BUILD/dmem.raw.bin" \
    -baseaddr 0 -outfile "$BUILD/dmem.flash.bin"

# 原脚本固定生成 C0 帧头；只修正数据镜像输出文件的前四字节。
printf '\320\320\320\320' | dd of="$BUILD/dmem.flash.bin" bs=1 count=4 conv=notrunc status=none
```

原版脚本对每个 32 位字进行字节反序，并添加固定 `C0` 帧头和帧尾，没有 `-memtype` 选项。数据 RAM 需要 `D0` 帧头，所以上面用 Bash 命令修正生成的数据文件，保留 Python 脚本原样。两个 `-baseaddr` 都是各自 RAM 内的字节偏移 `0`，不能填 CPU 数据地址 `0x80000000` 或 loader 的 DRAM 基址 `0x10000000`。

完整构建流程为：

```text
software/led_uart.c ── clang ─→ led_uart.o ─┐
platform/start.S ───── clang ─→ start.o ────┴─ ld.lld + link.ld → led_uart.elf

led_uart.elf ─┬─ llvm-objcopy .text → imem.raw.bin
             └─ llvm-objcopy .data → dmem.raw.bin

imem.raw.bin ── bin2pqr5bin.py → imem.flash.bin
dmem.raw.bin ── bin2pqr5bin.py + 修正输出帧头 → dmem.flash.bin
```

不要直接把整个 ELF 转为一个二进制：代码和数据的起始地址相隔 `0x8000_0000`，合并提取可能产生巨大的填充区域，而且 loader 需要分别下载到两块 RAM。两个 raw 文件各自从相应 RAM 的偏移 0 开始。

| 生成文件（位于 build/led_uart/） | 用途 |
| --- | --- |
| `start.o`、`led_uart.o` | 汇编与 C 的中间对象文件 |
| `led_uart.elf` | 包含入口、段、符号和调试信息的完整程序 |
| `led_uart.map` | 链接地址、段大小和符号布局 |
| `program.lst` | 源码与汇编反汇编列表，用于理解实际执行指令 |
| `imem.raw.bin`、`dmem.raw.bin` | 原始小端指令、数据镜像 |
| `imem.flash.bin`、`dmem.flash.bin` | 重排并封装后的最终下载镜像 |

上述命令生成 ELF、原始镜像、重排后的 `*.flash.bin` 和辅助文件，不自动下载。出现编译、链接或转换错误时，先处理错误，再执行后续步骤，避免使用旧镜像。

## 7. 串口下载和独立打印

**当前下载依赖尚未补齐。** 原版 `python_tools/peqflash.py` 导入 `pack_flash.py`，但工程中缺少该文件，因此包括 `--help` 在内的调用都会失败。下面的下载命令以补齐这个原有依赖为前提；LLVM 编译和 `bin2pqr5bin.py` 重排不受影响。

### 板级连接

- 下载适配器 TX 接 `uart_rxd`，RX 接 `uart_txd`。
- 打印适配器 RX 接 `cpu_uart_txd`，TX 不需要连接。
- FPGA 与两个适配器共地，I/O 电平与板卡匹配。
- 配置时钟、复位、两组串口及 LED 的 FPGA 引脚约束；中断不用时把 `irq_i` 接 0。

### 下载并查看打印

在工程外建立 Python 虚拟环境并安装串口依赖：

```sh
python3 -m venv ~/.venvs/cpu-uart
source ~/.venvs/cpu-uart/bin/activate
python -m pip install pyserial
```

在工程目录中使用第 6 节经 `bin2pqr5bin.py` 重排后的两个镜像：

```sh
python python_tools/peqflash.py \
    -serport /dev/ttyUSB0 -baud 115200 \
    -imembin build/led_uart/imem.flash.bin \
    -dmembin build/led_uart/dmem.flash.bin \
    --monitor-port /dev/ttyUSB1 --monitor-baud 115200
```

**这里不要加 `--raw`**：输入文件已经重排并添加 loader 协议，加上会重复处理。下载脚本不会编译 C，也不会检查镜像是否比源文件旧；每次改 C 程序都要重新构建并转换。LED 极性由编译参数决定，不是下载参数。

补齐依赖后，也可以用 `--demo` 代替两个文件参数，读取 `build/led_uart/imem.flash.bin` 和 `dmem.flash.bin`。它只读取现有镜像，不执行编译或转换；原版帮助中的 make 提示不适用于当前工程，应按第 6 节构建。

串口名称替换成实际设备名。`--monitor-baud` 对应 `CPU_UART_BPS`，`-baud` 对应 `UART_BPS`，默认均为 115200、8N1。若 Linux 提示串口权限不足，需要按发行版配置设备访问权限。

打印串口会在启动 CPU 前打开，启动后不清空打印缓冲区，避免丢失 `LED test start`。按 Ctrl+C 退出监视，或增加 `--monitor-seconds 5` 自动退出。监视只读，不向 CPU 发送键盘输入。

### 下载协议和重新启动

loader 接收的是协议帧，不能直接把 ELF 或 raw 文件的字节裸发到串口。协议格式是四字节前导码、四字节大端正文长度、四字节大端存储区偏移、正文及四字节结束码。IRAM 前导码为 `C0 C0 C0 C0`，DRAM 为 `D0 D0 D0 D0`，结束码为 `E0 E0 E0 E0`。正文每个 32 位字改为高字节先发。两个 raw 镜像的长度必须为 4 的倍数，链接脚本已按字对齐段末尾。这些处理属于下载打包，不是 LLVM 编译器的工作。

| 命令/参数 | 行为 |
| --- | --- |
| `D3` | 查询设备签名，预期 `C0 DE 4A 11` |
| `B0` | 启动或重新启动已有程序，不清空 RAM |
| `B1` | 用 NOP 清空 IRAM，然后启动 CPU |
| `-rebootonly` | 不下载，发送启动命令 |
| `-cleanimem` | 下载前执行 B1；与 `-rebootonly` 同用时仅执行 B1 |
| `-reloc` | 改 IMEM 下载偏移，但不改变 CPU 启动 PC，也不重定位 ELF 内的引用；本 C 示例不能随意使用它 |

本示例的 IRAM/DRAM 下载偏移均为 0。CPU 数据指针仍使用 `0x8000_0000` 起的地址，loader 会把 DRAM 镜像偏移转换为自己的 `0x1000_0000` 起的地址。

重新启动已经下载的程序：

```sh
python python_tools/peqflash.py -serport /dev/ttyUSB0 -rebootonly --monitor-port /dev/ttyUSB1
```

## 8. Vivado 工程与上板前待完成项

将 `rtl.f` 中的 RTL 文件加入工程，顶层设为 `cpu_loader_top`，include directory 设为 `core/`，以找到 `core/define.sv` 头文件。`software/led_uart.c`、`platform/` 和 Python 脚本不作为 RTL 加入综合工程。

当前 XDC 的差分时钟、复位、下载串口和独立打印串口名称已与顶层对应；LED、irq_i 及对外调试端口仍需按板卡分配引脚或在板级封装中内部连接。上板前需要补齐这些约束，并查看综合报告，确认 IRAM/DRAM 的实际 BRAM 推断结果。当前 README 没有假设具体开发板型号或提供固定引脚编号。

`cpu.tcl` 从 `rtl.f` 读取源文件，加入 `core/define.sv` 和 `cpu.xdc`，随后运行综合、实现和 bitstream 生成。**当前脚本中的 `part_name` 为 `xczu5ev-sfvc784-2-e(active)`，应先按实际芯片修正；如果目标就是该器件，则去掉 `(active)`，使用 `xczu5ev-sfvc784-2-e`。** 补齐板级约束后，在配置好 Vivado 环境的终端中运行：

```sh
vivado -mode batch -source cpu.tcl
```

脚本把工程和报告写入 `prj/`。当前目录没有自动化测试文件，本文不提供对已删除测试脚本的调用命令。

当前尚需完成：下载脚本的打包依赖、Tcl 器件名修正，以及 LED、中断和调试端口的板级处理。文中的终端输出是测试程序的预期行为；本文列出了构建和下载步骤，不表示已经完成 LLVM 编译、仿真或上板验证。
