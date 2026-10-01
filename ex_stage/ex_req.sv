`include "define.sv"

//只有加减法单周期运算，直接赋值0
 module ex_req(
    output wire ex_req_o
);

assign ex_req_o = 1'b0;

endmodule