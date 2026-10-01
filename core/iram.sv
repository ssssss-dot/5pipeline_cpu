`include "define.sv"

module iram(
    input clk,
    input rst_n,

    input    imem_req_valid,
    output   imem_req_ready,
    input  [`InstAddrBus]  imem_req_addr,
    input  [`InstBus]  imem_req_wdata,
    input  [3:0]  imem_req_wstrb,
    input    imem_req_write,
    output   imem_rsp_valid,
    input    imem_rsp_ready,
    output reg [`InstBus] imem_rsp_rdata
);

(* ram_style = "block" *) reg [`InstBus] iram [0 : `InstMemNum - 1'b1];

localparam IDLE = 1'b0;
localparam RESP = 1'b1;

reg [`InstBus] addr_q;
reg [`InstBus] wdata_q;
reg [3:0] wstrb_q;
reg write_q;

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
            if(imem_req_valid && imem_req_ready)begin
                next_state = RESP;
            end
        end
        RESP:begin
            if(imem_rsp_ready && imem_rsp_valid)begin
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
    end
    else begin
        write_q <= 'd0;
        case(state)
            IDLE:begin
                if(imem_req_valid && imem_req_ready)begin
                    addr_q  <= imem_req_addr;
                    wstrb_q <= imem_req_wstrb;
                    write_q <= imem_req_write;
                    wdata_q <= imem_req_wdata;
                end
            end
            RESP:begin
            end
        endcase
    end
end

always @(posedge clk)begin
    if(write_q)begin
        if(wstrb_q[0])begin
            iram[addr_q[14:2]][7:0] <= wdata_q[7:0];
        end
        if(wstrb_q[1])begin
            iram[addr_q[14:2]][15:8] <= wdata_q[15:8];
        end
        if(wstrb_q[2])begin
            iram[addr_q[14:2]][23:16] <= wdata_q[23:16];
        end
        if(wstrb_q[3])begin
            iram[addr_q[14:2]][31:24] <= wdata_q[31:24];
        end
    end
    else if(imem_req_valid && imem_req_ready)begin
        imem_rsp_rdata <= iram[imem_req_addr[14:2]];
    end
end

assign imem_req_ready = rst_n && (state == IDLE);
assign imem_rsp_valid = rst_n && (state == RESP);

endmodule
