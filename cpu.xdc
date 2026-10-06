# cpu_loader_top 板级约束
# 保留原有引脚位置和电气标准，只统一当前顶层端口名。

# 差分输入时钟：100 MHz，与顶层默认 CLK_FREQ=100_000_000 对应。
create_clock -name sys_clk -period 10.000 -waveform {0.000 5.000} [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_HSTL_I_12 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_HSTL_I_12 [get_ports sys_clk_n]
set_property PACKAGE_PIN AE5 [get_ports sys_clk_p]
set_property PACKAGE_PIN AF5 [get_ports sys_clk_n]

# 系统低有效复位
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports rst_n]

# loader 下载串口
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports uart_txd]

# 独立 CPU 打印串口（旧名称 dbg_uart_txd 改为 cpu_uart_txd）
set_property -dict {PACKAGE_PIN E12 IOSTANDARD LVCMOS33} [get_ports cpu_uart_txd]

# pl_led1、pl_led2
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports {led[1]}]