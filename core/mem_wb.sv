`include "define.sv"

module mem_wb(
    input clk,
    input rst_n,

    input stall_i,
    input flush_i,

    input [`RegBus]      mem_alu_result_i,
    input [`InstAddrBus] mem_pc_plus4_i,
    input [`RegAddrBus]  mem_rd_i,
    input mem_reg_we_i,

    //从mem中读出的数据
    input [`RegBus]      mem_mem_data_i,

    //写回数据源选择
    input [`WbSelBus] mem_wb_sel_i,

    //load指令标志
    input mem_load_flag_i,

    input mem_fence_i,

    // MEM阶段直通的CSR写回信息
    input                mem_csr_we_i,
    input [`CsrAddrBus]  mem_csr_waddr_i,
    input [`CsrDataBus]  mem_csr_wdata_i,

    output reg [`RegBus]      wb_alu_result_o,
    output reg [`InstAddrBus] wb_pc_plus4_o,
    output reg [`RegAddrBus]  wb_rd_o,
    output reg                wb_reg_we_o,

    output reg [`RegBus]      wb_mem_data_o,
    output reg [`WbSelBus]    wb_wb_sel_o,
    output reg                wb_load_flag_o,
    output reg                wb_fence_o,

    // WB阶段提交给CSRFile
    output reg                wb_csr_we_o,
    output reg [`CsrAddrBus]  wb_csr_waddr_o,
    output reg [`CsrDataBus]  wb_csr_wdata_o

);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wb_alu_result_o <= `ZeroWord;
        wb_pc_plus4_o   <= `ZeroWord;
        wb_rd_o         <= `NOPRegAddr;
        wb_reg_we_o     <= `WriteDisable;

        wb_mem_data_o   <= `ZeroWord;
        wb_wb_sel_o     <= `WB_SEL_NONE;
        wb_load_flag_o  <= 1'b0;
        wb_fence_o      <= 1'b0;

        wb_csr_we_o     <= 1'b0;
        wb_csr_waddr_o  <= 'd0;
        wb_csr_wdata_o  <= `ZeroWord;
    end
    else if (flush_i) begin
        wb_alu_result_o <= `ZeroWord;
        wb_pc_plus4_o   <= `ZeroWord;
        wb_rd_o         <= `NOPRegAddr;
        wb_reg_we_o     <= `WriteDisable;

        wb_mem_data_o   <= `ZeroWord;
        wb_wb_sel_o     <= `WB_SEL_NONE;
        wb_load_flag_o  <= 1'b0;
        wb_fence_o      <= 1'b0;

        wb_csr_we_o     <= 1'b0;
        wb_csr_waddr_o  <= 'd0;
        wb_csr_wdata_o  <= `ZeroWord;
    end
    else if (stall_i) begin
        wb_alu_result_o <= wb_alu_result_o;
        wb_pc_plus4_o   <= wb_pc_plus4_o;
        wb_rd_o         <= wb_rd_o;
        wb_reg_we_o     <= wb_reg_we_o;

        wb_mem_data_o   <= wb_mem_data_o;
        wb_wb_sel_o     <= wb_wb_sel_o;
        wb_load_flag_o  <= wb_load_flag_o;
        wb_fence_o      <= wb_fence_o;

        wb_csr_we_o     <= wb_csr_we_o;
        wb_csr_waddr_o  <= wb_csr_waddr_o;
        wb_csr_wdata_o  <= wb_csr_wdata_o;
    end
    else begin
        wb_alu_result_o <= mem_alu_result_i;
        wb_pc_plus4_o   <= mem_pc_plus4_i;
        wb_rd_o         <= mem_rd_i;
        wb_reg_we_o     <= mem_reg_we_i;

        wb_mem_data_o   <= mem_mem_data_i;
        wb_wb_sel_o     <= mem_wb_sel_i;
        wb_load_flag_o  <= mem_load_flag_i;
        wb_fence_o      <= mem_fence_i;

        wb_csr_we_o     <= mem_csr_we_i;
        wb_csr_waddr_o  <= mem_csr_waddr_i;
        wb_csr_wdata_o  <= mem_csr_wdata_i;
    end
end

endmodule
