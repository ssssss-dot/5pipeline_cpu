`include "define.sv"

module id_stage(
    input  clk,
    input  rst_n,

    //if_stage给到的信号
    input  [`InstBus]      inst_i,
    input  [`InstAddrBus]  pc_i,
    input  [`InstAddrBus]  pc_plus4_i,

    // 来自 WB 级的写回接口
    input                  wb_we_i,
    input  [`RegAddrBus]   wb_waddr_i,
    input  [`RegBus]       wb_wdata_i,

    // 送给后面的 id_ex
    output  [`RegAddrBus]  rs1_o,
    output  [`RegAddrBus]  rs2_o,
    output  [`RegAddrBus]  rd_o,

    output  [`RegBus]      imm_o,

    output                 re1_o,
    output                 re2_o,
    output                 reg_we_o,

    output                 jump_flag_o,
    output                 branch_flag_o,
    output                 jalr_flag_o,

    output                 mem_re_o,
    output                 mem_we_o,
    output  [`MemOpBus]    mem_op_o,
    output  [`WbSelBus]    wb_sel_o,

    output                 fence_o,

    output  [`AluOpBus]        aluop_o,
    output  [`AluSrc1SelBus]   alu_src1_sel_o,
    output  [`AluSrc2SelBus]   alu_src2_sel_o,

    output  [`InstAddrBus]  pc_o,
    output  [`InstAddrBus]  pc_plus4_o,
    output  [`RegBus]       rs1_data_o,
    output  [`RegBus]       rs2_data_o,

    //判断当前ID指令有没有依赖EX那条还没完成的load结果，后续做数据冒险检测用
    input  ex_mem_re_i,//EX阶段上一条是不是 load，如果拉高说明是lb/lh/lw/lbu/lhu，这些指令的结果不是现在立刻就有，而是还要到后面的 MEM 阶段读完内存才真正拿到
    input [`RegAddrBus] ex_rd_i,//EX阶段上一条最后要写哪个寄存器

    // mret需要读取mepc/mstatus；前面仍有CSR写操作时必须暂停ID级
    input  ex_csr_we_i,
    input  mem_csr_we_i,
    input  wb_csr_we_i,

    output id_req_o,

    //csr
    output  [`CsrAddrBus] csr_addr_o,
    output  [`CsrCmdBus]  csr_cmd_o,
    output  csr_en_o,
    output  mret_o    

);

wire [`RegBus] rs1_data;
wire [`RegBus] rs2_data;

// 译码模块
id u_id(
    .inst_i(inst_i),

    .pc_i(pc_i),
    .pc_plus4_i(pc_plus4_i),

    .rs1_data_i(rs1_data),
    .rs2_data_i(rs2_data),

    .rs1_o(rs1_o),
    .rs2_o(rs2_o),
    .rd_o(rd_o),

    .imm_o(imm_o),

    .re1_o(re1_o),
    .re2_o(re2_o),
    .reg_we_o(reg_we_o),

    .jump_flag_o(jump_flag_o),
    .branch_flag_o(branch_flag_o),
    .jalr_flag_o(jalr_flag_o),

    .mem_re_o(mem_re_o),
    .mem_we_o(mem_we_o),
    .mem_op_o(mem_op_o),
    .wb_sel_o(wb_sel_o),

    .fence_o(fence_o),

    .aluop_o(aluop_o),
    .alu_src1_sel_o(alu_src1_sel_o),
    .alu_src2_sel_o(alu_src2_sel_o),

    .pc_o(pc_o),
    .pc_plus4_o(pc_plus4_o),
    .rs1_data_o(rs1_data_o),
    .rs2_data_o(rs2_data_o),

    .csr_addr_o(csr_addr_o),
    .csr_cmd_o(csr_cmd_o),
    .csr_en_o(csr_en_o),
    .mret_o(mret_o)
);

// 寄存器堆
reg_file u_reg_file(
    .clk(clk),
    .rst_n(rst_n),

    .we(wb_we_i),
    .waddr(wb_waddr_i),
    .wdata(wb_wdata_i),

    .re1(re1_o),
    .raddr1(rs1_o),
    .rdata1(rs1_data),

    .re2(re2_o),
    .raddr2(rs2_o),
    .rdata2(rs2_data)
);

//id_req模块例化
id_req u_id_req(
    .id_re1_i(re1_o),
    .id_re2_i(re2_o),
    .id_rs1_i(rs1_o),
    .id_rs2_i(rs2_o),

    .ex_mem_re_i(ex_mem_re_i),
    .ex_rd_i(ex_rd_i),

    .id_req_o(id_req_o),

    // mret与前面CSR写指令之间的冒险检测
    .id_mret_i(mret_o),
    .ex_csr_we_i(ex_csr_we_i),
    .mem_csr_we_i(mem_csr_we_i),
    .wb_csr_we_i(wb_csr_we_i)
);
endmodule
