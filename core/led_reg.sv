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
    output  wire  [`DataBus]     mmio_rsp_rdata,

    output [1:0] en
); 

reg [`DataBus] led_reg;
reg [`DataBus] addr_q;
reg [`DataBus] wdata_q;
reg [3:0] wstrb_q;
reg write_q;

localparam  IDLE = 1'b0;
localparam  RESP = 1'b1;

reg state ; 
reg next_state ;

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        state <= 'd0;
    end
    else begin
        state <= next_state;
    end
end

always @(*)begin
    next_state = state;
    case(state)
        IDLE:begin
            if(mmio_req_valid && mmio_req_ready)begin
                next_state = RESP;
            end
        end
        RESP:begin
            if(mmio_rsp_ready && mmio_rsp_valid)begin
                next_state = IDLE;
            end
        end
    endcase
end

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        addr_q <= 'd0;
        wdata_q <= 'd0;
        wstrb_q <= 'd0;
        write_q <= 'd0;
        led_reg <='d0;
    end
    else begin
        case(state)
            IDLE:begin
                if(mmio_req_valid && mmio_req_ready)begin
                    addr_q  <= mmio_req_addr;
                    wstrb_q <= mmio_req_wstrb;
                    write_q <= mmio_req_write;
                    wdata_q <= mmio_req_wdata;
                end
            end
            RESP:begin
                if((mmio_rsp_ready && mmio_rsp_valid) && {addr_q[31:2], 2'b00} == `LED_CTRL_ADDR)begin
                    if(write_q)begin
                        if(wstrb_q[0])begin
                            led_reg[7:0] <= wdata_q[7:0];
                        end
                        if(wstrb_q[1])begin
                            led_reg[15:8] <= wdata_q[15:8];
                        end
                        if(wstrb_q[2])begin
                            led_reg[23:16] <= wdata_q[23:16];
                        end
                        if(wstrb_q[3])begin
                            led_reg[31:24] <= wdata_q[31:24];
                        end
                    end
                end
            end
        endcase
    end
end

assign mmio_req_ready = (state == IDLE);
assign mmio_rsp_valid = (state == RESP);
assign mmio_rsp_rdata =
    (mmio_rsp_valid && !write_q &&
     ({addr_q[31:2], 2'b00} == `LED_CTRL_ADDR))
    ? led_reg : 32'b0;

assign en = led_reg[1:0];

endmodule