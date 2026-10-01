`include "define.sv"

//mem阶段不做数据源写回的判断
//把算出来的地址拆成前两位和后面的，后面的负责在bram找32位的字，低两位负责找是32位里面的哪个字节
module mem(
    input clk,
    input rst_n,

    input                reg_we_i,//写回寄存器使能信号，直接给wb
    input [`RegAddrBus]  rd_i,//写回寄存器地址
    input [`WbSelBus]    wb_sel_i,//写回数据源选择

    input [`RegBus]      alu_result_i,//alu计算出的数据结果或地址,
    input [`RegBus]      store_data_i,//要存入mem的数据

    input                mem_re_i,//读存储器使能
    input                mem_we_i,//写存储器使能
    input [`MemOpBus]    mem_op_i,//判断是对存储器做声明操作

    input [`InstAddrBus] pc_plus4_i,//pc+4的地址
    input                fence_i,

    //是否是load指令标志
    input                load_flag_i,

    //ex得到的计算数据/地址直接给wb
    output [`RegBus]      alu_result_o,
    output [`InstAddrBus] pc_plus4_o,
    output [`RegAddrBus]  rd_o,
    output reg_we_o,

    //读出的数据
    output reg [`DataBus] mem_data_o,

    //写回数据源选择
    output [`WbSelBus] wb_sel_o,

    //load指令标志
    output load_flag_o,

    output fence_o,

    //当前整条load/store指令的MEM阶段结果，可以被MEM/WB接收，并且EX/MEM可以向前更新
    input mem_accept_i,

    //外部loader先写到dmem里面的初始数据
    // 写信号
    output                    mem_req_valid,
    input                     mem_req_ready,
    output reg [`InstAddrBus] mem_req_addr,//根据pc往mem（ddr）里面找相应地址的数据
    output reg [31:0]         mem_req_wdata,
    output reg [3:0]          mem_req_wstrb,
    output reg                mem_req_write,// 0表示读DDR，1表示写DDR

    // 读信号
    input              mem_rsp_valid,
    input   [`DataBus] mem_rsp_rdata,

    output mem_req_o,//时序读，所以读的时候流水线stall拉高，等握手完成

    //给tx端串口打印结果
    output [`ByteWidth] dbg_uart_tx_data,
    output dbg_uart_tx_valid,
    input  dbg_uart_tx_ready,

    //b通道返回的信号
    input  dbg_rsp_valid,
    output dbg_rsp_ready,
    input  dbg_rsp_error,

    output debug_load_start,
    output [`DataBus] debug_read_word,

    // MEM -> MMIO bridge
    output                        mmio_req_valid,
    input                         mmio_req_ready,
    output reg [`DataAddrBus]     mmio_req_addr,
    output reg [`DataBus]         mmio_req_wdata,
    output reg [3:0]              mmio_req_wstrb,
    output reg                    mmio_req_write,

    // MMIO bridge -> MEM
    input                     mmio_rsp_valid,
    output                    mmio_rsp_ready,
    input  [`DataBus]         mmio_rsp_rdata

);

//状态机状态定义，管理完整的一次取指事务
localparam MEM_IDLE = 2'd0;//发现load/store，锁存地址、数据、mem_op
localparam MEM_REQ  = 2'd1;//保持valid，等待仲裁器ready
localparam MEM_WAIT = 2'd2;//请求已经发送，等待DDR响应
localparam MEM_HOLD = 2'd3;//响应数据准备好，解除stall，让MEM/WB接收

reg [1:0] state;
reg [1:0] next_state;

//wb要的信号直接接
assign alu_result_o = alu_result_i;
assign pc_plus4_o = pc_plus4_i;
assign rd_o = rd_i;
assign wb_sel_o = wb_sel_i;
assign load_flag_o = load_flag_i;
assign fence_o = fence_i;
assign reg_we_o = reg_we_i;

wire is_uart_tx_write;//判断是往mem里面写还是通过串口显示处理后的结果
wire is_mmio_access;
assign is_uart_tx_write = mem_we_i && (alu_result_i == `UART_TX_ADDR);//拉高表示是往tx发送数据
assign is_mmio_access =
    (mem_re_i || mem_we_i) &&
    //通过前16位判断是不是mmio地址
    ((alu_result_i & `MMIO_ADDR_MASK) == `MMIO_BASE_ADDR) &&
    !is_uart_tx_write;

reg [`ByteWidth] selected_byte;//32位字中，第几个字节
reg [15:0] selected_half;//前两个字节

reg [`DataBus] store_wdata;//mem阶段存储写入的数据
reg [3:0]  store_wstrb;//mem阶段存储哪个字节有效
reg [1:0]  req_offset;//读出128b的偏移量

reg [`DataBus] rsp_rdata;//从ddr中读出的数据锁存
reg         mem_re_d0;//读请求使能信号锁存
reg [`MemOpBus] mem_op_d0;//锁存mem_op

reg is_mmio;//判断是否是mmio的状态锁存
reg is_uart;//判断是否是uart的状态锁存
reg [`ByteWidth] uart_data;

//每执行一条访问 DDR 的 load/store 指令，流水线暂停一次；整个 DDR 事务完成后恢复一次
assign mem_req_o = ((state == MEM_IDLE) && (mem_re_i || mem_we_i)) || (state == MEM_REQ)  || (state == MEM_WAIT);

//把数据接出去
assign dbg_uart_tx_data = uart_data;//要存的数据但是地址到uart之后
assign dbg_uart_tx_valid = is_uart && state == MEM_REQ;
assign debug_read_word  = rsp_rdata;
assign debug_load_start = (state == MEM_IDLE) && mem_re_i;
assign dbg_rsp_ready = (state == MEM_WAIT) && is_uart;//每次等到响应才进hold

assign mem_req_valid = (state == MEM_REQ) && !is_uart && !is_mmio;
assign mmio_req_valid = (state == MEM_REQ) && is_mmio;
assign mmio_rsp_ready = (state == MEM_WAIT) && is_mmio;//每次等到响应才进hold

//第一段状态机
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= MEM_IDLE;
    end
    else begin
        state <= next_state;
    end
end

//第二段判断跳转
always @(*) begin
    next_state = state;
    case (state)
        MEM_IDLE: begin
            if (mem_re_i || mem_we_i) begin// 空闲：等待允许取指
                next_state = MEM_REQ;
            end
        end
        MEM_REQ: begin
            if ((mem_req_valid && mem_req_ready) || (dbg_uart_tx_valid && dbg_uart_tx_ready && is_uart) || (mmio_req_valid && mmio_req_ready)) begin
                next_state = MEM_WAIT;
            end
        end
        MEM_WAIT: begin
            if ((!is_uart && !is_mmio && mem_rsp_valid) || (dbg_rsp_ready && dbg_rsp_valid && is_uart) || (is_mmio && mmio_rsp_valid && mmio_rsp_ready)) begin
                next_state = MEM_HOLD;
            end
        end
        MEM_HOLD: begin
            //确保流水线不是暂停状态
            if (mem_accept_i) begin
                next_state = MEM_IDLE;
            end
        end
        default: begin
            next_state = MEM_IDLE;
        end
    endcase
end

//第三段状态机只锁存请求和响应
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        mem_req_write  <= 1'b0;
        mem_req_addr   <= 32'b0;
        mem_req_wdata  <= 32'b0;
        mem_req_wstrb  <= 'd0;

        rsp_rdata      <= 'd0;
        mem_re_d0      <= 'd0;

        mem_op_d0     <= `MEM_NONE;
        req_offset <= 'd0;//alu算出来的后四位，判断是128b中的哪个字写入

        is_uart <= 'd0;
        uart_data <= 'd0;
        is_mmio <= 1'b0;

        mmio_req_addr  <= 'd0;
        mmio_req_wdata <= 'd0;
        mmio_req_wstrb <= 'd0;
        mmio_req_write <= 1'b0;
    end
    else begin 
        if( (mem_re_i || mem_we_i) && (!is_uart_tx_write && !is_mmio_access) && (state == MEM_IDLE))begin//state == MEM_IDLE时候锁存，req握手成功后直接拿

            mem_req_write  <= mem_we_i ? 1'b1 : 1'b0;
            mem_req_addr   <= alu_result_i;//地址[3:2]：告诉Controller写128位中的哪个32位通道,前28位判断
            mem_req_wdata  <= store_wdata;
            mem_req_wstrb  <= mem_we_i ? store_wstrb : 4'b0000;

            mem_op_d0      <= mem_op_i;
            req_offset     <= alu_result_i[1:0];
            mem_re_d0      <= mem_re_i;
            is_uart        <= 'd0;
            is_mmio         <= 'd0;
        end
        else if (is_uart_tx_write && (state == MEM_IDLE))begin
            uart_data <= store_data_i[7:0];
            is_uart   <= is_uart_tx_write;
            is_mmio    <= 'd0;
            mem_re_d0 <= 1'b0;
        end
        else if(is_mmio_access && (state == MEM_IDLE))begin
            is_mmio  <= 1'b1;
            is_uart <= 'd0;

            mmio_req_addr  <= alu_result_i;
            mmio_req_write <= mem_we_i;
            //storedata和storewstrb是组合逻辑，一进来就拼好了，这里可以直接锁存
            mmio_req_wdata <= mem_we_i ? store_wdata : 32'b0;
            mmio_req_wstrb <= mem_we_i ? store_wstrb : 4'b0000;

            mem_re_d0      <= mem_re_i;
            mem_op_d0      <= mem_op_i;
            req_offset     <= alu_result_i[1:0];
        end
        // DDR响应到达时，保存输入数据
        if ((state == MEM_WAIT) && mem_rsp_valid && !is_mmio && !is_uart) begin
            rsp_rdata <= mem_rsp_rdata;
            mmio_req_write <= 1'b0;
        end
        else if((state == MEM_WAIT) && is_mmio &&  mmio_rsp_valid && mmio_rsp_ready && mem_re_d0) begin
            rsp_rdata <= mmio_rsp_rdata;
            mmio_req_write <= 1'b0;
        end
        if (state == MEM_HOLD && mem_accept_i) begin
            is_mmio        <= 1'b0;
            is_uart        <= 1'b0;
            mmio_req_write <= 1'b0;
        end
    end
end

//根据打拍后的字内索引（最低两位），选择32位字中的字节
always @(*)begin
    selected_byte = rsp_rdata[7:0];//初始化
    case(req_offset[1:0])
        0: selected_byte = rsp_rdata[7:0];
        1: selected_byte = rsp_rdata[15:8];
        2: selected_byte = rsp_rdata[23:16];
        3: selected_byte = rsp_rdata[31:24];
    endcase
end

//半字索引
always @(*)begin
    selected_half = 'd0;//初始化
    case(req_offset[1:0])
        0: selected_half = rsp_rdata[15:0];
        2: selected_half = rsp_rdata[31:16];
    endcase
end

//load是先锁存再拼接，store是先拼接再锁存
//Load的数据来自未来的DDR响应，所以只能先保存地址和操作类型，等响应回来再处理
//Store的数据现在已经由CPU提供，所以可以先根据 SB/SH/SW 和地址偏移摆放好，再锁存并发送
//l指令
//给 mem_data_o 默认值，避免锁存器
always @(*) begin
    // 无条件默认值，避免锁存器
    mem_data_o = `ZeroWord;

    // 使用延迟一拍后的读有效信号
    if (mem_re_d0 && state == MEM_HOLD) begin
        case (mem_op_d0)

            // 字节符号扩展
            `MEM_LB: begin
                mem_data_o = {
                    {24{selected_byte[7]}},
                    selected_byte
                };
            end

            // 字节零扩展
            `MEM_LBU: begin
                mem_data_o = {
                    24'b0,
                    selected_byte
                };
            end

            // 半字符号扩展，只支持自然对齐
            `MEM_LH: begin
                if (req_offset[0] == 1'b0) begin
                    mem_data_o = {
                        {16{selected_half[15]}},
                        selected_half
                    };
                end
            end

            // 半字零扩展，只支持自然对齐
            `MEM_LHU: begin
                if (req_offset[0] == 1'b0) begin
                    mem_data_o = {
                        16'b0,
                        selected_half
                    };
                end
            end

            // 32位字，只支持4字节对齐
            `MEM_LW: begin
                if (req_offset[1:0] == 2'b00) begin
                    mem_data_o = rsp_rdata;
                end
            end

            default: begin
                mem_data_o = `ZeroWord;
            end
        endcase
    end
end

//s指令在锁存前做好拼接，拼完再锁存
always @(*) begin
    store_wdata = `ZeroWord;
    store_wstrb = 4'b0000;

    if (mem_we_i) begin
        case (mem_op_i)

            //判断是写入的这个32位字的哪个字节
            `MEM_SB: begin
                case (alu_result_i[1:0])
                    2'd0: begin
                        store_wdata[7:0] = store_data_i[7:0];
                        store_wstrb = 4'b0001;
                    end

                    2'd1: begin
                        store_wdata[15:8] = store_data_i[7:0];
                        store_wstrb = 4'b0010;
                    end

                    2'd2: begin
                        store_wdata[23:16] = store_data_i[7:0];
                        store_wstrb = 4'b0100;
                    end

                    2'd3: begin
                        store_wdata[31:24] = store_data_i[7:0];
                        store_wstrb = 4'b1000;
                    end
                endcase
            end

            //拒绝奇数地址，只有0011，1100
            `MEM_SH: begin
                case (alu_result_i[1:0])
                    2'd0: begin
                        store_wdata[15:0] = store_data_i[15:0];
                        store_wstrb = 4'b0011;
                    end

                    2'd2: begin
                        store_wdata[31:16] = store_data_i[15:0];
                        store_wstrb = 4'b1100;
                    end

                    default: begin
                        store_wstrb = 4'b0000;
                    end
                endcase
            end

            //全给
            `MEM_SW: begin
                if (alu_result_i[1:0] == 2'b00) begin
                    store_wdata = store_data_i;
                    store_wstrb = 4'b1111;
                end
            end

            default: begin
                store_wdata = `ZeroWord;
                store_wstrb = 4'b0000;
            end
        endcase
    end
end

endmodule
