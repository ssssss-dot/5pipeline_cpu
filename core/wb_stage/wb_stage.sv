`include "define.sv"

module wb_stage(
    input  wire [`RegBus]     mem_data_i,
    input  wire [`RegBus]     alu_result_i,
    input  wire [`InstAddrBus] pc_plus4_i,
    input  wire [`RegAddrBus] rd_i,
    input  wire               reg_we_i,
    input  wire [`WbSelBus]   wb_sel_i,

    // 写回 reg_file
    output wire               wb_we_o,
    output wire [`RegAddrBus] wb_waddr_o,
    output reg  [`RegBus]     wb_wdata_o,

    // 给 EX 阶段前递
    output wire               wb_reg_we_for_ex_o,
    output wire [`RegAddrBus] wb_rd_for_ex_o,
    output wire [`RegBus]     wb_forward_result_for_ex_o,

    input csr_we_i,
    input [`CsrAddrBus] csr_waddr_i,
    input [`CsrDataBus] csr_wdata_i,

    // 送给CSRFile
    output wire                wb_csr_we_o,
    output wire [`CsrAddrBus]  wb_csr_waddr_o,
    output wire [`CsrDataBus]  wb_csr_wdata_o
);

assign wb_csr_we_o    = csr_we_i;
assign wb_csr_waddr_o = csr_waddr_i;
assign wb_csr_wdata_o = csr_wdata_i;

//写回reg_file数据源选择
always @(*) begin
    case (wb_sel_i)
        `WB_SEL_ALU: begin
            wb_wdata_o = alu_result_i;
        end

        `WB_SEL_MEM: begin
            wb_wdata_o = mem_data_i;
        end

        `WB_SEL_PC4: begin
            wb_wdata_o = pc_plus4_i;
        end

        default: begin
            wb_wdata_o = `ZeroWord;
        end
    endcase
end

assign wb_we_o    = reg_we_i;//写使能
assign wb_waddr_o = rd_i;//写回reg_file的地址

// mem_wb -> ex 前递
assign wb_reg_we_for_ex_o       = reg_we_i;
assign wb_rd_for_ex_o           = rd_i;
assign wb_forward_result_for_ex_o = wb_wdata_o;

endmodule