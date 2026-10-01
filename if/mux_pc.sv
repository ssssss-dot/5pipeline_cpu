//包含头文件
`include "define.sv"

//根据下一条指令判断当前next_pc的地址，判断和2立即数加放到ex中，这里只取nextpc
module mux_pc(
    input stall_i,//流水线暂停信号
    input redirect_i,//拉高标志着需要跳转
    input [`InstAddrBus] redirect_pc_i,//在ex中计算完成的跳转地址，直接给到nextpc
    input [`InstAddrBus] curr_pc,
    output reg [`InstAddrBus] next_pc//单周期在组合逻辑里面判断
);

//根据指令给next_pc赋值
always @(*)begin
    if(redirect_i)begin
        next_pc = redirect_pc_i;
    end
    else if(stall_i)begin
        next_pc = curr_pc;
    end
    else begin
        next_pc = curr_pc + 'd4;
    end
end
endmodule