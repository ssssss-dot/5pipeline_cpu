`include "define.sv"

// 第二级流水线寄存器 ID/EX
module id_ex(
    input wire clk,
    input wire rst_n,

    // IF/ID传来的指令有效信号
    input wire id_valid_i,

    // 寄存器地址
    input wire [`RegAddrBus] id_rs1_i,
    input wire [`RegAddrBus] id_rs2_i,

    // 目的寄存器地址
    input wire [`RegAddrBus] id_rd_i,

    // 立即数
    input wire [`RegBus] id_imm_i,

    // regfile 读/写使能
    input wire id_re1_i,
    input wire id_re2_i,
    input wire id_reg_we_i,

    // 跳转/分支
    input wire id_jump_flag_i,
    input wire id_branch_flag_i,
    input wire id_jalr_flag_i,

    // 来自 IF/ID 的 PC 信息
    input wire [`InstAddrBus] pc_i,
    input wire [`InstAddrBus] pc_plus4_i,

    // regfile 读出的数据
    input wire [`RegBus] rs1_data_i,
    input wire [`RegBus] rs2_data_i,

    // MEM / WB 控制
    input wire id_mem_re_i,
    input wire id_mem_we_i,
    input wire [`MemOpBus] id_mem_op_i,
    input wire [`WbSelBus] id_wb_sel_i,

    // fence
    input wire id_fence_i,

    //csr信号
    input wire [`CsrAddrBus] id_csr_addr_i,
    input wire  id_csr_en_i,
    input wire [`CsrCmdBus] id_csr_cmd_i,
    input wire  id_csr_mret_i,

    // ALU 控制
    input wire [`AluOpBus] id_aluop_i,
    input wire [`AluSrc1SelBus] id_alu_src1_sel_i,
    input wire [`AluSrc2SelBus] id_alu_src2_sel_i,

    // 控制信号
    input wire flush_i,
    input wire stall_i,

    // 打拍后的输出
    output reg [`RegAddrBus] ex_rs1_o,
    output reg [`RegAddrBus] ex_rs2_o,
    output reg [`RegAddrBus] ex_rd_o,

    output reg [`RegBus] ex_imm_o,

    output reg ex_re1_o,
    output reg ex_re2_o,
    output reg ex_reg_we_o,

    output reg ex_jump_flag_o,
    output reg ex_branch_flag_o,
    output reg ex_jalr_flag_o,

    output reg ex_mem_re_o,
    output reg ex_mem_we_o,
    output reg [`MemOpBus] ex_mem_op_o,
    output reg [`WbSelBus] ex_wb_sel_o,

    output reg ex_fence_o,

    output reg [`AluOpBus] ex_aluop_o,
    output reg [`AluSrc1SelBus] ex_alu_src1_sel_o,
    output reg [`AluSrc2SelBus] ex_alu_src2_sel_o,

    output reg [`InstAddrBus] pc_o,
    output reg [`InstAddrBus] pc_plus4_o,
    output reg [`RegBus] rs1_data_o,
    output reg [`RegBus] rs2_data_o,

    // 当前EX阶段指令是否有效
    output reg ex_valid_o,

    output reg [`CsrAddrBus] ex_csr_addr_o,
    output reg  ex_csr_en_o,
    output reg [`CsrCmdBus] ex_csr_cmd_o,
    output reg  ex_csr_mret_o
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 清空，插入 bubble
        ex_rs1_o <= `NOPRegAddr;
        ex_rs2_o <= `NOPRegAddr;
        ex_rd_o  <= `NOPRegAddr;

        ex_imm_o <= `ZeroWord;

        ex_re1_o    <= `ReadDisable;
        ex_re2_o    <= `ReadDisable;
        ex_reg_we_o <= `WriteDisable;

        ex_jump_flag_o   <= 1'b0;
        ex_branch_flag_o <= 1'b0;
        ex_jalr_flag_o   <= 1'b0;

        ex_mem_re_o <= 1'b0;
        ex_mem_we_o <= 1'b0;
        ex_mem_op_o <= `MEM_NONE;
        ex_wb_sel_o <= `WB_SEL_NONE;

        ex_fence_o <= 1'b0;

        ex_aluop_o        <= `EX_NOP_OP;
        ex_alu_src1_sel_o <= `ALU_SRC1_RS1;
        ex_alu_src2_sel_o <= `ALU_SRC2_RS2;

        pc_o       <= `ZeroWord;
        pc_plus4_o <= `ZeroWord;
        rs1_data_o <= `ZeroWord;
        rs2_data_o <= `ZeroWord;

        ex_valid_o <= 1'b0;

        ex_csr_addr_o <= 'd0;
        ex_csr_en_o   <= 1'b0;
        ex_csr_cmd_o  <= `CSR_CMD_NONE;
        ex_csr_mret_o <= 1'b0;
    end
    else if (flush_i) begin
        // flush 时也插入 bubble
        ex_rs1_o <= `NOPRegAddr;
        ex_rs2_o <= `NOPRegAddr;
        ex_rd_o  <= `NOPRegAddr;

        ex_imm_o <= `ZeroWord;

        ex_re1_o    <= `ReadDisable;
        ex_re2_o    <= `ReadDisable;
        ex_reg_we_o <= `WriteDisable;

        ex_jump_flag_o   <= 1'b0;
        ex_branch_flag_o <= 1'b0;
        ex_jalr_flag_o   <= 1'b0;

        ex_mem_re_o <= 1'b0;
        ex_mem_we_o <= 1'b0;
        ex_mem_op_o <= `MEM_NONE;
        ex_wb_sel_o <= `WB_SEL_NONE;

        ex_fence_o <= 1'b0;

        ex_aluop_o        <= `EX_NOP_OP;
        ex_alu_src1_sel_o <= `ALU_SRC1_RS1;
        ex_alu_src2_sel_o <= `ALU_SRC2_RS2;

        pc_o       <= `ZeroWord;
        pc_plus4_o <= `ZeroWord;
        rs1_data_o <= `ZeroWord;
        rs2_data_o <= `ZeroWord;

        ex_valid_o <= 1'b0;

        ex_csr_addr_o <= 'd0;
        ex_csr_en_o   <= 1'b0;
        ex_csr_cmd_o  <= `CSR_CMD_NONE;
        ex_csr_mret_o <= 1'b0;
    end
    else if (stall_i) begin
        // 保持原值
        ex_rs1_o <= ex_rs1_o;
        ex_rs2_o <= ex_rs2_o;
        ex_rd_o  <= ex_rd_o;

        ex_imm_o <= ex_imm_o;

        ex_re1_o    <= ex_re1_o;
        ex_re2_o    <= ex_re2_o;
        ex_reg_we_o <= ex_reg_we_o;

        ex_jump_flag_o   <= ex_jump_flag_o;
        ex_branch_flag_o <= ex_branch_flag_o;
        ex_jalr_flag_o   <= ex_jalr_flag_o;

        ex_mem_re_o <= ex_mem_re_o;
        ex_mem_we_o <= ex_mem_we_o;
        ex_mem_op_o <= ex_mem_op_o;
        ex_wb_sel_o <= ex_wb_sel_o;

        ex_fence_o <= ex_fence_o;

        ex_aluop_o        <= ex_aluop_o;
        ex_alu_src1_sel_o <= ex_alu_src1_sel_o;
        ex_alu_src2_sel_o <= ex_alu_src2_sel_o;

        pc_o       <= pc_o;
        pc_plus4_o <= pc_plus4_o;
        rs1_data_o <= rs1_data_o;
        rs2_data_o <= rs2_data_o;

        ex_valid_o <= ex_valid_o;

        ex_csr_addr_o <= ex_csr_addr_o;
        ex_csr_en_o   <= ex_csr_en_o;
        ex_csr_cmd_o  <= ex_csr_cmd_o;
        ex_csr_mret_o <= ex_csr_mret_o;
    end
    else begin
        // 正常打一拍
        ex_rs1_o <= id_rs1_i;
        ex_rs2_o <= id_rs2_i;
        ex_rd_o  <= id_rd_i;

        ex_imm_o <= id_imm_i;

        ex_re1_o    <= id_re1_i;
        ex_re2_o    <= id_re2_i;
        ex_reg_we_o <= id_reg_we_i;

        ex_jump_flag_o   <= id_jump_flag_i;
        ex_branch_flag_o <= id_branch_flag_i;
        ex_jalr_flag_o   <= id_jalr_flag_i;

        ex_mem_re_o <= id_mem_re_i;
        ex_mem_we_o <= id_mem_we_i;
        ex_mem_op_o <= id_mem_op_i;
        ex_wb_sel_o <= id_wb_sel_i;

        ex_fence_o <= id_fence_i;

        ex_aluop_o        <= id_aluop_i;
        ex_alu_src1_sel_o <= id_alu_src1_sel_i;
        ex_alu_src2_sel_o <= id_alu_src2_sel_i;

        pc_o       <= pc_i;
        pc_plus4_o <= pc_plus4_i;
        rs1_data_o <= rs1_data_i;
        rs2_data_o <= rs2_data_i;

        ex_valid_o <= id_valid_i;

        ex_csr_addr_o <= id_csr_addr_i;
        ex_csr_en_o   <= id_csr_en_i;
        ex_csr_cmd_o  <= id_csr_cmd_i;
        ex_csr_mret_o <= id_csr_mret_i;
    end
end

endmodule
