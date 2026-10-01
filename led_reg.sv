`include "define.sv"

module led_reg(
    input clk,
    input rst_n,

    input   wire                 mmio_req_valid,
    output  wire                 mmio_req_ready,
    input   wire [`DataAddrBus]  mmio_req_addr,
    input   wire [`DataBus]      mmio_req_wdata,
    input   wire [3:0]           mmio_req_wstrb,
    input   wire                 mmio_req_write,
    output  wire                 mmio_rsp_valid,
    input   wire                 mmio_rsp_ready,
    output  wire [`DataBus]      mmio_rsp_rdata,

    output [1:0] en
); 

reg [`DataBus] led_reg;

localparam  IDLE = 1'b0;
localparam  RESP = 1'b0;

assign en = led_reg[1:0];
endmodule