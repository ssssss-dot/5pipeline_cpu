module uart_rx(
    input            clk,
    input            rst_n,
    input            uart_rxd,
    input            uart_rx_en,
    input            uart_rx_ready,
    output reg       uart_rx_valid,
    output reg [7:0] uart_rx_data,
    output reg       o_frame_err//表示这一帧传的数据有错
);

//参数
parameter uart_bps   = 115200;
parameter clk_freq = 100000000;
localparam baud_cnt_max = clk_freq/uart_bps;

//reg定义
reg    [4:0] rx_cnt;
reg          uart_rxd_d0;
reg          uart_rxd_d1;
reg          uart_rxd_d2;
reg          rx_busy;
reg    [15:0] baud_cnt;
reg    [7:0] rx_data_t;
wire         start_en;

//取rxd第一个字节的下降沿作为开始传输的信号
//uart_rx_en：rx阶段开始
//(uart_rxd_d2) && (~uart_rxd_d1)：取一帧开始的下降沿
//(~rx_busy)：rx总钱目前没有在传输
//(~uart_rx_valid)：上一帧传完了
assign start_en = uart_rx_en && (uart_rxd_d2) && (~uart_rxd_d1) && (~rx_busy) && (~uart_rx_valid);

//rxd打拍，同步时钟，消除亚稳态
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rxd_d0 <= 1'b1;
        uart_rxd_d1 <= 1'b1;
        uart_rxd_d2 <= 1'b1;
    end
    else begin
        uart_rxd_d0 <= uart_rxd;
        uart_rxd_d1 <= uart_rxd_d0;
        uart_rxd_d2 <= uart_rxd_d1;
    end
end

//rx总线线忙信号产生
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_busy <= 1'b0;
    else if (start_en)
        rx_busy <= 1'b1;
    else if (rx_busy && (baud_cnt == baud_cnt_max/2-1'b1) && (rx_cnt == 5'd9))
        rx_busy <= 1'b0;
    else
        rx_busy <= rx_busy;
end

//baud_cnt计数器
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        baud_cnt <= 16'h0;
    else if (rx_busy && (baud_cnt < baud_cnt_max-1'b1))
        baud_cnt <= baud_cnt + 16'h1;
    else if (baud_cnt == baud_cnt_max-1'b1)
        baud_cnt <= 16'h0;
    else if (~rx_busy)
        baud_cnt <= 16'h0;
end

//rx一个字节数据计数器
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_cnt <= 5'h0;
    else if(rx_busy && baud_cnt == baud_cnt_max-1'b1)
        rx_cnt <= rx_cnt + 5'h1;
    else if(rx_busy)
        rx_cnt <= rx_cnt;
    else
        rx_cnt <= 5'h0;
end

//拼好字节给rxdata传给loader
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        rx_data_t <= 8'h0;
    else if (rx_busy && (baud_cnt == baud_cnt_max/2 - 1'b1)) begin
        case(rx_cnt)
        5'd1: rx_data_t[0] <= uart_rxd_d2;
        5'd2: rx_data_t[1] <= uart_rxd_d2;
        5'd3: rx_data_t[2] <= uart_rxd_d2;
        5'd4: rx_data_t[3] <= uart_rxd_d2;
        5'd5: rx_data_t[4] <= uart_rxd_d2;
        5'd6: rx_data_t[5] <= uart_rxd_d2;
        5'd7: rx_data_t[6] <= uart_rxd_d2;
        5'd8: rx_data_t[7] <= uart_rxd_d2;
        default : ;
        endcase
    end
    else
        rx_data_t <= rx_data_t;
end

//当valid拉高知道检测到ready也拉高的时候握手完成，这一拍传数据，valid清零
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rx_data  <= 8'h0;
        uart_rx_valid <= 1'b0;
    end
    else if (rx_busy && (rx_cnt == 5'd9) && (baud_cnt == baud_cnt_max/2 - 1'b1)) begin
        uart_rx_data <= rx_data_t;
        uart_rx_valid <= uart_rxd_d2;// 停止位为1才valid
    end
    else if(uart_rx_valid && uart_rx_ready)//握手完成
        uart_rx_valid <= 1'b0;
end

//帧错误检测，通过判断最后一位数据是否为1判断这一帧是不是完整，1:完整，0:不完整
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        o_frame_err <= 'd0;
    end
    else if(rx_cnt == 5'd9 && ~uart_rxd_d2 && rx_busy && (baud_cnt == baud_cnt_max/2 - 1'b1))begin//在rx_cnt==9的中点采样
        o_frame_err <= 1'b1;
    end
    else begin
        o_frame_err <= 'd0;
    end
end

endmodule
