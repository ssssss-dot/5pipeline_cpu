//控制暂停和冲刷信号的产生
module Ctrl(
    input wire rst_n,

    input wire if_req,
    input wire id_req,
    input wire ex_req,
    input wire mem_req,

    //ex阶段产生的，由pc的分支跳转决定是否要冲刷
    input wire redirect_i,   // branch/jal/jalr 确认要改PC
    //中断异常信号，可以先不管，置为0
    input wire except_i,     // 异常/中断，产生，要冲刷两条指令

    output reg [5:0] stall,
    output reg flush_if_id,
    output reg flush_id_ex,
    output reg flush_ex_mem,
    output reg flush_mem_wb,

    //loader给的外部全流水线暂停信号
    input i_loader_stall
);

always @(*) begin
    stall       = 6'b000000;
    flush_if_id = 1'b0;
    flush_id_ex = 1'b0;
    flush_ex_mem= 1'b0;
    flush_mem_wb= 1'b0;

    if (!rst_n) begin
        stall       = 6'b000000;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;
        flush_ex_mem= 1'b0;
        flush_mem_wb= 1'b0;
    end
    else if (i_loader_stall)begin
        stall = 6'b111111;
    end
    else if (except_i) begin
        // 中断/异常时通常前面几级都冲掉
        stall       = 6'b000000;
        flush_if_id = 1'b1;
        flush_id_ex = 1'b1;
        flush_ex_mem= 1'b1;
        flush_mem_wb= 1'b0;
    end
    else if (mem_req) begin
        stall = 6'b011111;
    end
    //处理控制冒险（分支，跳转改了pc，将已经给出的指令冲刷掉）
    //redirect比if_req更优先，防止if_req先暂停，redirect无法更新
    else if (redirect_i) begin
        // branch/jal/jalr 改PC后，冲掉错误路径上的前级指令
        flush_if_id = 1'b1;
        flush_id_ex = 1'b1;
    end
    else if (ex_req) begin
        stall = 6'b001111;
    end
    else if (id_req) begin//数据冒险，数据还没更新
        stall = 6'b000011;//停前两级
        flush_id_ex = 1'b1;//给 EX 插一个 bubble（等一拍等真正需要的数据来）
    end
    else if (if_req) begin
        stall = 6'b000001;//if_id不暂停，防止一条指令被执行多次
    end
end

endmodule