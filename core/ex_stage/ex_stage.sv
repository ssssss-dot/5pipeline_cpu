`include "define.sv"

module ex_stage(
    input clk,
    input rst_n,

    // 当前EX阶段指令是否有效
    input wire ex_valid_i,
    // EX/MEM未暂停且未被冲刷时，当前EX指令可以向后级提交
    input wire ex_advance_i,

    // 寄存器地址
    input wire [`RegAddrBus] rs1_i,
    input wire [`RegAddrBus] rs2_i,

    // 目的寄存器地址
    input wire [`RegAddrBus] rd_i,

    // 立即数
    input wire [`RegBus] imm_i,

    // regfile 读/写使能
    input wire re1_i,
    input wire re2_i,
    input wire reg_we_i,

    // 跳转/分支，用来判断redirect_o是否拉高，jal/jalr怎么算
    input wire jump_flag_i,
    input wire branch_flag_i,
    input wire jalr_flag_i,

    // 来自 IF/ID 的 PC 信息
    input wire [`InstAddrBus] pc_i,
    input wire [`InstAddrBus] pc_plus4_i,

    // regfile 读出的数据
    input wire [`RegBus] rs1_data_i,
    input wire [`RegBus] rs2_data_i,

    // MEM / WB 控制
    input wire mem_re_i,
    input wire mem_we_i,
    input wire [`MemOpBus] mem_op_i,
    input wire [`WbSelBus] wb_sel_i,

    // fence
    input wire fence_i,

    // ALU 控制
    input wire [`AluOpBus] aluop_i,
    input wire [`AluSrc1SelBus] alu_src1_sel_i,
    input wire [`AluSrc2SelBus] alu_src2_sel_i,

    output redirect_o,//判断是否有分支跳转信号，需要对前两条指令进行冲刷
    output  [`InstAddrBus] redirect_pc_o,//经过计算后真正要跳转的地址

    // 传给后级的目的寄存器和写回控制
    output [`RegAddrBus] rd_o,//目的寄存器地址
    output reg_we_o,//写寄存器使能信号
    output [`WbSelBus] wb_sel_o,//写回的数据源选择，在wb选真正写回的数据

    //alu/地址运算结果
    output  [`RegBus] alu_result_o,

    // store 要写入 data memory 的数据，一般就是 rs2 的值
    output  [`RegBus] store_data_o,

    // 传给 MEM 级的访存控制
    output mem_re_o,//mem读使能
    output mem_we_o,//mem写使能
    output [`MemOpBus] mem_op_o,//对mem做的操作

    // jal/jalr 后面写回要用 pc+4
    output [`InstAddrBus] pc_plus4_o,

    // 可选：fence 继续往后传
    output  fence_o,

    // 来自 EX/MEM 级的前递信息，从ex_mem流水线寄存器取出（打拍后的信号）
    input wire                 ex_mem_reg_we_i,//写寄存器使能，确定要写回
    input wire [`RegAddrBus]   ex_mem_rd_i,//写回的目的寄存器地址，判断要用的rs1/rs2是不是目的寄存器的还没更新的值
    //必须是最终的写回值，不只是alu_result
    input wire [`RegBus]       ex_mem_forward_result_i,//本次运算的result打一拍的值，写回rd，如果要用，直接通过旁路个下一条指令

    // 来自 MEM/WB 级的前递信息，从mem_wb流水线寄存器取出（打拍后的信号）
    input wire                 mem_wb_reg_we_i,
    input wire [`RegAddrBus]   mem_wb_rd_i,
    input wire [`RegBus]       mem_wb_forward_result_i,

    //判断是否是load指令，load不前递，单可以在mem_wb前递，因为load要到mem才能有数据
    output load_flag_o,
    //打拍后的load标志信号
    input ex_mem_load_flag_i,

    output ex_req_o,

    // DMA外部中断
    input wire dma_irq_i,

    // CPU确认接受中断
    input wire                trap_enter_i,//标志cpu正式进入中断
    input wire [`InstAddrBus] trap_pc_i,//中断产生会冲刷两条指令，记录被冲刷的pc（被冲刷的后面还要执行）

    // WB提交CSR新值
    input wire                wb_csr_we_i,
    input wire [`CsrAddrBus]  wb_csr_waddr_i,
    input wire [`CsrDataBus]  wb_csr_wdata_i,

    // 输出给CPU控制逻辑
    output wire [`InstAddrBus] mtvec_o,
    output wire [`InstAddrBus] mepc_o,
    output wire                irq_request_o,//通过内部寄存器和外部dma的中断给cpu的中断请求

    // ID/EX传来的CSR指令
    input wire [`CsrAddrBus] csr_addr_i,
    input wire [`CsrCmdBus]  csr_cmd_i,
    input wire               csr_en_i,
    input wire               csr_mret_i,

    // EX计算出的CSR新值，送到EX/MEM
    output wire                csr_we_o,
    output wire [`CsrAddrBus]  csr_waddr_o,
    output wire [`CsrDataBus]  csr_wdata_o,

    //ex_mem的数据前递，mem_wb的前递就是sb写回csrfile的新值
    input ex_mem_csr_we_i,
    input  [`CsrAddrBus]  ex_mem_csr_waddr_i,
    input  [`CsrDataBus]  ex_mem_csr_wdata_i

);

wire [`CsrDataBus] csr_rdata;
wire               csr_mret_commit;

reg [`CsrDataBus] csr_rdata_final;
//选择，优先级ex_mem>wb写回的新值>读取csrfile的rdata旧值
always @(*) begin
    csr_rdata_final = csr_rdata;
    // EX/MEM离当前EX更近，优先级最高
    if (ex_mem_csr_we_i && (ex_mem_csr_waddr_i == csr_addr_i)) begin
        csr_rdata_final = ex_mem_csr_wdata_i;
    end

    // WB前递
    else if (wb_csr_we_i && (wb_csr_waddr_i == csr_addr_i)) begin
        csr_rdata_final = wb_csr_wdata_i;
    end

    else begin 
        csr_rdata_final = csr_rdata;
    end
end

// ex执行模块例化
ex u_ex(
    .ex_valid_i(ex_valid_i),
    .ex_advance(ex_advance_i),

    .rs1_i(rs1_i),
    .rs2_i(rs2_i),

    .rd_i(rd_i),

    .imm_i(imm_i),

    .re1_i(re1_i),
    .re2_i(re2_i),
    .reg_we_i(reg_we_i),

    .jump_flag_i(jump_flag_i),
    .branch_flag_i(branch_flag_i),
    .jalr_flag_i(jalr_flag_i),

    .pc_i(pc_i),
    .pc_plus4_i(pc_plus4_i),

    .rs1_data_i(rs1_data_i),
    .rs2_data_i(rs2_data_i),

    .mem_re_i(mem_re_i),
    .mem_we_i(mem_we_i),
    .mem_op_i(mem_op_i),
    .wb_sel_i(wb_sel_i),

    .fence_i(fence_i),

    .aluop_i(aluop_i),
    .alu_src1_sel_i(alu_src1_sel_i),
    .alu_src2_sel_i(alu_src2_sel_i),

    .redirect_o(redirect_o),
    .redirect_pc_o(redirect_pc_o),

    .rd_o(rd_o),
    .reg_we_o(reg_we_o),
    .wb_sel_o(wb_sel_o),

    .alu_result_o(alu_result_o),
    .store_data_o(store_data_o),

    .mem_re_o(mem_re_o),
    .mem_we_o(mem_we_o),
    .mem_op_o(mem_op_o),

    .pc_plus4_o(pc_plus4_o),
    .fence_o(fence_o),

    .ex_mem_reg_we_i(ex_mem_reg_we_i),
    .ex_mem_rd_i(ex_mem_rd_i),
    .ex_mem_forward_result_i(ex_mem_forward_result_i),

    .mem_wb_reg_we_i(mem_wb_reg_we_i),
    .mem_wb_rd_i(mem_wb_rd_i),
    .mem_wb_forward_result_i(mem_wb_forward_result_i),

    .load_flag_o(load_flag_o),
    .ex_mem_load_flag_i(ex_mem_load_flag_i),

    .csr_addr_i  (csr_addr_i),
    .csr_cmd_i   (csr_cmd_i),
    .csr_en_i    (csr_en_i),

    // CSRFile组合读取的旧值
    .csr_rdata_i (csr_rdata_final),

    // ID/EX传来的mret
    .csr_mret_i  (csr_mret_i),

    // mret跳转目标
    .csr_mepc_i  (mepc_o),

    // EX计算出的CSR新值
    .csr_we_o    (csr_we_o),
    .csr_waddr_o (csr_waddr_o),
    .csr_wdata_o (csr_wdata_o),

    // 送CSRFile更新mstatus
    .csr_mret_o  (csr_mret_commit)
);

//ex_req模块例化
ex_req u_ex_req(
    .ex_req_o(ex_req_o)
);

csr_file u_csr_file (
    .clk           (clk),
    .rst_n         (rst_n),

    // 当前EX阶段CSR指令的地址
    .raddr_i       (csr_addr_i),
    .rdata_o       (csr_rdata),

    // WB阶段提交CSR新值
    .wb_we_i       (wb_csr_we_i),
    .wb_waddr_i    (wb_csr_waddr_i),
    .wb_wdata_i    (wb_csr_wdata_i),

    // DMA外部中断
    .dma_irq_i     (dma_irq_i),

    // CPU正式接受中断
    .trap_enter_i  (trap_enter_i),
    .trap_pc_i     (trap_pc_i),

    // EX执行mret
    .mret_i        (csr_mret_commit),

    // 输出给CPU控制逻辑
    .mtvec_o       (mtvec_o),
    .mepc_o        (mepc_o),
    .irq_request_o (irq_request_o)
);

endmodule
