module uart_tx(
    input             clk,
    input             rst_n,
    input             uart_tx_en,
    input      [7:0]  uart_tx_data,//接收到的txdata
    input             uart_tx_valid,
    output reg        uart_tx_ready,
    output reg        uart_txd//把需要的txdata发给上位机
);
//常数定义
parameter uart_bps   = 115200;
parameter clk_freq = 100000000;
localparam baud_cnt_max = clk_freq/uart_bps;

//reg定义
reg  [15:0]  baud_cnt;//波特率计数器，数满一次 = 发送下一个串口 bit
reg  [4:0]   tx_cnt;//发送位计数器记录发送到uart的第几位
reg  [7:0]   tx_data_t;//发送缓存
reg          tx_busy;//发送总线线忙信号,在握手那一拍持续拉高

wire tx_done;//tx完成信号

assign tx_done = tx_busy && (tx_cnt == 5'd9) && (baud_cnt == baud_cnt_max - 1'b1);
//数据输入tx_data_t,uart_tx_ready信号产生
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        tx_data_t <= 1'b0;
        uart_tx_ready <= 1'b1;
        tx_busy <= 1'b0;
    end
    else if(uart_tx_en && uart_tx_valid && uart_tx_ready) begin//握手信号拉高一拍
        tx_data_t <= uart_tx_data;
        uart_tx_ready <= 1'b0;//握手一拍，后面ready拉低
        tx_busy <= 1'b1;//busy拉高表示后面要开始传数据，总线忙
    end
    else if (tx_done) begin//一个字节发完了，busy拉低
        tx_data_t <= tx_data_t;
        uart_tx_ready <= 1'b1;
        tx_busy <= 1'b0;
    end
    else begin
        tx_data_t <= tx_data_t;
        uart_tx_ready <= uart_tx_ready;
    end
end

//baud_cnt计数,~uart_txd_ready表示tx线上正在传输数据，根据tx_cnt把数据塞过去
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) 
        baud_cnt <= 1'b0;
    else if (tx_busy && (baud_cnt < baud_cnt_max - 1'b1))
        baud_cnt <= baud_cnt + 1'b1;
    else if (tx_busy && (baud_cnt == baud_cnt_max - 1'b1))
        baud_cnt <= 1'b0;
    else   
        baud_cnt <= 1'b0;
end

//tx_cnt计数
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        tx_cnt <= 1'b0;
    else if (tx_done)
        tx_cnt <= 1'b0;
    else if(tx_busy && baud_cnt == baud_cnt_max - 1'b1)
        tx_cnt <= tx_cnt + 1'b1;
end

//根据 tx_cnt 来给 uart 发送端口赋值
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        uart_txd <= 1'b1;
    else if(tx_busy) begin//总线上传输数据忙
        case (tx_cnt)
            5'd0   :   uart_txd <= 1'b0;
            5'd1   :   uart_txd <= tx_data_t[0];
            5'd2   :   uart_txd <= tx_data_t[1];
            5'd3   :   uart_txd <= tx_data_t[2];
            5'd4   :   uart_txd <= tx_data_t[3];
            5'd5   :   uart_txd <= tx_data_t[4];
            5'd6   :   uart_txd <= tx_data_t[5];
            5'd7   :   uart_txd <= tx_data_t[6];
            5'd8   :   uart_txd <= tx_data_t[7];
            5'd9   :   uart_txd <= 1'b1;
            default: ;
        endcase
    end
    else 
        uart_txd <= 1'b1;
end

endmodule