module cdc_sync #(

  //把外部给的中断haltcpu信号做时钟域同步，输出一个和clk对齐的halt信号
  //多级触发同步链（就是寄存器打两拍）
   // Configurable parameters   
   parameter STAGES = 2             // No. of flops in the sync chain, min. 2
)

(
   input  clk        ,        // Clock @ destination clock domain
   input  rst_n       ,        // Reset @ destination clock domain; this may be omitted if targetting FPGAs
   input  i_sig      ,        // Input signal, asynchronous
   output o_sig_sync          // Output signal synchronized to clk
) ;

(* ASYNC_REG = "TRUE" *)//它的意思是告诉 FPGA 综合/布局布线工具：这个寄存器是异步信号同步链的一部分，请按 CDC 同步寄存器来处理
reg [STAGES-1: 0] sync_ff ;

// Synchronizing logic
always @(posedge clk or negedge rst_n) begin   
   if (!rst_n) begin
      sync_ff <= 'd0 ;
   end
   else begin
      sync_ff <= {sync_ff [STAGES-2 : 0], i_sig} ; //把整体左移，再把i_sig拼到最后一位    
   end
end

// Synchronized signal
assign o_sig_sync = sync_ff [STAGES-1] ;

endmodule