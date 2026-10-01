`include "define.sv"

module dram(
    input clk,
    input rst_n,

    input    dmem_req_valid,
    output   dmem_req_ready,
    input  [`DataAddrBus]  dmem_req_addr,
    input  [`DataBus]  dmem_req_wdata,
    input  [3:0]  dmem_req_wstrb,
    input    dmem_req_write,
    output   dmem_rsp_valid,
    input    dmem_rsp_ready,
    output reg [`DataBus] dmem_rsp_rdata
);

(* ram_style = "block" *) reg [`DataBus] dram [0 : `DataMemNum - 1'b1];

localparam IDLE = 1'b0;
localparam RESP = 1'b1;

reg [`DataBus] addr_q;
reg [`DataBus] wdata_q;
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
            if(dmem_req_valid && dmem_req_ready)begin
                next_state = RESP;
            end
        end
        RESP:begin
            if(dmem_rsp_ready && dmem_rsp_valid)begin
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
                if(dmem_req_valid && dmem_req_ready)begin
                    addr_q  <= dmem_req_addr;
                    wstrb_q <= dmem_req_wstrb;
                    write_q <= dmem_req_write;
                    wdata_q <= dmem_req_wdata;
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
            dram[addr_q[14:2]][7:0] <= wdata_q[7:0];
        end
        if(wstrb_q[1])begin
            dram[addr_q[14:2]][15:8] <= wdata_q[15:8];
        end
        if(wstrb_q[2])begin
            dram[addr_q[14:2]][23:16] <= wdata_q[23:16];
        end
        if(wstrb_q[3])begin
            dram[addr_q[14:2]][31:24] <= wdata_q[31:24];
        end
    end
    else if(dmem_req_valid && dmem_req_ready)begin
        dmem_rsp_rdata <= dram[dmem_req_addr[14:2]];
    end
end

assign dmem_req_ready = rst_n && (state == IDLE);
assign dmem_rsp_valid = rst_n && (state == RESP);

endmodule