module top_uart#(
    parameter clk_freq = 100_000_000,
    parameter uart_bps = 115200 
)
(
    input  sys_clk,
    input  sys_rst_n,

    input  uart_rxd,
    output uart_txd,

    input uart_tx_en,
    input uart_rx_en,

    input [7:0] uart_tx_data,//从loader出来的发给上位机的数据
    input  uart_tx_valid,//高电平表示当前loader给uart接收模块的数据有效
    output uart_tx_ready,//表示当前可以从loader接收数据

    output [7:0] uart_rx_data,//把上位机得到的rx数据给loader
    output uart_rx_valid,//表示读到的数据有效
    input  uart_rx_ready,//表示loader准备好接收信号

    output o_frame_err//帧错误信号

);


//输入模块例化
uart_tx #(
    .uart_bps (uart_bps),
    .clk_freq (clk_freq)
)u_uart_tx(
    .clk            (sys_clk),
    .rst_n          (sys_rst_n),
    .uart_tx_en     (uart_tx_en),
    .uart_tx_data   (uart_tx_data),
    .uart_tx_valid  (uart_tx_valid),
    .uart_tx_ready  (uart_tx_ready),
    .uart_txd       (uart_txd)
    );  

//输入模块例化
uart_rx #(
    .uart_bps (uart_bps),
    .clk_freq (clk_freq)
)u_uart_rx(
    .clk          (sys_clk),
    .rst_n        (sys_rst_n),
    .uart_rxd     (uart_rxd),
    .uart_rx_en   (uart_rx_en),
    .uart_rx_data (uart_rx_data),
    .uart_rx_valid(uart_rx_valid),
    .uart_rx_ready(uart_rx_ready),
    .o_frame_err  (o_frame_err)
);

endmodule