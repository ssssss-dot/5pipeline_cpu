`include "define.sv"

//打一拍寄存给到id
module if_id(
    input clk,
    input rst_n,

    input stall_i,//暂停信号，信号保持原状
    input flush_i,//表示冲刷掉当前指令

    input [`InstAddrBus] if_pc_i,
    input [`InstAddrBus] if_pc_plus4_i,
    input [`InstBus] if_inst_i,
    input   if_valid_i,//表示取出的数据有效，现在定为1，表示输出全有效

    output reg [`InstAddrBus] id_pc_o,
    output reg [`InstAddrBus] id_pc_plus4_o,
    output reg [`InstBus] id_inst_o,
    output reg id_valid_o

);

//nopinst表示空指令，指令为`define NOP_INST 32'h00000013
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        id_pc_o <= `ZeroWord;
        id_pc_plus4_o <= `ZeroWord;
        id_inst_o <= `NOP_INST;
        id_valid_o <= 'd0;
    end 
    else if(flush_i)begin//冲刷
        id_pc_o <= `ZeroWord;
        id_pc_plus4_o <= `ZeroWord;
        id_inst_o <= `NOP_INST;
        id_valid_o <= 'd0;
    end
    else if(stall_i) begin//暂停
        id_pc_o <= id_pc_o;
        id_pc_plus4_o <= id_pc_plus4_o;
        id_inst_o <= id_inst_o;
        id_valid_o <= id_valid_o;
    end
    else if(if_valid_i == 0) begin//无效数据
        id_pc_o <= `ZeroWord;
        id_pc_plus4_o <= `ZeroWord;
        id_inst_o <= `NOP_INST;
        id_valid_o <= 'd0;
    end
    else begin//正常流水线打拍
        id_pc_o <= if_pc_i;
        id_pc_plus4_o <= if_pc_plus4_i;
        id_inst_o <= if_inst_i;
        id_valid_o <= if_valid_i;
    end
end

endmodule