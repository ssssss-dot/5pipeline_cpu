//包含头文件
`include "define.sv"

//存储指令的存储器,根据pc地址读指令
module inst_ram(
    input clk,
    input rst_n,

    input [`InstAddrBus] curr_pc,
    output reg [`InstAddrBus] curr_pc_d1,
    output reg [`InstBus] inst_o,//从ddr取得的指令
    output wire inst_valid_o,//表示ddr给id的指令有效
    input redirect_i,

    //控制读,停止时期拉低，不读
    input cpu_read_en,

    //启动取指令
    input fetch_enable_i,

    // 发往cache的取指请求
    output                      if_req_valid,
    input                       if_req_ready,
    output reg  [`InstAddrBus]  if_req_addr,//根据pc往mem（ddr）里面找相应地址的数据

    // 仲裁器返回的mem数据
    input              if_rsp_valid,
    input   [`InstBus] if_rsp_rdata,

    // 给流水线Ctrl的暂停请求
    output          if_req_o
);

//状态机状态定义，管理完整的一次取指事务
localparam IF_IDLE = 2'd0;//保存PC和请求地址
localparam IF_REQ  = 2'd1;//等仲裁器接收地址
localparam IF_WAIT = 2'd2;//等DDR返回数据
localparam IF_HOLD = 2'd3;//等IF/ID接收指令

reg [1:0] state;
reg [1:0] next_state;

//redirect发生
//├─ PC立即跳转
//├─ 流水线错误指令立即清除
//└─ DDR旧请求继续执行，但设置discard_q=1,DDR收到请求后仍会返回数据，因为请求已经发送，无法从DDR内部撤回，因此用discard_q=1表示当时得到的数据错误，要清除
reg discard_q;

//开始一次取指
wire start_fetch;
assign start_fetch = (state == IF_IDLE) && fetch_enable_i && !redirect_i;//表示这个周期开始取指令
//state == IF_IDLE总线空闲
//fetch_enable loader完成，可以取指令
//redirect_i=1表示当前取指路径错了，PC将在这个时钟沿跳转到新的目标地址。此时不能再用旧curr_pc发起DDR请求

// REQ期间一直保持valid，直到仲裁器ready
// redirect发生时撤销尚未握手的请求
assign if_req_valid = (state == IF_REQ) && !redirect_i;

// HOLD表示指令和PC已经准备好
assign inst_valid_o = (state == IF_HOLD) && !redirect_i;

//在cpu向ddr读指令的 idle req wait状态都要暂停流水线，直到hold得到了inst_o
//redirect不停流水线，默认不跳，等ex计算完是否要跳
//!fetch_enable_i,Loader还没有完成，CPU不能运行
assign if_req_o = rst_n && (state == IF_IDLE || state == IF_REQ || state == IF_WAIT || !fetch_enable_i);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        discard_q <= 1'b0;
    end
    else begin
        // 仲裁器接收了一个新的取指请求
        // 默认这个请求是有效路径
        if (state == IF_REQ && if_req_ready && if_req_valid) begin
            discard_q <= 1'b0;
        end

        // 请求已经发出，等待期间发生跳转
        // 该请求对应的旧PC已经失效
        //当前正在等待一个已经发出的ICache响应，
        //本周期发生了跳转，
        //并且旧icache响应本周期还没有回来，旧icache响应包含的是跳转前错误路径上的指令
        else if (state == IF_WAIT && redirect_i && !if_rsp_valid) begin
            discard_q <= 1'b1;
        end

        // 旧响应已经返回并被处理
        else if (state == IF_WAIT && if_rsp_valid) begin
            discard_q <= 1'b0;
        end
    end
end

//第一段状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IF_IDLE;
    end
    else begin
        state <= next_state;
    end
end

//第二段判断跳转
always @(*) begin
    next_state = state;
    case (state)
        IF_IDLE: begin
            if (fetch_enable_i && !redirect_i) begin// 空闲：等待允许取指
                next_state = IF_REQ;
            end
        end
        IF_REQ: begin
            if (redirect_i) begin
                //有分支跳转，放弃旧PC
                next_state = IF_IDLE;
            end
            else if (if_req_valid && if_req_ready) begin// ready/valid握手成功
                next_state = IF_WAIT;
            end
        end
        IF_WAIT: begin
            if (if_rsp_valid) begin
                if (discard_q || redirect_i) begin
                    // 请求属于错误路径，返回数据丢弃
                    next_state = IF_IDLE;
                end
                else begin
                    // 正常响应，保存指令
                    next_state = IF_HOLD;
                end
            end
        end
        IF_HOLD: begin
            if (cpu_read_en || redirect_i) begin
                next_state = IF_IDLE;
            end
        end
    endcase
end

//第三段
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        curr_pc_d1 <= 'd0;
        if_req_addr <= 'd0;
        inst_o <= 'd0;
    end
    else begin 
        case (state) 
            IF_IDLE: begin
                //idle状态，锁存PC
                if (start_fetch) begin
                    if_req_addr <= curr_pc;
                    curr_pc_d1 <= curr_pc;
                end
            end
            //ddr返回数据
            IF_WAIT: begin
                // 只保存正常路径的DDR响应
                if (if_rsp_valid && !discard_q && !redirect_i) begin
                    inst_o <= if_rsp_rdata;
                end
            end
        endcase
    end
end

endmodule