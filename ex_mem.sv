`include "define.sv"

module ex_mem(
    input wire clk,
    input wire rst_n,

    input wire stall_i,
    input wire flush_i,

    // 来自 EX 级
    input wire                ex_reg_we_i,
    input wire [`RegAddrBus]  ex_rd_i,
    input wire [`WbSelBus]    ex_wb_sel_i,

    input wire [`RegBus]      ex_alu_result_i,
    input wire [`RegBus]      ex_store_data_i,

    input wire                ex_mem_re_i,
    input wire                ex_mem_we_i,
    input wire [`MemOpBus]    ex_mem_op_i,

    input wire [`InstAddrBus] ex_pc_plus4_i,
    input wire                ex_fence_i,

    // EX阶段计算出的CSR新值
    input wire                ex_csr_we_i,
    input wire [`CsrAddrBus]  ex_csr_waddr_i,
    input wire [`CsrDataBus]  ex_csr_wdata_i,

    // 给 forwarding / hazard 用
    input wire                ex_load_flag_i,

    // 打拍后送到 MEM 级
    output reg                mem_reg_we_o,
    output reg [`RegAddrBus]  mem_rd_o,
    output reg [`WbSelBus]    mem_wb_sel_o,

    output reg [`RegBus]      mem_alu_result_o,
    output reg [`RegBus]      mem_store_data_o,

    output reg                mem_mem_re_o,
    output reg                mem_mem_we_o,
    output reg [`MemOpBus]    mem_mem_op_o,

    output reg [`InstAddrBus] mem_pc_plus4_o,
    output reg                mem_fence_o,

    // 给后面 EX 前递 / ID 冒险检测用
    output reg                mem_load_flag_o,

    // 打拍后送到MEM阶段的CSR写回信息
    output reg                mem_csr_we_o,
    output reg [`CsrAddrBus]  mem_csr_waddr_o,
    output reg [`CsrDataBus]  mem_csr_wdata_o,

    output wire [`RegBus]     forward_result_o//给回去的前递数据
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 插入 bubble
        mem_reg_we_o     <= `WriteDisable;
        mem_rd_o         <= `NOPRegAddr;
        mem_wb_sel_o     <= `WB_SEL_NONE;

        mem_alu_result_o <= `ZeroWord;
        mem_store_data_o <= `ZeroWord;

        mem_mem_re_o     <= 1'b0;
        mem_mem_we_o     <= 1'b0;
        mem_mem_op_o     <= `MEM_NONE;

        mem_pc_plus4_o   <= `ZeroWord;
        mem_fence_o      <= 1'b0;

        mem_load_flag_o  <= 1'b0;

        mem_csr_we_o     <= 1'b0;
        mem_csr_waddr_o  <= 'd0;
        mem_csr_wdata_o  <= `ZeroWord;
    end
    else if (flush_i) begin
        // flush 时也插入 bubble
        mem_reg_we_o     <= `WriteDisable;
        mem_rd_o         <= `NOPRegAddr;
        mem_wb_sel_o     <= `WB_SEL_NONE;

        mem_alu_result_o <= `ZeroWord;
        mem_store_data_o <= `ZeroWord;

        mem_mem_re_o     <= 1'b0;
        mem_mem_we_o     <= 1'b0;
        mem_mem_op_o     <= `MEM_NONE;

        mem_pc_plus4_o   <= `ZeroWord;
        mem_fence_o      <= 1'b0;

        mem_load_flag_o  <= 1'b0;

        mem_csr_we_o     <= 1'b0;
        mem_csr_waddr_o  <= 'd0;
        mem_csr_wdata_o  <= `ZeroWord;
    end
    else if (stall_i) begin
        // 保持原值
        mem_reg_we_o     <= mem_reg_we_o;
        mem_rd_o         <= mem_rd_o;
        mem_wb_sel_o     <= mem_wb_sel_o;

        mem_alu_result_o <= mem_alu_result_o;
        mem_store_data_o <= mem_store_data_o;

        mem_mem_re_o     <= mem_mem_re_o;
        mem_mem_we_o     <= mem_mem_we_o;
        mem_mem_op_o     <= mem_mem_op_o;

        mem_pc_plus4_o   <= mem_pc_plus4_o;
        mem_fence_o      <= mem_fence_o;

        mem_load_flag_o  <= mem_load_flag_o;

        mem_csr_we_o     <= mem_csr_we_o;
        mem_csr_waddr_o  <= mem_csr_waddr_o;
        mem_csr_wdata_o  <= mem_csr_wdata_o;
    end
    else begin
        // 正常打一拍
        mem_reg_we_o     <= ex_reg_we_i;
        mem_rd_o         <= ex_rd_i;
        mem_wb_sel_o     <= ex_wb_sel_i;

        mem_alu_result_o <= ex_alu_result_i;
        mem_store_data_o <= ex_store_data_i;

        mem_mem_re_o     <= ex_mem_re_i;
        mem_mem_we_o     <= ex_mem_we_i;
        mem_mem_op_o     <= ex_mem_op_i;

        mem_pc_plus4_o   <= ex_pc_plus4_i;
        mem_fence_o      <= ex_fence_i;

        mem_load_flag_o  <= ex_load_flag_i;

        mem_csr_we_o     <= ex_csr_we_i;
        mem_csr_waddr_o  <= ex_csr_waddr_i;
        mem_csr_wdata_o  <= ex_csr_wdata_i;
    end
end

//判断前递的是哪个数据
assign forward_result_o =
    (mem_wb_sel_o == `WB_SEL_ALU) ? mem_alu_result_o  :
    (mem_wb_sel_o == `WB_SEL_PC4) ? mem_pc_plus4_o    :
                                    `ZeroWord;

endmodule
