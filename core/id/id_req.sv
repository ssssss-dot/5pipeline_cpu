`include "define.sv"

//产生load数据冒险，load需要多一拍
module id_req(
    // 当前 ID 级的信息
    input wire                id_re1_i,
    input wire                id_re2_i,
    input wire [`RegAddrBus]  id_rs1_i,
    input wire [`RegAddrBus]  id_rs2_i,

    // 来自 EX 级的信息
    input wire                ex_mem_re_i,   // 前一条是不是load
    input wire [`RegAddrBus]  ex_rd_i,       // 前一条要写回哪个rd

    output wire               id_req_o,

    //id阶段发现csr
    input wire id_mret_i,

    //观察前面的ex，mem，wb阶段有没有要更新的csr数据
    input wire ex_csr_we_i,
    input wire mem_csr_we_i,
    input wire wb_csr_we_i
);

//如果 ID 阶段这条指令，正要读取一个寄存器，而这个寄存器恰好是前一条 load 指令还没来得及写回的目标寄存器，那就发出暂停请求 id_req_o=1
//(ex_mem_re_i == 1'b1)：前一条正在 EX 的指令是不是 load
//(ex_rd_i != `NOPRegAddr)：前一条指令确实要写某个目标寄存器
//(id_re1_i && (id_rs1_i == ex_rd_i))：当前 ID 这条指令真的要读 rs1，而且它读的 rs1，正好就是前一条 load 要写回的寄存器
//csr的mret冒险也需要从id阶段暂停流水线
//比如前一条指令要改csrfile的寄存器，后面紧跟着一条mret指令（mret会调用csrfile里面寄存器的值）
assign id_req_o = ((ex_mem_re_i == 1'b1) && (ex_rd_i != `NOPRegAddr) && ((id_re1_i && (id_rs1_i == ex_rd_i)) || (id_re2_i && (id_rs2_i == ex_rd_i))))
                    || (id_mret_i && (ex_csr_we_i || mem_csr_we_i || wb_csr_we_i));

endmodule