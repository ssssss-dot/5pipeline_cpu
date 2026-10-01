`ifndef _Def
`define _Def
`define ID_BRANCHES
`define ID_JALR
//seldom used in fact
`define ZeroWord		32'h00000000
`define WriteEnable	1'b1
`define WriteDisable	1'b0
`define ReadEnable		1'b1
`define ReadDisable	1'b0
`define InstValid		1'b1 
`define InstInvalid	1'b0
`define InstAddrBus	31: 0
`define InstBus		31: 0
`define InstAddrWidth	32
`define InstMemNum		32768
`define InstMemNumLog2	15
`define ChipEnable		1'b1
`define ChipDisable	1'b0
// regfile
`define RegAddrBus		4: 0
`define RegAddrWidth	5
`define RegBus			31: 0
`define RegWidth		32
`define NOPRegAddr		5'b00000
// 数据存储器
`define DataAddrBus     31:0
`define DataBus         31:0
`define DataMemNum      32768
`define DataMemNumLog2  15
`define ByteWidth       7:0
//aluex
`define AluOpBus		10:0
`define AluOutSelBus	2:0
`define AluSrc1SelBus  1:0
`define AluSrc2SelBus  1:0

`define ALU_SRC1_RS1   2'b00
`define ALU_SRC1_PC    2'b01
`define ALU_SRC1_ZERO  2'b10

`define ALU_SRC2_RS2   2'b00
`define ALU_SRC2_IMM   2'b01
`define ALU_SRC2_FOUR  2'b10
`define CSR_SEL        2'b11

`define EX_ADD_OP		11'b00100110000
`define EX_SUB_OP 		11'b00100110001
`define EX_SLT_OP		11'b00100110100
`define EX_SLTU_OP		11'b00100110110
`define EX_XOR_OP		11'b00100111000
`define EX_OR_OP 		11'b00100111100
`define EX_AND_OP		11'b00100111110
`define EX_SLL_OP		11'b00100110010
`define EX_SRL_OP		11'b00100111010
`define EX_SRA_OP		11'b00100111011 

`define EX_JAL_OP 		11'b11011110000
`define EX_JALR_OP		11'b11001110000
`define EX_BEQ_OP 		11'b11000110000
`define EX_BNE_OP 		11'b11000110010
`define EX_BLT_OP 		11'b11000111000
`define EX_BGE_OP 		11'b11000111010
`define EX_BLTU_OP		11'b11000111100
`define EX_BGEU_OP		11'b11000111110

`define EX_LB_OP 		11'b00000110000
`define EX_LH_OP 		11'b00000110010
`define EX_LW_OP 		11'b00000110100
`define EX_LBU_OP		11'b00000111000
`define EX_LHU_OP		11'b00000111010

`define EX_SB_OP		11'b01000110000
`define EX_SH_OP		11'b01000110010
`define EX_SW_OP		11'b01000110100

`define EX_NOP_OP		11'b00000000000
//cmp执行阶段指令
`define EX_CMP_OP       11'b00100110011
`define EX_CMPU_OP      11'b00100110101//无符号比较

`define EX_RES_LOGIC	3'b001
`define EX_RES_SHIFT	3'b010
`define EX_RES_ARITH	3'b011
`define EX_RES_J_B  	3'b100
`define EX_RES_LD_ST	3'b101
`define EX_RES_NOP		3'b000
//id
`define PC_addr     5'h20

`define OP_LUI      7'b0110111
`define OP_AUIPC    7'b0010111
`define OP_JAL      7'b1101111
`define OP_JALR     7'b1100111
`define OP_BRANCH   7'b1100011
`define OP_LOAD     7'b0000011
`define OP_STORE    7'b0100011
`define OP_OPI		7'b0010011
`define OP_OP       7'b0110011
`define OP_MISC_MEM 7'b0001111
//自定义compare指令
`define OP_CMP      7'b0001011

`define FUNCT3_JALR 3'b000
`define FUNCT3_BEQ  3'b000
`define FUNCT3_BNE  3'b001
`define FUNCT3_BLT  3'b100
`define FUNCT3_BGE  3'b101
`define FUNCT3_BLTU 3'b110
`define FUNCT3_BGEU 3'b111
`define FUNCT3_LB   3'b000
`define FUNCT3_LH   3'b001
`define FUNCT3_LW   3'b010
`define FUNCT3_LBU  3'b100
`define FUNCT3_LHU  3'b101
`define FUNCT3_SB   3'b000
`define FUNCT3_SH   3'b001
`define FUNCT3_SW   3'b010

`define FUNCT3_ADDI      3'b000
`define FUNCT3_SLTI      3'b010
`define FUNCT3_SLTIU     3'b011
`define FUNCT3_XORI      3'b100
`define FUNCT3_ORI       3'b110
`define FUNCT3_ANDI      3'b111
`define FUNCT3_SLLI      3'b001
`define FUNCT3_SRLI_SRAI 3'b101

`define FUNCT3_ADD_SUB 3'b000
`define FUNCT3_SLL     3'b001
`define FUNCT3_SLT     3'b010
`define FUNCT3_SLTU    3'b011
`define FUNCT3_XOR     3'b100
`define FUNCT3_SRL_SRA 3'b101
`define FUNCT3_OR      3'b110
`define FUNCT3_AND     3'b111

`define FUNCT3_FENCE  3'b000
`define FUNCT3_FENCEI 3'b001
//cmp指令自定义
`define FUNCT3_CMP    3'b000
`define FUNCT3_CMPU   3'b001

`define FUNCT7_SLLI 1'b0
`define FUNCT7_SRLI 1'b0
`define FUNCT7_SRAI 1'b1
`define FUNCT7_ADD  1'b0
`define FUNCT7_SUB  1'b1
`define FUNCT7_SLL  1'b0
`define FUNCT7_SLT  1'b0
`define FUNCT7_SLTU 1'b0
`define FUNCT7_XOR  1'b0

`define FUNCT7_SRL 1'b0
`define FUNCT7_SRA 1'b1
`define FUNCT7_OR  1'b0
`define FUNCT7_AND 1'b0
//自定义指令
`define FUNCT7_CMP  1'b0
`define FUNCT7_CMPU 1'b0

//判断wb的数据来源
`define WbSelBus 1:0
`define WB_SEL_ALU  2'b00//alu运算结果写回，add/addi/lui/auipc
`define WB_SEL_MEM  2'b01//根据运算出的地址，写回存储器读出的值，lb/lh/lw/lbu/lhu
`define WB_SEL_PC4  2'b10//将pc+4写回jal/jalr
`define WB_SEL_NONE 2'b11

//判断访存指令要做哪种操作
`define MemOpBus 3:0
`define MEM_NONE 4'b0000
`define MEM_LB   4'b0001//从内存里读 1 个字节（8 位）再做符号扩展到 32 位
`define MEM_LH   4'b0010//从内存里读 2 个字节（16 位）再做符号扩展到 32 位
`define MEM_LW   4'b0011//从内存里读 4 个字节（32 位）直接作为 32 位结果，不需要额外扩展
`define MEM_LBU  4'b0100//从内存里读 1 个字节再做零扩展到 32 位（注意与lb的区别）
`define MEM_LHU  4'b0101//从内存里读 2 个字节再做零扩展到 32 位（注意与lh的区别）
`define MEM_SB   4'b0110//往内存里写 1 个字节写入的数据一般来自 rs2 的低 8 位
`define MEM_SH   4'b0111//往内存里写 2 个字节写入的数据一般来自 rs2 的低 16 位
`define MEM_SW   4'b1000//把一个 32 位字 写到内存里

`define NOP_INST 32'h00000013   //空指令

`define UART_TX_ADDR 32'h4000_0000//dram里面的地址分配，到32'h1000_0000时就把数据给uart_tx打印出来 

//ddr 的地址规划
`define DDR_INST_BASE 32'h0000_0000
`define DDR_DATA_BASE 32'h1000_0000

//虚拟地址空间
`define CPU_DATA_BASE 32'h8000_0000
`define CPU_INST_BASE 32'h0000_0000

//axi协议的参数
//Crossbar有3个输入源，会在输出ID前追加2位源编号（判断是icache，dcache还是ldr）；5位输入ID追加后正好匹配8位MIG ID。
`define AXI_S_ID_WIDTH         5
`define AXI_M_ID_WIDTH         8
`define AXI_LEN_SINGLE        8'd0
`define AXI_SIZE_1B           3'd0
`define AXI_SIZE_2B           3'd1
`define AXI_SIZE_4B           3'd2
`define AXI_SIZE_8B           3'd3
`define AXI_BURST_FIXED       2'b00
`define AXI_BURST_INCR        2'b01
`define AXI_BURST_WRAP        2'b10

//ARPROT[2]：0=数据访问，1=指令访问
//ARPROT[1]：0=Secure，1=Non-secure
//ARPROT[0]：0=非特权，1=特权访问
`define AXI_PROT_NORMAL       3'b000
`define AXI_PROT_INSTRUCTION  3'b100

`define AXI_CACHE_NORMAL      4'b0011
`define AXI_ID_DEFAULT        '0
`define AXI_LOCK_NORMAL       1'b0
`define AXI_QOS_DEFAULT       4'b0000
`define AXI_REGION_DEFAULT    4'b0000
`define AXI_USER_DEFAULT      '0

// AXI单拍aw/w通道的固定属性
`define AXI_AWID_DEFAULT      `AXI_ID_DEFAULT
`define AXI_AWLEN_SINGLE      `AXI_LEN_SINGLE
`define AXI_AWBURST_INCR      `AXI_BURST_INCR
`define AXI_AWLOCK_NORMAL     `AXI_LOCK_NORMAL
`define AXI_AWCACHE_NORMAL    `AXI_CACHE_NORMAL
`define AXI_AWPROT_NORMAL     `AXI_PROT_NORMAL
`define AXI_AWQOS_DEFAULT     `AXI_QOS_DEFAULT
`define AXI_AWREGION_DEFAULT  `AXI_REGION_DEFAULT
`define AXI_AWUSER_DEFAULT    `AXI_USER_DEFAULT
`define AXI_WLAST_SINGLE      1'b1
`define AXI_WUSER_DEFAULT     `AXI_USER_DEFAULT

//dma寄存器地址
`define DMA_SRC_BASE 32'h4000_4000//从ddr的哪个地址开始读
`define DMA_DST_BASE 32'h4000_4004//处理好的地址从ddr的哪个地址开始写
`define DMA_RDLEN_BASE 32'h4000_4008//处理的读字节数
`define DMA_WRLEN_BASE 32'h4000_4018//处理的写字节数
`define DMA_CONTROL_ADDR   32'h4000_400C//决定是否启用中断
`define DMA_STATUS_ADDR    32'h4000_4010//状态寄存器（只读）
`define DMA_IRQ_CLEAR_ADDR 32'h4000_4014//清中断
// IRQ_STATUS[0]：AXI读端完成
// IRQ_STATUS[1]：AXI写端完成
// IRQ_STATUS[2]：AXI读端错误
// IRQ_STATUS[3]：AXI写端错误
`define DMA_IRQ_STATUS_ADDR 32'h4000_401C//记录中断的原因
`define DMA_IRQ_ENABLE_ADDR  32'h4000_4020//使能哪个中断，由外部程序配置
`define DMA_RD_BYTE_OFFSET_ADDR 32'h4000_4024//判断每次搬运时的偏移
`define DMA_WR_BYTE_OFFSET_ADDR 32'h4000_4028//判断每次搬运时的偏移

//csr中断相关指令和寄存器
`define CsrAddrBus 11:0
`define CsrDataBus 31:0
`define CsrCmdBus  2:0

//opcode
`define OP_SYSTEM 7'b1110011

//csr相关寄存器地址
`define CSR_MSTATUS 12'h300
`define CSR_MIE     12'h304
`define CSR_MTVEC   12'h305
`define CSR_MEPC    12'h341
`define CSR_MCAUSE  12'h342
`define CSR_MIP     12'h344

//funct3
`define CSR_CMD_NONE   3'b000
`define CSR_CMD_CSRRW  3'b001//rd写入csr的旧值，将rs1的新的值写到csrfile（改变寄存器的配置）
`define CSR_CMD_CSRRS  3'b010//rd为旧值，将rs1和csr旧值每位做或操作写入csrfile
`define CSR_CMD_CSRRC  3'b011//csr_wdata = csr_rdata & ~rs1_data;
`define CSR_CMD_CSRRWI 3'b101//rd为旧值，CSR ← {27'b0, zimm}，zimm只有5位
`define CSR_CMD_CSRRSI 3'b110//rd为旧值，CSR ← CSR旧值 | {27'b0, zimm}
`define CSR_CMD_CSRRCI 3'b111//rd为旧值，CSR ← CSR旧值 & ~{27'b0, zimm}

//特权指令，识别到能直接跳回原指令
//ID识别mret
//→ 通过ID/EX传到EX
//→ EX确认mret有效
//→ PC跳转到mepc
//→ 冲刷mret后面已经取出的错误路径指令
`define INST_MRET 32'h3020_0073

//mstatus 寄存器的第三位是 MIE，MIE = Machine Interrupt Enable
//0：CPU当前不接受普通机器模式中断（有一个中断在处理）
//1：CPU当前允许机器模式中断
`define MSTATUS_MIE_BIT   3

//MPIE = Machine Previous Interrupt Enable（保存进中断之前的mie）
//mret时把备份的mstatus的MPIE写入mie
`define MSTATUS_MPIE_BIT  7

//MPP是 Machine Previous Privilege，表示“进入机器模式中断之前，CPU运行在哪个权限模式”，现在一直都在machine模式下
`define MSTATUS_MPP   12:11
`define PRIV_MODE_M   2'b11

//mie的11位， Machine External Interrupt Enable，外部中断使能
//MEIE=0：不允许DMA等外部中断
//MEIE=1：允许DMA等外部中断
`define MIE_MEIE_BIT  11 
//mip的11位， Machine External Interrupt Pending，外部中断挂起
//1表示有外部中断，可以直接接到dmairq
`define MIP_MEIP_BIT  11  

//irq_request =mstatus[3] &&mie[11] &&mip_value[11]

//mtvec的低2位，表示直连模式，所有中断跳转到同一个地址
//mtvec = 0x0000_1000
//DMA中断发生
//PC    = 0x0000_1000
`define MTVEC_MODE_DIRECT 2'b00

//发生中断的原因
`define MCAUSE_MACHINE_EXTERNAL_IRQ 32'h8000_000B

//通过读mmio_addr_mask，判断是否是mmio，mmio的地址范围是0x4000_0000-0x4000_FFFF
`define MMIO_BASE_ADDR  32'h4000_0000
`define MMIO_ADDR_MASK  32'hFFFF_0000

`define DMA_BASE_ADDR   32'h4000_4000
`define CONV_BASE_ADDR  32'h4000_5000
`define POOL_BASE_ADDR  32'h4000_6000
`define FC_BASE_ADDR    32'h4000_7000

// Conv配置寄存器：CPU MMIO字节地址，每个寄存器占4字节
`define CONV_CONTROL_ADDR     (`CONV_BASE_ADDR + 32'h00)// [0]启动，写1自清；[1]中断使能
`define CONV_STATUS_ADDR      (`CONV_BASE_ADDR + 32'h04)// [0]busy只读；[1]done、[2]error写1清除
`define CONV_INPUT_SHAPE_ADDR (`CONV_BASE_ADDR + 32'h08)// [15:0]输入宽度；[31:16]输入高度
`define CONV_CHANNELS_ADDR    (`CONV_BASE_ADDR + 32'h0C)// [15:0]输入通道数；[31:16]输出通道数
`define CONV_BIAS_BASE_ADDR   (`CONV_BASE_ADDR + 32'h10)// 寄存器内容[13:0]为bias的BRAM字地址
`define CONV_QUANT_MULT_ADDR  (`CONV_BASE_ADDR + 32'h14)// 重量化整数乘数
`define CONV_QUANT_SHIFT_ADDR (`CONV_BASE_ADDR + 32'h18)// [5:0]重量化右移位数
`define CONV_INPUT_BASE_ADDR  (`CONV_BASE_ADDR + 32'h1C)// 输入特征图在BRAM中的字节基地址
`define CONV_WEIGHT_BASE_ADDR (`CONV_BASE_ADDR + 32'h20)// 权重在BRAM中的字节基地址

//加速器共享64KB的ram
`define RAM_SIZE 0:16383
//ram地址分配

`endif
