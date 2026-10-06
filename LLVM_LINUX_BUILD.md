# Linux 下用 LLVM 编译 LED / UART 裸机程序

本文针对当前工程的 LED / UART 裸机程序。第 3 节命令按你服务器上的平铺目录编写：`led_uart.c`、`start.s`、`linker.ld` 和 `bin2pqr5bin.py` 都位于 `~/Desktop/rsicv/c_demo/led_test/`。其中 `start.s` 对应仓库的 `platform/start.S`，`linker.ld` 对应仓库的 `platform/link.ld`，以下按内容相同、仅路径和文件名不同说明。Linux 是编译主机，生成的程序运行在 FPGA 的 RV32I CPU 上。

## 1. 三个文件怎样配合

| 文件 | 作用 |
| --- | --- |
| [software/led_uart.c](software/led_uart.c) | C 程序：控制 LED、读取寄存器、输出串口字符，提供 `main()` |
| [platform/start.S](platform/start.S) | CPU 复位入口 `_start`：设置 `sp`、`gp`，清零 `.bss`，调用 `main` |
| [platform/link.ld](platform/link.ld) | 链接脚本：规定代码、数据和栈放在哪些地址 |

```text
start.s ───── clang ──→ start.o ─────┐
                                   ├─ ld.lld + linker.ld ─→ led_uart.elf
led_uart.c ── clang ──→ led_uart.o ──┘

led_uart.elf ── llvm-objcopy ──→ imem.raw.bin（指令）
                           └─→ dmem.raw.bin（字符串、初始数据）

imem.raw.bin ── bin2pqr5bin.py ─→ imem.flash.bin
dmem.raw.bin ── bin2pqr5bin.py + 修正输出帧头 ─→ dmem.flash.bin
```

Linux 区分大小写，`start.s` 和 `start.S` 是不同文件名。下面对小写的 `start.s` 显式使用 `-x assembler-with-cpp`，保持与仓库大写 `.S` 相同的汇编预处理方式；`.ld` 交给链接器，不单独编译。不要只编译 C 文件后就把 `main` 当作复位入口。

## 2. 准备 Linux 工具

Ubuntu / Debian 可以安装发行版提供的工具包：

```bash
sudo apt update
sudo apt install clang lld llvm python3
```

你提供的 LLVM 路径是 `/home/shenjiexiang/llvm-project`。先在 Linux 上查找实际可执行文件：

```bash
find /home/shenjiexiang/llvm-project -type f -name clang -executable
```

如果结果为 `/home/shenjiexiang/llvm-project/build/bin/clang`，在当前 Bash 终端执行：

```bash
export LLVM_BIN=/home/shenjiexiang/llvm-project/build/bin
export CLANG="$LLVM_BIN/clang"
export LLD="$LLVM_BIN/ld.lld"
export OBJCOPY="$LLVM_BIN/llvm-objcopy"
export OBJDUMP="$LLVM_BIN/llvm-objdump"
```

若结果在其他目录，将 `LLVM_BIN` 改为实际的 `bin` 目录。若没有结果且目录中只有 `llvm/`、`clang/` 等源码目录，需要先构建 LLVM；源码目录本身不是编译器可执行文件。这里只记录了你提供的路径，尚未访问该 Linux 环境核实安装位置。

已有自行编译的 LLVM 时，需要包含 RISC-V 后端、Clang 和 LLD。设置变量后检查（未设置时使用 PATH 中的工具）：

```bash
"${CLANG:-clang}" --version
"${CLANG:-clang}" --print-targets
"${LLD:-ld.lld}" --version
"${OBJCOPY:-llvm-objcopy}" --version
"${OBJDUMP:-llvm-objdump}" --version
python3 --version
```

`clang --print-targets` 的输出应包含 `riscv32`。若没有，需换用包含 RISC-V 后端的 LLVM；自行构建 LLVM 时，目标选项应包含 `-DLLVM_TARGETS_TO_BUILD=RISCV`，项目选项应包含 `-DLLVM_ENABLE_PROJECTS="clang;lld"`。

Clang 的目标架构由 `--target` 指定；不指定时默认面向宿主机，参见 [Clang 跨编译文档](https://clang.llvm.org/docs/CrossCompilation.html)。本程序不需要 RISC-V Linux sysroot、glibc 或额外的 GCC 工具链。

## 3. 完整编译命令

你的服务器目录结构为：

```text
~/Desktop/rsicv/c_demo/led_test/
├── led_uart.c
├── start.s
├── linker.ld
├── bin2pqr5bin.py
└── build/
```

先进入该目录：

```bash
cd ~/Desktop/rsicv/c_demo/led_test
```

命令直接读取当前目录下的文件，不需要创建 `software/` 或 `platform/`。如果在完整仓库目录中构建，请使用 README 第 6 节对应仓库布局的命令。

下面整段复制到 **Bash** 中执行。已按你提供的 `/home/shenjiexiang/llvm-project` 配置工具路径，默认可执行文件位于其 `build/bin` 下，无需提前 export 每个工具变量。若第 2 节查到其他位置，先设置 `export LLVM_BIN=实际的可执行文件目录`。括号使构建在子 shell 内运行；任何一步失败都会停止本次构建。数组语法不能直接交给 `sh`。

```bash
(
    set -euo pipefail

    # 使用指定 LLVM 目录下的可执行文件，不依赖 PATH 中的 clang。
    LLVM_BIN="${LLVM_BIN:-/home/shenjiexiang/llvm-project/build/bin}"
    CLANG="$LLVM_BIN/clang"
    LLD="$LLVM_BIN/ld.lld"
    OBJCOPY="$LLVM_BIN/llvm-objcopy"
    OBJDUMP="$LLVM_BIN/llvm-objdump"
    PYTHON="${PYTHON:-python3}"
    LED_ACTIVE_LOW="${LED_ACTIVE_LOW:-0}"
    BUILD=build/led_uart

    for source in start.s led_uart.c linker.ld bin2pqr5bin.py; do
        test -f "$source" || {
            echo "找不到文件：$source，请确认当前目录为 led_test 且文件名大小写一致" >&2
            exit 1
        }
    done

    for tool in "$CLANG" "$LLD" "$OBJCOPY" "$OBJDUMP" "$PYTHON"; do
        command -v "$tool" >/dev/null || {
            echo "找不到工具：$tool" >&2
            exit 1
        }
    done
    mkdir -p "$BUILD"

    CPU_FLAGS=(
        --target=riscv32-unknown-elf
        -march=rv32i
        -mabi=ilp32
        -mno-relax
        -msmall-data-limit=0
    )

    # 1. 编译启动汇编。
    "$CLANG" "${CPU_FLAGS[@]}" -g -x assembler-with-cpp \
        -c start.s -o "$BUILD/start.o"

    # 2. 编译 C 程序。
    "$CLANG" "${CPU_FLAGS[@]}" \
        -std=c11 -O1 -g \
        -ffreestanding -fno-builtin -fno-stack-protector \
        -fno-pic -fno-pie \
        -fno-unwind-tables -fno-asynchronous-unwind-tables \
        -Wall -Wextra -DLED_ACTIVE_LOW="$LED_ACTIVE_LOW" \
        -c led_uart.c -o "$BUILD/led_uart.o"

    # 3. 使用本工程的内存布局链接，不加入 libc 或系统启动文件。
    "$LLD" -m elf32lriscv --no-relax --build-id=none \
        -T linker.ld -Map="$BUILD/led_uart.map" \
        "$BUILD/start.o" "$BUILD/led_uart.o" \
        -o "$BUILD/led_uart.elf"

    # 4. 分别提取两块 RAM 的原始小端镜像。
    "$OBJCOPY" -O binary --only-section=.text \
        "$BUILD/led_uart.elf" "$BUILD/imem.raw.bin"
    "$OBJCOPY" -O binary --only-section=.data \
        "$BUILD/led_uart.elf" "$BUILD/dmem.raw.bin"

    # 5. 生成反汇编与 ELF 布局报告。
    "$OBJDUMP" -d -S "$BUILD/led_uart.elf" > "$BUILD/program.lst"
    "$OBJDUMP" -f -h -t "$BUILD/led_uart.elf" > "$BUILD/elf-info.txt"
    # 6. 最后用 bin2pqr5bin.py 按 32 位字重排，并添加下载协议头尾。
    "$PYTHON" bin2pqr5bin.py -binfile "$BUILD/imem.raw.bin" \
        -baseaddr 0 -outfile "$BUILD/imem.flash.bin"
    "$PYTHON" bin2pqr5bin.py -binfile "$BUILD/dmem.raw.bin" \
        -baseaddr 0 -outfile "$BUILD/dmem.flash.bin"
    # 保留原版脚本：它固定生成 C0 帧头，数据镜像需单独改为 D0。
    printf '\320\320\320\320' | dd of="$BUILD/dmem.flash.bin" bs=1 count=4 conv=notrunc status=none
    wc -c "$BUILD/imem.flash.bin" "$BUILD/dmem.flash.bin"
    echo "构建完成：$BUILD/imem.flash.bin 和 $BUILD/dmem.flash.bin"
)
```

如果实际可执行文件位于 `/home/shenjiexiang/llvm-project/bin`，在执行整段命令前设置：

```bash
export LLVM_BIN=/home/shenjiexiang/llvm-project/bin
```

`LLVM_BIN` 必须是实际包含 `clang`、`ld.lld`、`llvm-objcopy` 和 `llvm-objdump` 的目录。若工具名称带版本后缀，直接修改上面代码块中的对应文件名。你提供的终端输出已确认 `clang` 位于 `/home/shenjiexiang/llvm-project/build/bin`；其余工具由构建命令逐个检查。

本流程不要求安装 `llvm-readelf`。ELF 检查报告复用 `llvm-objdump -f -h -t`，分别输出文件概要、节表和符号表。若服务器上的旧命令仍提示找不到 `llvm-readelf`，请重新复制本节的完整代码块；本地 Markdown 的修改不会自动同步到服务器。

LED 默认按高电平点亮编译；如果板上 LED 低电平点亮，在重新执行完整构建前设置：

```bash
export LED_ACTIVE_LOW=1
```

改回高电平点亮时设为 `0`。修改源文件、启动文件、链接脚本或极性后，都要重新构建并下载新镜像。构建失败时不要使用目录里上次留下的镜像。

## 4. 编译参数为什么这样选

| 参数 | 含义 |
| --- | --- |
| `--target=riscv32-unknown-elf` | 生成 32 位 RISC-V 裸机目标文件 |
| `-march=rv32i` | 使用基础整数指令集，不启用 M、C、F 等扩展 |
| `-mabi=ilp32` | 采用匹配的整数调用约定，int、long、指针均为 32 位 |
| `-mno-relax` / `--no-relax` | 分别关闭编译端和链接端松弛 |
| `-msmall-data-limit=0` | 关闭小数据优化，配合当前固定地址的构建方案 |
| `-ffreestanding -fno-builtin` | 按裸机环境编译，禁用普通库函数的内建优化；不会提供 libc 实现 |
| `-fno-stack-protector` | 避免依赖栈保护运行库 |
| `-fno-pic -fno-pie` | 生成按链接脚本固定地址运行的代码 |
| `-fno-unwind-tables -fno-asynchronous-unwind-tables` | 不生成本例不使用的栈展开表 |
| `-O1 -g` | 基础优化并保留调试信息，便于查看反汇编 |
| `-c` | 只生成 `.o`，暂不链接 |
| `-T linker.ld` | 用当前目录的链接脚本安排地址 |

这里直接调用 `ld.lld`，输入只有两个 `.o`，因此不会自动链接宿主机的启动文件和标准库，不需要向它传 Clang 的 `-nostdlib` 参数。LLD 的目标支持见 [LLD 官方说明](https://lld.llvm.org/)。

本例的 `<stdint.h>` 只提供整数类型，不代表程序调用了 libc。以后加入 `printf`、`malloc`，或编译器生成了 `memcpy`、除法辅助函数等调用时，需要另行提供相应实现；`-ffreestanding` 不保证所有 C 代码都能完全脱离运行库。

## 5. 地址布局、SP / GP 和 BSS

当前 `link.ld` 定义：

| 内容 | CPU 地址或范围 | 初始化方式 |
| --- | --- | --- |
| `.text`，包含 `_start` | 从 `0x00000000` 开始，IRAM 共 32 KiB | 下载 `imem.flash.bin` |
| `.data`，包含字符串和只读表 | 从 `0x80000000` 开始，位于 32 KiB DRAM 内 | 下载 `dmem.flash.bin` |
| `.bss` | 跟在 `.data` 后，按 4 字节对齐 | `_start` 循环清零 |
| `__global_pointer$` | `0x80000800` | `_start` 将此地址写入 `gp` |
| 预留栈 | `0x80007000`～`0x80007FFF` | 运行时使用，向低地址增长 |
| `__stack_top` | `0x80008000` | `_start` 将此地址写入 `sp` |

默认配置的 `led_on_value = 3` 属于初始数据，`led_readback` 属于零初始化数据。低电平点亮配置下，`led_on_value` 的初值为零，也可能被编译器放入 `.bss`。以实际 ELF 段和符号为准。

字符串虽然只读，也必须进入 DRAM：本工程的普通 load/store 通过数据端口读取，不能默认从 IRAM 读取代码后面的字符串。链接脚本已将 `.rodata` 等输入段合并进 `.data`。

`.bss` 占运行时 RAM，不需要下载一串零；`start.S` 会清零它。`.data` 则由下载器直接写入 DRAM，启动文件没有从 ROM 搬运数据的循环。

不要沿用另一份 cache 测试中写死的 `sp = 0x80020000`；当前工程使用 `__stack_top = 0x80008000`。也不要把自带 `_start` 的 C 文件与 `platform/start.S` 同时链接，否则会出现重复入口。

## 6. 生成结果与检查方法

所有构建结果在 `build/led_uart/`，该目录已被工程 `.gitignore` 忽略。

| 文件 | 用途 |
| --- | --- |
| `start.o`、`led_uart.o` | 编译产生的中间目标文件 |
| `led_uart.elf` | 含地址、符号和调试信息的完整程序 |
| `led_uart.map` | 链接器生成的布局说明 |
| `imem.raw.bin` | IRAM 原始指令镜像 |
| `dmem.raw.bin` | DRAM 原始数据镜像 |
| `imem.flash.bin` | 指令镜像重排后的下载帧，前导码为 `C0 C0 C0 C0` |
| `dmem.flash.bin` | 数据镜像重排后的下载帧，前导码为 `D0 D0 D0 D0` |
| `program.lst` | 反汇编及可用的源码对应信息 |
| `elf-info.txt` | ELF 文件概要、节表、符号表，由 llvm-objdump 生成 |

查看报告：

```bash
less build/led_uart/elf-info.txt
less build/led_uart/program.lst
less build/led_uart/led_uart.map
```

重点确认 ELF 为 ELF32、RISC-V、小端；入口为 `0x0`；`_start` 位于 `0x00000000`，`.data` 位于 `0x80000000`，`__stack_top` 为 `0x80008000`。反汇编应先执行设置 SP/GP、清零 BSS 的启动逻辑，再调用 `main`。具体代码大小和指令排列可能随 LLVM 版本变化。

链接脚本会检查代码容量以及数据/BSS 是否侵入预留栈空间，但不会检查程序运行时的栈使用是否超出 4 KiB。

**必须分段提取镜像。** 不要对整个 ELF 直接执行不带 `--only-section` 的二进制提取：代码和数据地址相隔 `0x80000000`，可能产生巨大的填充文件。`llvm-objcopy` 的提取参数见 [官方文档](https://llvm.org/docs/CommandGuide/llvm-objcopy.html)，反汇编参数见 [llvm-objdump 文档](https://llvm.org/docs/CommandGuide/llvm-objdump.html)。

## 7. 编译完成后怎样下载

下载使用最后一步生成的两个 `*.flash.bin`。`bin2pqr5bin.py` 将每四字节反序（例如 `13 00 00 00` 变为 `00 00 00 13`），不足四字节时先补零，再添加前导码、长度、偏移和结束码。它不改变指令之间的顺序，也不反转整个文件。

两次转换的 `-baseaddr` 均为 `0`，表示各自 RAM 内的字节偏移。CPU 数据地址 `0x80000000` 与 loader 的 DRAM 地址 `0x10000000` 是不同接口的地址映射，不能填入此参数；不需要修改 C 指针或链接脚本。原版脚本只检查地址对齐，不检查 32 KiB 容量；当前链接脚本负责程序布局的容量检查。协议头尾额外占 16 字节，不写入 RAM。

保留原版 `bin2pqr5bin.py`：它没有 `-memtype` 选项，固定生成 `C0 C0 C0 C0` 帧头。因此上面的 Bash 命令在转换数据镜像后，只把生成文件的前四字节改为 `D0 D0 D0 D0`，不修改 Python 脚本或正文。

**当前下载仍有缺失依赖：** 保留原版 `peqflash.py` 后，它仍导入 `pack_flash.py`，而工程中未提供该文件，连 `--help` 也会因此失败。下面的下载命令以补齐原有依赖为前提；编译和重排不受影响。

下载工具在完整仓库中，截图里的 `led_test` 目录尚未包含它。安装 `pyserial` 后，将两个 `*.flash.bin` 复制到完整仓库的 `build/led_uart/`，再在仓库根目录执行（串口名按实际修改）：

```bash
python3 python_tools/peqflash.py \
    -serport /dev/ttyUSB0 -baud 115200 \
    -imembin build/led_uart/imem.flash.bin \
    -dmembin build/led_uart/dmem.flash.bin \
    --monitor-port /dev/ttyUSB1 --monitor-baud 115200
```

**这里不加 `--raw`**，因为文件已经重排并封装，再加会重复处理。连接与 Python 环境配置见 [README 的下载说明](README.md#7-串口下载和独立打印)。

## 8. 常见错误

| 现象 | 检查方法 |
| --- | --- |
| `clang`、`ld.lld` 等找不到 | 安装对应包，或设置工具变量为实际路径/带版本号的名称 |
| 找不到与目标匹配的后端 | 检查 `clang --print-targets` 是否包含 `riscv32` |
| 生成的是 x86 / ARM 文件 | 检查编译启动文件和 C 文件时是否都带了 `--target` |
| `undefined symbol: main` | 当前 `start.S` 调用 `main`，C 程序必须提供该函数 |
| `duplicate symbol: _start` | C 文件与启动汇编重复定义了入口，只保留一份启动实现 |
| 找不到 `__stack_top`、`__bss_start` 等符号 | 检查是否使用 `-T linker.ld`，且该文件内容与仓库的 `platform/link.ld` 一致 |
| 找不到 `platform/start.S` | 使用本节平铺目录命令中的 `start.s`；Linux 文件名区分大小写 |
| `undefined symbol: printf`、`memcpy` 或运算辅助函数 | 程序产生了本工程未提供的运行库调用，需实现或链接匹配的裸机运行库 |
| IRAM / DRAM 容量断言失败 | 查看 `.map` 中代码、数据和 BSS 大小，按实际硬件容量调整程序 |
| 下载提示 `invalid frame` | 确认使用重排后的 `*.flash.bin`，IMEM/DMEM 类型对应，且未加 `--raw` |
| `pack_flash` 模块找不到 | 当前下载脚本缺少原有依赖；编译和重排成功不代表下载依赖已补齐 |

本文命令已按当前源文件、启动文件和链接脚本核对。编写环境中未发现可直接调用的 LLVM 工具，因此未实际执行 Linux 编译，也未进行仿真或上板验证。
