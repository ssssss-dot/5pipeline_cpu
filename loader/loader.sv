`include "define.sv"

// Module definition
module loader# (
   parameter clk_freq = 100_000_000,
   parameter uart_bps = 115200,
   parameter TIMEOUT = 100_000_000//loader允许一次操作等待的最大时钟周期数,防止loader进入下载状态后，因为上位机中断发送而永远卡住
)
(
   // Clock and Reset
   input                 clk                ,  // Clock
   input                 rst_n              ,  // Asynchronous Reset; active-low
   
   // Control Signals 
   input                i_halt_cpu         ,  // 外部使cpu停止运行的信号
   output               o_ldr_cpu_stall    ,  // 在传数据和指令时让cpu停
   output               o_ldr_cpu_reset    ,  // 传输完拉高，cpu开始处理

   // Status Signals
   output  reg              o_init_done        ,  // Flags that loader has been successfully initialized
   output  reg              o_busy             ,  // Programming status from Loader: '0'- Idle, '1'- Busy with programming
   output  reg              o_pgm_done         ,  // Flags when programming is done successfully without errors
   output                   o_err              ,  // Error in programming/other internal errors
   output     [4:0]         o_err_code         ,  // Error code

   // 和上位机的串口通信
   input                 i_uart_rx          ,  // UART RX
   output                o_uart_tx          ,  // UART TX
   
   // loader -> loader_bridge（aw，w）
   output         ldr_req_valid,
   input          ldr_req_ready,
   output  reg [31:0] ldr_req_addr,
   output  reg [31:0] ldr_req_wdata,
   output  reg [3:0]  ldr_req_wstrb,

   // loader_bridge -> loader：写完成响应（b）
   input         ldr_rsp_valid,
   output        ldr_rsp_ready,
   input         ldr_rsp_error,

   output o_debug_ram_sel
);

//===================================================================================================================================================
// Localparams (constants - DO NOT MODIFY) 
//===================================================================================================================================================
localparam I_PREAMBLE              = 8'hC0        ;  // 指令存储器下载的开头标志
localparam D_PREAMBLE              = 8'hD0        ;  // 数据存储器下载的开头标志
localparam POSTAMBLE               = 8'hE0        ;  // 表示一段下载数据结束了
localparam CMD_REQ_DEVC_SIGN       = 8'hD3        ;  // 请求设备签名
localparam CMD_BOOT_REQ_IRAM_CLN   = 8'hB1        ;  // 清空 IRAM 后再启动
localparam CMD_BOOT_REQ            = 8'hB0        ;  // 直接启动
localparam SUCCESS                 = 8'h55        ;  // 成功应答码
localparam ERROR_CMD_INVALID       = 8'hEC        ;  // 命令错误
localparam ERROR_PGM               = 8'hED        ;  // 烧录错误
localparam ERROR_POSTAMBLE         = 8'hEE        ;  // 结束标记错误
localparam DEVC_SIGN               = 32'hC0DE4A11 ;  // 固定 32 位值，用来让上位机识别连到的是不是这个 loader
//溢出判断用
localparam INST_REGION_BYTES = `InstMemNum * 4;
localparam DATA_REGION_BYTES = `DataMemNum * 4;

// NOP instruction for IRAM clean slate
localparam INSTR_NOP = 32'h0000_0013 ;

//===================================================================================================================================================
// Typedefs
//===================================================================================================================================================
// 状态机定义
localparam INIT           = 4'd0,//初始化，上电后赋初值
           IDLE           = 4'd1,//空闲状态，等上位机发指令
           IRAM_CLN       = 4'd2,//把指令存储器内容刷成NOP,擦掉旧程序
           READ_PGM_SIZE  = 4'd3,//读取程序大小，把uart连收的四个字节拼成程序总长度
           READ_PGM_BADDR = 4'd4,//读取程序基地址。再收 4 个字节，决定程序从 RAM 的哪个地址开始写
           READ_PGM_BIN   = 4'd5,//读取程序正文二进制。持续从 UART 收程序数据，每收满 4 个字节就准备写 RAM
           RAM_PGM        = 4'd6,//写ram，真正把数据送到iram或者dram
           READ_POSTAMBLE = 4'd7,//读取结束标记
           ACK            = 4'd8,//应答状态，给上位机发送设备签名，成功码或者错误码
           PGM_DONE       = 4'd9,//下载完成，释放cpu stall/reset 准备进入ack
           RAM_WAIT       = 4'd10,//等待握手
           IRAM_CLN_WAIT  = 4'd11;//写nop的状态

//===================================================================================================================================================
// Internal Registers/Signals
//===================================================================================================================================================

reg [3:0] state;
reg [3:0] next_state;
reg [3:0] ack_exit_state_rg;//存ack结束后next_state的状态

// Control signals - CPU
reg       cpu_stall_rg      ;  // 下载时让cpu处理部分暂停
reg       cpu_reset_rg      ;  // 下载时的复位信号

// Control/Status signals - UART
reg        uart_tx_en_rg        ;  // UART TX enable
reg        uart_rx_en_rg        ;  // UART RX enable
reg  [7:0] uart_txdata_rg       ;  // 准备发送给上位机的一个字节的数据
reg        uart_txdata_valid_rg ;  // 字节有效信号
wire       uart_tx_ready        ;  // uart返回的握手信号
wire [7:0] uart_rxdata          ;  // uart收到的一个字节
wire       uart_rxdata_valid    ;  // UART RX data valid
wire       uart_rx_ack          ;  // UART RX ack
wire       uart_error           ;  // 帧错误信号

// 命令识别 C0 C0 C0 C0（rxd读入的数据） → cmd_rg记录I_PREAMBLE → 选择IRA，D0 D0 D0 D0 → cmd_rg记录D_PREAMBLE → 选择DRAM
reg [7:0]  cmd_rg              ;  // 保存最近识别到的上位机命令或前导码，区分当前下载目标是IRAM还是DRAM，调试用，已经有ram_sel_rg判断

//ACK回复通道
reg [31:0] ack_resp_rg         ;  // 保存ack阶段给上位机的应答（设备签名，成功/错误回复）
reg [1:0]  ack_byte_rg         ;  // ack阶段四个字节的索引，选择ACK回复中的当前字节
wire       is_ack_byte_zero    ;  // 表示当前是否已经处理到ACK的最后一个字节
reg        is_last_ack_byte_rg ;  // 最后一个ACK字节已提交给UART，等待UART发送完成

assign is_ack_byte_zero = (ack_byte_rg == 2'd0) ;

// RX data sampling and BIN stream related
reg [1:0]  sample_cnt_rg       ;  // 统计当前32位字段已经接收了几个UART字节
reg [31:0] pgm_size_rg         ;  // 总长度，有多少个字节的指令（每四个字节拼成一个指令）
wire [29:0] instr_cnt          ;  // 目标需要烧写的指令数，size寄存器除以4得到
reg [31:0] pgm_data_rg         ;  // 要写入的具体指令
reg [29:0] pgm_cnt_rg          ;  // 记录当前已经接收了多少个字

// Error flags
// -----------
// cmd_err        : sets on invalid command, cleared only on registering a valid command
// pgm_err        : sets on errors during IRAM/DRAM programming, cleared only after correct programming of IRAM/DRAM
// postamble_err  : sets on post-amble missing/error, cleared only after correct programming of IRAM/DRAM
reg        cmd_err_rg          ;  // 无效指令错误
reg        pgm_err_rg          ;  // 程序写入RAM过程错误，程序没有完整写入IRAM/DRAM，例：RAM地址已经到达边界，但目标数据还没传完
reg        postamble_err_rg    ;  // 下载协议结束标志错误，判断协议收到的最后的数据对不对 

//清空IRAM时，判断是否已经清到最后一个地址
//下载程序时，防止程序超过IRAM/DRAM容量
wire               is_ram_addr_ovflow ;//RAM地址到达最大值的标志，用来防止loader继续写入并发生地址回绕

// Control signals from Loader to RAM
reg               ram_sel_rg   ;  // RAM select: 0= IRAM, 1= DRAM
reg [31:0]        addr_cnt_rg  ;  // Address counter

assign ldr_rsp_ready = (state == RAM_WAIT) || (state == IRAM_CLN_WAIT);//请求已被接收，等待B通道写响应
assign ldr_req_valid = ((state == RAM_PGM) || (state == IRAM_CLN)) && !is_ram_addr_ovflow;//向loader_bridge发送写请求

//===================================================================================================================================================
// Loader FSM
//===================================================================================================================================================
//状态机1:用时序把next_state给state
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      state <= INIT; 
    else
      state <= next_state;
end

//状态机2组合块，根据state执行
always @(*)begin
   next_state = state;

   case (state)
      INIT:begin
         next_state = IDLE;
      end

      IDLE:begin
         if (uart_rxdata_valid)begin
            //表示uart收发器模块接受的上个字节有效且为设备签名请求信号
            if (uart_rxdata_valid && uart_rxdata == CMD_REQ_DEVC_SIGN)begin
               next_state = ACK;//进入ack状态，把设备签名给上位机，确认从机
            end
            //清空IRAM
            else if (uart_rxdata == CMD_BOOT_REQ_IRAM_CLN) begin
               next_state = IRAM_CLN;
            end

            // B0：不清空IRAM，直接执行CPU重启流程
            else if (uart_rxdata == CMD_BOOT_REQ) begin
               next_state = PGM_DONE;
            end
            //上位机连续发送4个C0，表示：接下来要下载的是指令程序，目标为IRAM,收到后开始接受程序长度状态
            else if (uart_rxdata == I_PREAMBLE)begin
               if (sample_cnt_rg == 2'd3) begin
                  next_state = READ_PGM_SIZE;
               end
            end
            //上位机连续发送4个D0，表示：接下来要下载的是指令程序，目标为DRAM,收到后开始接受程序长度状态
            else if (uart_rxdata == D_PREAMBLE) begin
               if (sample_cnt_rg == 2'd3) begin
                  next_state = READ_PGM_SIZE;
               end
            end
            //UART确实收到一个有效字节；但它不是签名请求；不是boot命令；不是IRAM前导码；也不是DRAM前导码。因此把它作为非法命令处理，进入ACK返回错误码
            else  begin
               next_state = ACK;
            end
         end
      end

      //第三段状态机里面，不断向IRAM写NOP，并递增地址
      IRAM_CLN: begin
         if (is_ram_addr_ovflow) begin//is_ram_addr_ovflow拉高表示地址达到IRAM末尾
            next_state = PGM_DONE;//进入数据传输完成阶段
         end
         else if(ldr_req_valid && ldr_req_ready)begin
            next_state = IRAM_CLN_WAIT;
         end
      end

      IRAM_CLN_WAIT: begin
         if (ldr_rsp_ready && ldr_rsp_valid) begin
            if (ldr_rsp_error)begin
               next_state = PGM_DONE;
            end
            else begin
               next_state = IRAM_CLN;
            end
         end
      end

      //上位机发送4个字节，用来表示本次下载的数据总长度
      //例如程序长度是16字节，上位机可能发送：00 00 00 10
      READ_PGM_SIZE: begin
         if (uart_rxdata_valid && sample_cnt_rg == 2'd3)
            next_state = READ_PGM_BADDR;//接收到数据总长度后进入下载地址状态
      end

      //再接收4个字节，表示程序应该从RAM的哪个地址开始写
      READ_PGM_BADDR: begin
         if (uart_rxdata_valid) begin
               if (sample_cnt_rg == 2'd3) begin
                  next_state = READ_PGM_BIN;//接收完4字节后，进入程序正文接收状态
               end
            end
      end

      //接收程序正文，UART一次只能收到8位，而IRAM/DRAM写接口一次写32位，所以要连续接收4个字节，第三段状态机把收到的四个字节拼成32bit
      READ_PGM_BIN: begin 
         //instr_cnt：目标值，一共需要写多少个字，pgm_size_rg得到，pgm_cnt_rg：进度值，目前已经写了多少个字
         if ((pgm_cnt_rg == instr_cnt) || is_ram_addr_ovflow) begin //地址满了或者指令数已经接收完毕，表示要的数据已经接收完毕             
            next_state   = (pgm_cnt_rg != instr_cnt)? PGM_DONE : READ_POSTAMBLE;//如果进度值不等于目标值，进入完成状态并报错，否则接收并检查程序结束标志              
         end
         else if (uart_rxdata_valid) begin
            if (sample_cnt_rg == 2'd3) begin
               next_state = RAM_PGM ;//每收到32bit数据就跳转到ram_pgm状态开始真正往ram里写数据
            end                 
         end
      end

      RAM_PGM : begin
         if (ldr_req_ready && ldr_req_valid)begin
            next_state  = RAM_WAIT;//每写完四个字节就跳回read_pgm_bin（这个状态时en拉低）状态继续接收下一个4字节的数据，直到指令发完或者地址满了            
         end
      end      

      RAM_WAIT : begin
         if (ldr_rsp_ready && ldr_rsp_valid) begin
            if (ldr_rsp_error)begin
               next_state = PGM_DONE;
            end
            else begin
               next_state = READ_PGM_BIN;
            end
         end
      end

      //检查结束标志（传输字节是否有效）
      READ_POSTAMBLE: begin
         //收到有效字节，并且等于 8'hE0：数据帧正常结束
         if (uart_rxdata_valid && (uart_rxdata == POSTAMBLE) && (sample_cnt_rg == 2'd3)) begin              
            next_state = PGM_DONE;                               
         end 
         //收到有效字节，但不等于 8'hE0：结束标志错误
         else if (uart_rxdata_valid && (uart_rxdata != POSTAMBLE)) begin
            next_state = PGM_DONE;  
         end     
      end

      ACK : begin           
         if (uart_tx_ready) begin
            if (is_last_ack_byte_rg) begin
               next_state = ack_exit_state_rg;//ACK回复发送完成后，状态机应该跳到哪个状态，发送完成后的去向可能不同，所以提前把返回状态保存在一个寄存器里面  
            end  
         end
      end

      PGM_DONE : begin
         next_state = ACK;
      end    

      default: next_state = INIT;
   endcase
end

//FPGA 上电
//  ↓
//loader 初始化
//  ↓
//CPU 先执行 IRAM 中已有程序
//  ↓
//如果电脑发来下载命令
//  ↓
//loader 再复位并暂停 CPU
//  ↓
//覆盖程序 RAM
//  ↓
//重新启动 CPU
//状态机3，按照时序逻辑给输出信号赋值
always @(posedge clk or negedge rst_n) begin
   if (!rst_n) begin
      cpu_reset_rg        <= 1'b0 ;
      cpu_stall_rg        <= 1'b0 ;

      uart_tx_en_rg       <= 1'b0 ;       
      uart_rx_en_rg       <= 1'b0 ;       
      uart_txdata_rg      <= 'd0   ;     
      uart_txdata_valid_rg<= 1'b0 ;                      
      
      cmd_rg              <= 'd0   ;
      ack_resp_rg         <= 'd0   ;
      ack_byte_rg         <= 2'd0 ;
      is_last_ack_byte_rg <= 1'b0 ;
      ack_exit_state_rg <= IDLE;
      
      ram_sel_rg    <= 1'b0  ;
      addr_cnt_rg   <= 32'd0 ;

      sample_cnt_rg <= 2'd0  ;
      pgm_size_rg   <= 32'd0 ;
      pgm_data_rg   <= 32'd0 ;
      pgm_cnt_rg    <= 30'd0 ;

      cmd_err_rg       <= 1'b0 ;      
      pgm_err_rg       <= 1'b0 ;
      postamble_err_rg <= 1'b0 ;
      
      o_init_done <= 1'b0 ;
      o_busy      <= 1'b0 ;
      o_pgm_done  <= 1'b0 ; 
   end

   // Out of Reset
   else begin
      case (state)
         // ---------------------------------------------------------------------------------------
         // INIT state
         // ---------------------------------------------------------------------------------------
         // Set initial states of UART, CPU signals...
         // ---------------------------------------------------------------------------------------
         INIT : begin
            // UART RX : Enabled for command reception
            // UART TX : Disabled for power saving
            // CPU     : Released out of reset and no stall, in execute state 
            uart_rx_en_rg <= 1'b1 ;//允许FPGA接收电脑通过串口发来的字节 
            uart_tx_en_rg <= 1'b0 ;//关闭UART发送器
            cpu_reset_rg  <= 1'b1 ;//释放cpu复位 
            cpu_stall_rg  <= 1'b0 ;//取消暂停
            o_init_done   <= 1'b1 ;//Initialization done            
         end
         
         // ---------------------------------------------------------------------------------------
         // IDLE state
         // ---------------------------------------------------------------------------------------
         // Wait here until a command is received via UART RX
         // ---------------------------------------------------------------------------------------
         IDLE : begin
            
            // rx收到请求设备签名的D3
            if (uart_rxdata_valid && uart_rxdata == CMD_REQ_DEVC_SIGN) begin 
               // Register the command  
               cmd_rg     <= CMD_REQ_DEVC_SIGN ;//设备签名控制指令
               cmd_err_rg <= 1'b0 ;//无错误

               // Clear sample counter on any other command than PREAMBLE
               sample_cnt_rg <= 2'd0 ;//采样计数器清零
               
               // Set up command ACK               
               // ACK response = Device Signature, size = 4 bytes  
               ack_resp_rg       <= DEVC_SIGN  ; //准备返回的设备签名 
               ack_byte_rg       <= 2'd3       ; //设置发送字节索引，32位的设备签名分4个字节发送
               ack_exit_state_rg <= IDLE       ; //ack应答后返回总线空闲状态                                           
            end

            //处理两个启动控制命令
            else if (uart_rxdata_valid && ((uart_rxdata == CMD_BOOT_REQ_IRAM_CLN) || (uart_rxdata == CMD_BOOT_REQ))) begin
               // 无错误，调试信号接uart发送数据               
               cmd_rg     <= uart_rxdata ;//保存当前命令
               cmd_err_rg <= 1'b0 ;

               //采样计数器清零
               sample_cnt_rg <= 2'd0 ;

               //总线忙
               //下载未完成
               o_busy     <= 1'b1  ;
               o_pgm_done <= 1'b0  ;                                

               // IRAM清除，B1 = 1011_0001，最低位为1，后面clean状态用nop清空iram           
               if (uart_rxdata[0]) begin
                  cpu_reset_rg <= 1'b0     ;  // cpu保持复位   
                  cpu_stall_rg <= 1'b1     ;  // 暂停流水线
                  ram_sel_rg   <= 1'b0     ;  //选择iram    

                  addr_cnt_rg       <= 32'd0;
                  pgm_err_rg        <= 1'b0;
                  postamble_err_rg  <= 1'b0;                             
               end
               // 重启B0 = 1011_0000，最低位为0，先复位 CPU，但不接管 IRAM，恢复pc地址，清空流水线寄存器，清空控制状态，但不修改iram，dram
               else begin
                  cpu_reset_rg <= 1'b0     ;  // Assert CPU reset
                  cpu_stall_rg <= 1'b0     ;  // No transfer of IRAM control reqd...                  
               end
            end

            //识别接下来要下载 IRAM 指令程序的前导码
            else if (uart_rxdata_valid && (uart_rxdata == I_PREAMBLE)) begin
               pgm_cnt_rg        <= 30'd0;
               pgm_err_rg        <= 1'b0;
               postamble_err_rg  <= 1'b0;
               //如果前导码有改变，就重置采样计数器
               if (cmd_rg == D_PREAMBLE) begin
                  sample_cnt_rg <= 2'd1 ;
               end
               else begin
                  sample_cnt_rg <= sample_cnt_rg + 1 ;
               end

               // 保存收到的前导码 
               cmd_rg     <= I_PREAMBLE ;
               cmd_err_rg <= 1'b0 ;

               // 收到四个字节，表示采样成功  
               if (sample_cnt_rg == 2'd3) begin    
                  cpu_reset_rg <= 1'b0 ;  // 要开始下载，所以复位cpu   
                  cpu_stall_rg <= 1'b1 ;  // 要开始下载，所以暂停流水线
                  ram_sel_rg   <= 1'b0 ;

                  // Reset programming status
                  // Set Loader status = BUSY
                  o_busy     <= 1'b1  ;
                  o_pgm_done <= 1'b0  ;                                                   
               end
            end

            //识别接下来要下载 DRAM 指令程序的前导码
            else if (uart_rxdata_valid && (uart_rxdata == D_PREAMBLE)) begin
               pgm_cnt_rg        <= 30'd0;
               pgm_err_rg        <= 1'b0;
               postamble_err_rg  <= 1'b0;
               //如果前导码有改变，就重置采样计数器
               if (cmd_rg == I_PREAMBLE) begin
                  sample_cnt_rg <= 2'd1 ;
               end
               else begin
                  sample_cnt_rg <= sample_cnt_rg + 1 ;
               end

               // 保存收到的前导码              
               cmd_rg     <= D_PREAMBLE ;
               cmd_err_rg <= 1'b0 ; 

               // 收到四个字节，表示采样成功   
               if (sample_cnt_rg == 2'd3) begin    
                  cpu_reset_rg <= 1'b0 ;  // 要开始下载，所以复位cpu   
                  cpu_stall_rg <= 1'b1 ;  // 要开始下载，所以暂停流水线
                  ram_sel_rg   <= 1'b1 ;

                  // Reset programming status
                  // Set Loader status = BUSY
                  o_busy     <= 1'b1  ;
                  o_pgm_done <= 1'b0  ;                                                   
               end
            end

            // 无效指令
            else if (uart_rxdata_valid) begin                
               // Register the command with error             
               cmd_rg     <= uart_rxdata ;//保存错误指令
               cmd_err_rg <= 1'b1 ;//报错

               // 清除采样计数器
               sample_cnt_rg <= 2'd0 ;

               //准备向电脑返回一个字节的非法命令错误码 
               ack_resp_rg       <= {24'h0, ERROR_CMD_INVALID} ;  //拼成32位应答寄存器
               ack_byte_rg       <= 2'd0 ;//byte计数器置0，在ack阶段去除最后一个字节（错误码）  
               ack_exit_state_rg <= IDLE ;//总线重回空闲状态                            
            end            
         end         
         
         // ---------------------------------------------------------------------------------------
         // IRAM Clean state
         // ---------------------------------------------------------------------------------------
         // Cleans IRAM by overwriting every data with NOP instruction
         // ---------------------------------------------------------------------------------------
         //iram清除，把整个指令存储器 IRAM 填成 NOP，不是填成全0
         IRAM_CLN : begin
            if (is_ram_addr_ovflow) begin
               addr_cnt_rg      <= 32'd0;
               pgm_err_rg       <= 1'b0;
               postamble_err_rg <= 1'b0;
            end
         end
         
         //响应成功后回到cln，并将地址加4，插下一个nop
         IRAM_CLN_WAIT : begin
            if (ldr_rsp_valid && ldr_rsp_ready) begin
               if (ldr_rsp_error) begin
                     pgm_err_rg <= 1'b1;
               end
               else begin
                     addr_cnt_rg <= addr_cnt_rg + 32'd4;
               end
            end
         end
         // ---------------------------------------------------------------------------------------
         // Read Program Size state        
         // ---------------------------------------------------------------------------------------         
         READ_PGM_SIZE : begin
            if (uart_rxdata_valid) begin
               sample_cnt_rg      <= sample_cnt_rg + 1  ;
               pgm_size_rg[7:0]   <= uart_rxdata        ;
               pgm_size_rg[15:8]  <= pgm_size_rg[7:0]   ;
               pgm_size_rg[23:16] <= pgm_size_rg[15:8]  ; 
               pgm_size_rg[31:24] <= pgm_size_rg[23:16] ;
            end
         end

         // ---------------------------------------------------------------------------------------
         // Read Program Base Address state        
         // ---------------------------------------------------------------------------------------
         //每次左移一个字节，把收到的一个字节拼进来
         READ_PGM_BADDR : begin
            if (uart_rxdata_valid) begin
               sample_cnt_rg      <= sample_cnt_rg + 1  ;//记录收到了几个字节，满4个进入READ_PGM_BIN
               addr_cnt_rg[7:0]   <= uart_rxdata        ;
               addr_cnt_rg[15:8]  <= addr_cnt_rg[7:0]   ;
               addr_cnt_rg[23:16] <= addr_cnt_rg[15:8]  ; 
               addr_cnt_rg[31:24] <= addr_cnt_rg[23:16] ;
            end
         end         
         
         // ---------------------------------------------------------------------------------------
         // Read Program Binary state     
         // ---------------------------------------------------------------------------------------
         // Read incoming binary stream, buffer the 32-bit instruction/data to be written to RAM   
         // ---------------------------------------------------------------------------------------
         //接收程序正文
         READ_PGM_BIN : begin
            // All instructions written or address overflow happened...
            if ((pgm_cnt_rg == instr_cnt) || is_ram_addr_ovflow) begin//判断是否结束  
               // Reset counters, RAM address
               pgm_cnt_rg   <=  0 ; 
               addr_cnt_rg  <=  0 ;                 
               pgm_err_rg   <= (pgm_cnt_rg != instr_cnt);  //程序长度与要写进去的指令个数不相等              
            end
            //写入ddr
            else if (uart_rxdata_valid) begin
               sample_cnt_rg      <= sample_cnt_rg + 1  ;
               pgm_data_rg[7:0]   <= uart_rxdata        ;
               pgm_data_rg[15:8]  <= pgm_data_rg[7:0]   ;
               pgm_data_rg[23:16] <= pgm_data_rg[15:8]  ; 
               pgm_data_rg[31:24] <= pgm_data_rg[23:16] ;              
            end
         end

         // ---------------------------------------------------------------------------------------
         // Program RAM state     
         // ---------------------------------------------------------------------------------------
         // Write the buffered instruction/data to RAM
         // ---------------------------------------------------------------------------------------
         //把拼好的数据写入ram，后面会根据sel判断是给iram还是dram
         RAM_PGM : begin
  
         end

         RAM_WAIT : begin
            if(ldr_rsp_ready && ldr_rsp_valid)begin
               if (ldr_rsp_error) begin
                  // AXI BRESP返回错误
                  pgm_err_rg <= 1'b1;
               end
               //一次成功响应表示一次传输完成，程序数索引+1，地址+4、
               else begin
                  addr_cnt_rg <= addr_cnt_rg + 4 ;  
                  pgm_cnt_rg  <= pgm_cnt_rg + 1  ;
               end                
            end    
         end

         // ---------------------------------------------------------------------------------------
         // Read Post-amble state     
         // ---------------------------------------------------------------------------------------
         //检查程序数据后面的结束标记         
         READ_POSTAMBLE: begin
            if (uart_rxdata_valid && (uart_rxdata == POSTAMBLE)) begin
               sample_cnt_rg <= sample_cnt_rg + 1 ;//每收到一个E0，计数器+1
               // Post-amble successfully sampled...
               if (sample_cnt_rg == 2'd3) begin
                  postamble_err_rg <= 1'b0     ;  // Success, no errors                                             
               end
            end 
            // Post-amble byte sequence violated...
            else if (uart_rxdata_valid && (uart_rxdata != POSTAMBLE)) begin
               sample_cnt_rg    <= 2'd0     ;
               postamble_err_rg <= 1'b1     ;  // Set error
            end     
         end

         // ---------------------------------------------------------------------------------------
         // ACK state
         // ---------------------------------------------------------------------------------------
         // Acknowledge the command received/BIN stream by sending back the ACK via UART TX
         // ---------------------------------------------------------------------------------------
         //给上位机的应答
         ACK : begin
            // 打开uart发送器
            uart_tx_en_rg <= 1'b1 ;  
          
            // UART TX is ready to accept byte            
            if (uart_tx_ready) begin
               // Send ACK byte to UART TX buffer
               if (!is_last_ack_byte_rg) begin
                  uart_txdata_rg        <= ack_resp_rg[(ack_byte_rg*8)+:8] ;  // 选择要发送的字节
                  uart_txdata_valid_rg  <= 1'b1 ; //字节有效                 
                  ack_byte_rg           <= (is_ack_byte_zero)? ack_byte_rg : (ack_byte_rg - 2'd1) ;//准备下一个字节的索引
                  is_last_ack_byte_rg   <= (is_ack_byte_zero) ;//判断当前是不是最后一个字节
               end     
               // 发送结束复位
               else begin
                  is_last_ack_byte_rg  <= 1'b0 ;  // Reset the flag
                  uart_txdata_valid_rg <= 1'b0 ;  
                  uart_tx_en_rg        <= 1'b0 ;  // Disable UART TX
               end  
            end
         end

         // ---------------------------------------------------------------------------------------
         // Programming Done state
         // ---------------------------------------------------------------------------------------
         // After every command other than DEVICE SIGNATURE REQUEST, Loader reaches this state.
         // After BIN stream, Loader reaches this state.
         // Log programming status, initiate ACK.
         // Put CPU back in execute state if no errors...else CPU should remain reset
         // ---------------------------------------------------------------------------------------
         //下载完成状态         
         PGM_DONE : begin
            o_busy     <= 1'b0 ;
            if (pgm_err_rg || postamble_err_rg) begin
               // 下载错误，CPU继续保持复位
               cpu_reset_rg <= 1'b0;
               cpu_stall_rg <= 1'b1;
               o_pgm_done   <= 1'b0;
            end
            else if ((cmd_rg == CMD_BOOT_REQ) ||
                     (cmd_rg == CMD_BOOT_REQ_IRAM_CLN)) begin
               // 只有收到B0，或者B1清除完成，才启动CPU
               cpu_reset_rg <= 1'b1;
               cpu_stall_rg <= 1'b0;
               o_pgm_done   <= 1'b1;
            end
            else begin
               // C0/D0下载完成，只返回成功，CPU仍保持复位,只有B0/B1时候启动
               cpu_reset_rg <= 1'b0;
               cpu_stall_rg <= 1'b1;
               o_pgm_done   <= 1'b1;
            end
            // Set up command ACK               
            // ACK response = SUCCESS if no errors, else ERROR code; size = 1 byte
            //如果有错误，根据错误类型准备错误码  
            if (postamble_err_rg) begin
               ack_resp_rg <= {24'h0, ERROR_POSTAMBLE} ;  // Post-amble Error
            end 
            else if (pgm_err_rg) begin
               ack_resp_rg <= {24'h0, ERROR_PGM} ;  // Programming Error
            end
            else begin
               ack_resp_rg <= {24'h0, SUCCESS} ;  // Programming success, no errors
            end
            ack_byte_rg       <= 2'd0 ;
            ack_exit_state_rg <= IDLE ;
         end         
         
         // Default state
         default    : ;

      endcase     
   end

end

// RAM de-mux to route RAM control signals to IRAM or/and DRAM
always @(*) begin
   ldr_req_wdata = (state == IRAM_CLN) ? INSTR_NOP : pgm_data_rg;
   ldr_req_wstrb = 4'b1111;
   case (ram_sel_rg)      
      // IRAM selected
      1'b0: begin
         ldr_req_addr = `DDR_INST_BASE + addr_cnt_rg ;
      end
      // DRAM selected
      1'b1: begin
          ldr_req_addr = `DDR_DATA_BASE + addr_cnt_rg ;      
      end
      default: ldr_req_addr = 32'd0;
   endcase
end

//判断是否溢出
assign is_ram_addr_ovflow = ram_sel_rg? (addr_cnt_rg >= DATA_REGION_BYTES) : (addr_cnt_rg >= INST_REGION_BYTES) ;

//=========================================================================================================================================
// Timeout logic
//=========================================================================================================================================
reg [31:0] timer_rg      ;  // 定时器计数器
wire       timer_en      ;  // 定时器使能
wire       is_timer_zero ;  // Timer underflow flag
reg        timeout_rg    ;  // Programming timeout; sets when timeout happens in Loader FSM, cleared only on reset
                              // NOTE: If timeout happens, the system including Loader MUST BE reset, as the current state is undefined

//loader超时保护，loader进入下载状态后开始倒计时；如果长时间没有完成操作，计时到0，就把timeout_rg置1，报告超时错误
always @(posedge clk or negedge rst_n) begin
   // Reset
   if (!rst_n) begin
      timeout_rg <= 1'b0    ;
      timer_rg   <= TIMEOUT ;
   end
   //IDLE状态时，重置定时器
   else if (!timer_en) begin
      timer_rg <= TIMEOUT;
   end
   //每收到一个字节就重装计数器
   else if (uart_rxdata_valid) begin
      timer_rg <= TIMEOUT;
   end
   //没有收到数据，也没有计时到0，继续倒计时
   else if (!is_timer_zero) begin
      timer_rg <= timer_rg - 1'b1;
   end
   // 倒计时结束
   else begin
      timeout_rg <= 1'b1;
   end
end

assign timer_en      = (state != IDLE) ;  // Timer triggered when Loader becomes busy with processing command/programming...
assign is_timer_zero = (~|timer_rg) ;//判断timer_rg所有位是不是全都是0
//=========================================================================================================================================

// RX ack
// ------
// Always ack immediately when in UART RX data sampling states...
// valid ___/``\___
// ack  ____/``\___
assign uart_rx_ack = uart_rxdata_valid && ((state == IDLE) || (state == READ_PGM_SIZE) || 
                     (state == READ_PGM_BIN) || (state == READ_PGM_BADDR) || (state == READ_POSTAMBLE)) ;

// Counts
assign instr_cnt = pgm_size_rg[31:2] ;  // instr_cnt = 程序总字节数 / 4

// UART instance
top_uart #(
    .clk_freq (clk_freq),
    .uart_bps (uart_bps)
)u_top_uart (
   .sys_clk             (clk)       ,  
   .sys_rst_n           (rst_n)   ,

   .uart_txd           (o_uart_tx) ,
   .uart_rxd           (i_uart_rx) ,
    
   .uart_tx_en     (uart_tx_en_rg) ,  //写使能信号 
   .uart_rx_en     (uart_rx_en_rg) ,        
      
   .uart_tx_data   (uart_txdata_rg)       ,  //传回上位机的数据，发送应答信息
   .uart_tx_valid  (uart_txdata_valid_rg) ,  //
   .uart_tx_ready (uart_tx_ready)       ,  //tx总线不忙表示准备好了

   .uart_rx_data   (uart_rxdata)       ,  
   .uart_rx_valid  (uart_rxdata_valid) , 
   .uart_rx_ready  (uart_rx_ack)       ,  
   
   .o_frame_err    (uart_error)                                      
);

// 时钟同步，让外部的halt_cpu信号同步到cpu内部
wire halt_cpu_sync ;
cdc_sync #(
   .STAGES (2)
)  inst_sync_halt_cpu (
   .clk        (clk)          ,        
   .rst_n       (rst_n)      ,       
   .i_sig      (i_halt_cpu)   ,     
   .o_sig_sync (halt_cpu_sync)     
);

// Control/Reset signals to CPU
assign o_ldr_cpu_reset = ~halt_cpu_sync & cpu_reset_rg ;
assign o_ldr_cpu_stall = cpu_stall_rg ;

// Error signal out
assign o_err      = cmd_err_rg || pgm_err_rg || postamble_err_rg || timeout_rg || uart_error;
assign o_err_code = {cmd_err_rg, pgm_err_rg, postamble_err_rg, timeout_rg, uart_error}   ;

assign o_debug_ram_sel = ram_sel_rg;
endmodule