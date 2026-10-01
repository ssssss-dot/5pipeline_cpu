`include "define.sv"

// Fetch stage with a native instruction-memory request/response port.
module if_stage(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                stall_i,
    input  wire                redirect_i,
    input  wire [`InstAddrBus] redirect_pc_i,
    output wire [`InstBus]     inst_o,
    output wire [`InstAddrBus] pc_o,
    output wire [`InstAddrBus] pc_plus4_o,
    output wire                if_valid_o,
    output wire                if_req_o,
    input  wire                fetch_enable,
    output wire                imem_req_valid,
    input  wire                imem_req_ready,
    output wire [`InstAddrBus] imem_req_addr,
    input  wire                imem_rsp_valid,
    input  wire [`InstBus]     imem_rsp_rdata
);

wire [`InstAddrBus] curr_pc;
wire [`InstAddrBus] curr_pc_d1;
wire [`InstAddrBus] next_pc;
wire                  cpu_read_en;

assign pc_o         = curr_pc_d1;
assign pc_plus4_o   = curr_pc_d1 + 32'd4;
assign cpu_read_en  = !stall_i && !redirect_i;

inst_ram u_inst_ram (
    .clk            (clk),
    .rst_n          (rst_n),
    .curr_pc_d1     (curr_pc_d1),
    .curr_pc        (curr_pc),
    .inst_o         (inst_o),
    .inst_valid_o   (if_valid_o),
    .cpu_read_en    (cpu_read_en),
    .redirect_i     (redirect_i),
    .if_req_o       (if_req_o),
    .if_req_valid   (imem_req_valid),
    .if_req_ready   (imem_req_ready),
    .if_req_addr    (imem_req_addr),
    .if_rsp_valid   (imem_rsp_valid),
    .if_rsp_rdata   (imem_rsp_rdata),
    .fetch_enable_i (fetch_enable)
);

mux_pc u_mux_pc (
    .stall_i       (stall_i),
    .redirect_i    (redirect_i),
    .redirect_pc_i (redirect_pc_i),
    .curr_pc       (curr_pc),
    .next_pc       (next_pc)
);

pc_reg u_pc_reg (
    .clk     (clk),
    .rst_n   (rst_n),
    .curr_pc (curr_pc),
    .next_pc (next_pc)
);

endmodule
