`include "define.sv"

module csr_file(
    input wire clk,
    input wire rst_n,

    // EX读取CSR旧值
    input  wire [`CsrAddrBus] raddr_i,
    output reg  [`CsrDataBus] rdata_o,

    // WB提交CSR新值
    input wire                wb_we_i,
    input wire [`CsrAddrBus]  wb_waddr_i,
    input wire [`CsrDataBus]  wb_wdata_i,

    //raddr_i和wb_waddr_i是一个地址，先在ex阶段取旧值，之后再在wb阶段写新的值

    // DMA外部中断
    input wire dma_irq_i,

    // CPU确认接受中断
    input wire                trap_enter_i,//标志cpu正式进入中断
    input wire [`InstAddrBus] trap_pc_i,//中断产生会冲刷两条指令，记录被冲刷的pc（被冲刷的后面还要执行）

    // 执行mret
    input wire mret_i,

    // 输出给CPU控制逻辑
    output wire [`InstAddrBus] mtvec_o,
    output wire [`InstAddrBus] mepc_o,
    output wire                irq_request_o//通过内部寄存器和外部dma的中断给cpu的中断请求
);

// CSR寄存器
reg [`CsrDataBus] csr_mstatus;//保存 CPU 的机器模式状态，主要用3，7，11，12位
reg [`CsrDataBus] csr_mie;//中断使能，11位决定是否使能中断
reg [`CsrDataBus] csr_mtvec;//保存中断处理程序入口
reg [`CsrDataBus] csr_mepc;//保存中断发生前的pc
reg [`CsrDataBus] csr_mcause;//保存中断发生原因，赋值：32'h8000_000B
wire [`CsrDataBus] csr_mip;//看11位，接dma的外部中断

//cpu中断请求
//CPU全局允许中断并且允许机器外部中断并且DMA正在请求中断
assign irq_request_o = csr_mstatus[`MSTATUS_MIE_BIT] && csr_mie[`MIE_MEIE_BIT] && csr_mip[`MIP_MEIP_BIT];

assign csr_mip = {
    20'd0,
    dma_irq_i,  // mip[11]
    11'd0
};
assign mtvec_o = csr_mtvec;
assign mepc_o = csr_mepc;

//寄存器更新
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        csr_mstatus <= `ZeroWord;
        csr_mie <= `ZeroWord;
        csr_mtvec <= `ZeroWord;
        csr_mepc <= `ZeroWord;
        csr_mcause <= `ZeroWord;
    end
    //进入中断
    else if (trap_enter_i) begin
        csr_mepc <= {trap_pc_i[31:2] , 2'b00};
        csr_mcause <= `MCAUSE_MACHINE_EXTERNAL_IRQ;//原因是外部dma
        csr_mstatus[`MSTATUS_MPIE_BIT] <= csr_mstatus[`MSTATUS_MIE_BIT];//保存全局中断使能状态
        csr_mstatus[`MSTATUS_MIE_BIT] <= 1'b0;//关闭全局中断
        csr_mstatus[`MSTATUS_MPP] <= `PRIV_MODE_M;// 当前CPU只运行M模式
    end

    //mret
    else if (mret_i) begin
        csr_mstatus[`MSTATUS_MIE_BIT] <= csr_mstatus[`MSTATUS_MPIE_BIT];
        csr_mstatus[`MSTATUS_MPIE_BIT] <= 1'b1;
    end

    //写入时地址对齐
    else if (wb_we_i) begin
        case(wb_waddr_i)
            `CSR_MSTATUS: csr_mstatus <= wb_wdata_i;
            `CSR_MIE: csr_mie <= wb_wdata_i;
            `CSR_MTVEC: csr_mtvec <= {wb_wdata_i[31:2], 2'b00};
            `CSR_MEPC: csr_mepc <= {wb_wdata_i[31:2], 2'b00};
            `CSR_MCAUSE: csr_mcause <= wb_wdata_i;
        endcase
    end

end

always @(*) begin
    case (raddr_i)
        `CSR_MSTATUS: rdata_o = csr_mstatus;
        `CSR_MIE:     rdata_o = csr_mie;
        `CSR_MTVEC:   rdata_o = csr_mtvec;
        `CSR_MEPC:    rdata_o = csr_mepc;
        `CSR_MCAUSE:  rdata_o = csr_mcause;
        `CSR_MIP:     rdata_o = csr_mip;

        default:      rdata_o = `ZeroWord;
    endcase
end

endmodule