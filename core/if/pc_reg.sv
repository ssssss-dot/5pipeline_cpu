`include "define.sv"

//指令地址存储寄存器，输出下一个状态的地址以及系统使能信号（分支跳转和判断放到mux_pc里面去）
module pc_reg(
    input clk,//系统时钟
    input rst_n,
    input [`InstAddrBus] next_pc,//根据mux_pc的指令
    output reg [`InstAddrBus] curr_pc//下一个地址
);

//根据时钟将mux判断后的下一个pc地址给currpc
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        curr_pc <= 'd0;
    end
    else begin
        curr_pc <= next_pc;
    end
end
endmodule