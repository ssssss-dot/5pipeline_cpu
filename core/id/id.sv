//包含头文件
`include "define.sv"

//控制模块，由于是单周期，直接包含译码
module id(
    input [`InstBus ] inst_i,//输入得到的指令

    //ex需要的运算数据
    //if_id中得到的pc地址和pc+4
    input [`InstAddrBus] pc_i,
    input [`InstAddrBus] pc_plus4_i,

    //regfile里面读出来的rs1和rs2的数据，
    input [`RegBus] rs1_data_i,
    input [`RegBus] rs2_data_i,

    //寄存器堆里面两个做运算的数所存放的寄存器地址
    output [`RegAddrBus] rs1_o,
    output [`RegAddrBus] rs2_o,

    //写回的目的寄存器地址
    output [`RegAddrBus] rd_o,
    
    // 译码出来的立即数，送给 alu_src_mux / mux_pc
    output reg  [`RegBus] imm_o,

    //给regfile的使能
    output reg re1_o,
    output reg re2_o,
    output reg reg_we_o,

    //跳转，分支信号，
    output reg jump_flag_o,
    output reg branch_flag_o,
    output reg jalr_flag_o,

    //mem_op_o与aluop_o功能上有点重复，但是是不同阶段所需的数据，都保留

    //存储器相关的指令,给到mem的指令
    output reg  mem_re_o,//存储器读使能信号（load时拉高）
    output reg  mem_we_o,//存储器写使能信号（store时拉高）
    output reg [`MemOpBus] mem_op_o,//对存储器做什么指令
    output reg [`WbSelBus] wb_sel_o,//写回数据源选择

    //datamem选择控制器，目前不用管
    output reg fence_o,

    //alu控制,判断是哪种类型的操作，给到alu ex阶段的指令
	output reg [`AluOpBus]		aluop_o,

    //两个数据源的选择
	output reg  [`AluSrc1SelBus] alu_src1_sel_o,
    output reg  [`AluSrc2SelBus] alu_src2_sel_o,

    output [`InstAddrBus] pc_o,
    output [`InstAddrBus] pc_plus4_o,
    output [`RegBus] rs1_data_o,
    output [`RegBus] rs2_data_o,

    //csr控制，把从crs拿数据放到ex阶段
    output  [`CsrAddrBus] csr_addr_o,
    output reg [`CsrCmdBus]  csr_cmd_o,
    output reg csr_en_o,
    output reg mret_o

);

//运算数据直接经过id_stage给到寄存器打一拍
assign pc_o = pc_i;
assign pc_plus4_o = pc_plus4_i;
assign rs1_data_o = rs1_data_i;
assign rs2_data_o = rs2_data_i;

//rsicv指令中的每一块指令声明
wire[2:0]		funct3;
wire			funct7;
wire[6:0]		opcode;
wire[31:0]		imm_I;
wire[31:0]		imm_S;
wire[31:0]		imm_B;
wire[31:0]	 	imm_U;
wire[31:0]		imm_J;
wire[31:0]		zimm;

//取出指令对应的值
assign opcode		=	inst_i[6:0];
assign rd_o			=	inst_i[11:7];
assign funct3		=	inst_i[14:12];
assign rs1_o	    =	inst_i[19:15];
assign rs2_o		=	inst_i[24:20];
assign funct7		=	inst_i[30];
assign csr_addr_o   =   inst_i[31:20];

//根据指令生成立即数
assign imm_I        =   {{20{inst_i[31]}}, inst_i[31:20]};
assign imm_S        =   {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
assign imm_B		=	{{20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8],1'h0};
assign imm_U		=	{inst_i[31:12], 12'h0};
assign imm_J		=	{{12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21],1'h0};
assign zimm		    =	{27'h0, inst_i[19:15]};

//数据源选择
always @(*)begin
    //默认值
    re1_o          = `ReadDisable;
    re2_o          = `ReadDisable;
    reg_we_o       = `WriteDisable;

    imm_o          = `ZeroWord;
    aluop_o        = `EX_NOP_OP;
    alu_src1_sel_o = `ALU_SRC1_RS1;
    alu_src2_sel_o = `ALU_SRC2_RS2;

    jump_flag_o    = 1'b0;
    branch_flag_o  = 1'b0;
    jalr_flag_o    = 1'b0;

    mem_op_o = `MEM_NONE;
    wb_sel_o = `WB_SEL_NONE;

    csr_cmd_o = 'd0;
    csr_en_o  = 'd0;

    mem_re_o = 'd0;
    mem_we_o = 'd0;
    fence_o  = 'd0;
    mret_o   = 'd0;
        case (opcode)

        `OP_SYSTEM:begin
            // mret必须优先进行完整指令匹配
            if (inst_i == `INST_MRET) begin
                mret_o       = 1'b1;

                csr_en_o     = 1'b0;
                reg_we_o     = `WriteDisable;
                re1_o        = `ReadDisable;
                re2_o        = `ReadDisable;
            end
            else begin
                case(funct3)

                    `CSR_CMD_CSRRW,`CSR_CMD_CSRRS,`CSR_CMD_CSRRC:begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadDisable;
                        reg_we_o       = (rd_o != 5'd0);

                        imm_o          = `ZeroWord;
                        csr_cmd_o      = funct3;
                        wb_sel_o       = `WB_SEL_ALU;
                        aluop_o        = `EX_NOP_OP;
                        csr_en_o       = 1'b1;
                    end

                    `CSR_CMD_CSRRWI,`CSR_CMD_CSRRSI,`CSR_CMD_CSRRCI: begin
                        csr_en_o     = 1'b1;
                        csr_cmd_o    = funct3;

                        re1_o        = `ReadDisable;
                        re2_o        = `ReadDisable;

                        reg_we_o     = (rd_o != 5'd0);

                        wb_sel_o     = `WB_SEL_ALU;
                        aluop_o      = `EX_NOP_OP;

                        // zimm[4:0]零扩展到32位
                        imm_o        = zimm;
                    end

                    default: begin
                        csr_en_o = 1'b0;
                    end
                endcase
            
            end
        end

        `OP_LUI: begin
            wb_sel_o = `WB_SEL_ALU;
            // lui rd, imm
            re1_o          = `ReadDisable;
            re2_o          = `ReadDisable;
            reg_we_o       = `WriteEnable;

            imm_o          = imm_U;
            aluop_o        = `EX_ADD_OP;
            alu_src1_sel_o = `ALU_SRC1_ZERO;
            alu_src2_sel_o = `ALU_SRC2_IMM;
        end

        `OP_AUIPC:begin
            wb_sel_o = `WB_SEL_ALU;
            // auipc rd, imm
            re1_o          = `ReadDisable;
            re2_o          = `ReadDisable;
            reg_we_o       = `WriteEnable;

            imm_o          = imm_U;
            aluop_o        = `EX_ADD_OP;
            alu_src1_sel_o = `ALU_SRC1_PC;
            alu_src2_sel_o = `ALU_SRC2_IMM;
        end

        `OP_JAL: begin
            wb_sel_o = `WB_SEL_PC4;
            // jal rd, offset
            re1_o          = `ReadDisable;
            re2_o          = `ReadDisable;
            reg_we_o       = `WriteEnable;

            imm_o          = imm_J;
            aluop_o        = `EX_JAL_OP;
            alu_src1_sel_o = `ALU_SRC1_PC;
            alu_src2_sel_o = `ALU_SRC2_IMM;
            jump_flag_o    = 1'b1;
        end

        `OP_JALR:begin
            wb_sel_o       = `WB_SEL_PC4;
            re1_o          = `ReadEnable;
            re2_o          = `ReadDisable;
            reg_we_o       = `WriteEnable;

            imm_o          = imm_I;
            aluop_o        = `EX_JALR_OP;
            alu_src1_sel_o = `ALU_SRC1_RS1;
            alu_src2_sel_o = `ALU_SRC2_IMM;
            jalr_flag_o    = 1'b1;
        end

        `OP_BRANCH: begin
            wb_sel_o = `WB_SEL_NONE;
            mem_op_o = `MEM_NONE;
            branch_flag_o  = 1'b1;//分支跳转信号拉高
            case(funct3)
                `FUNCT3_BNE: begin
                //判断两个数是否不相等，不用回写
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = imm_B;
                    aluop_o        = `EX_BNE_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_BEQ: begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = imm_B;
                    aluop_o        = `EX_BEQ_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_BLT: begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = imm_B;
                    aluop_o        = `EX_BLT_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_BGE: begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = imm_B;
                    aluop_o        = `EX_BGE_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_BLTU: begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = imm_B;
                    aluop_o        = `EX_BLTU_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_BGEU: begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = imm_B;
                    aluop_o        = `EX_BGEU_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
            endcase
        end

        `OP_OP: begin
            wb_sel_o = `WB_SEL_ALU;
            case (funct3)
                `FUNCT3_ADD_SUB:begin
                    if (funct7 == `FUNCT7_ADD) begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadEnable;
                        reg_we_o       = `WriteEnable;

                        aluop_o        = `EX_ADD_OP;
                        alu_src1_sel_o = `ALU_SRC1_RS1;
                        alu_src2_sel_o = `ALU_SRC2_RS2;
                    end
                    else if(funct7 == `FUNCT7_SUB)begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadEnable;
                        reg_we_o       = `WriteEnable;

                        aluop_o        = `EX_SUB_OP;
                        alu_src1_sel_o = `ALU_SRC1_RS1;
                        alu_src2_sel_o = `ALU_SRC2_RS2;
                    end
                end
                `FUNCT3_XOR:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;

                    aluop_o        = `EX_XOR_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_OR:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;

                    aluop_o        = `EX_OR_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_AND:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;

                    aluop_o        = `EX_AND_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_SLL:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;

                    aluop_o        = `EX_SLL_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_SRL_SRA:begin
                    if (funct7 == `FUNCT7_SRL)begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadEnable;
                        reg_we_o       = `WriteEnable;

                        aluop_o        = `EX_SRL_OP;
                        alu_src1_sel_o = `ALU_SRC1_RS1;
                        alu_src2_sel_o = `ALU_SRC2_RS2;
                    end
                    else if (funct7 == `FUNCT7_SRA)begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadEnable;
                        reg_we_o       = `WriteEnable;

                        aluop_o        = `EX_SRA_OP;
                        alu_src1_sel_o = `ALU_SRC1_RS1;
                        alu_src2_sel_o = `ALU_SRC2_RS2;
                    end
                end
                `FUNCT3_SLT:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;

                    aluop_o        = `EX_SLT_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
                `FUNCT3_SLTU:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;

                    aluop_o        = `EX_SLTU_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;
                end
            endcase
        end

        `OP_OPI: begin
            wb_sel_o = `WB_SEL_ALU;
            case (funct3)
                `FUNCT3_ADDI:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_ADD_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;
                end
                `FUNCT3_XORI:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_XOR_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;
                end
                `FUNCT3_ORI:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_OR_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;
                end
                `FUNCT3_ANDI:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_AND_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;
                end
                `FUNCT3_SLLI:begin
                    if (funct7 == `FUNCT7_SLLI)begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadDisable;
                        reg_we_o       = `WriteEnable;

                        imm_o          = imm_I;
                        aluop_o        = `EX_SLL_OP;
                        alu_src1_sel_o = `ALU_SRC1_RS1;
                        alu_src2_sel_o = `ALU_SRC2_IMM;
                    end
                end
                `FUNCT3_SLTI:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_SLT_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;
                end
                `FUNCT3_SLTIU:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_SLTU_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;
                end
                `FUNCT3_SRLI_SRAI:begin
                    if(funct7 == `FUNCT7_SRLI)begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadDisable;
                        reg_we_o       = `WriteEnable;

                        imm_o          = imm_I;
                        aluop_o        = `EX_SRL_OP;
                        alu_src1_sel_o = `ALU_SRC1_RS1;
                        alu_src2_sel_o = `ALU_SRC2_IMM;
                    end
                    else if(funct7 == `FUNCT7_SRAI)begin
                        re1_o          = `ReadEnable;
                        re2_o          = `ReadDisable;
                        reg_we_o       = `WriteEnable;

                        imm_o          = imm_I;
                        aluop_o        = `EX_SRA_OP;
                        alu_src1_sel_o = `ALU_SRC1_RS1;
                        alu_src2_sel_o = `ALU_SRC2_IMM;
                    end
                end
            endcase
        end

        `OP_LOAD:begin
            case(funct3)
                `FUNCT3_LB:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_LB_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b1;
                    mem_we_o = 1'b0;
                    mem_op_o = `MEM_LB;
                    wb_sel_o = `WB_SEL_MEM;//lb 最后写回寄存器的是“内存读出来的数据”，不是 ALU 结果,alu只是算地址
                end
                `FUNCT3_LH:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_LH_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b1;
                    mem_we_o = 1'b0;
                    mem_op_o = `MEM_LH;
                    wb_sel_o = `WB_SEL_MEM;
                end
                `FUNCT3_LW:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_LW_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b1;
                    mem_we_o = 1'b0;
                    mem_op_o = `MEM_LW;
                    wb_sel_o = `WB_SEL_MEM;
                end
                `FUNCT3_LBU:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_LBU_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b1;
                    mem_we_o = 1'b0;
                    mem_op_o = `MEM_LBU;
                    wb_sel_o = `WB_SEL_MEM;
                end
                `FUNCT3_LHU:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = imm_I;
                    aluop_o        = `EX_LHU_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b1;
                    mem_we_o = 1'b0;
                    mem_op_o = `MEM_LHU;
                    wb_sel_o = `WB_SEL_MEM;
                end
            endcase
        end

        `OP_STORE:begin
            case(funct3)
                `FUNCT3_SB:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;//store指令不写回

                    imm_o          =  imm_S;
                    aluop_o        = `EX_SB_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b0;
                    mem_we_o = 1'b1;
                    mem_op_o = `MEM_SB;
                    wb_sel_o = `WB_SEL_NONE;//不写回rd，不用选择写回的数据来源
                end
                `FUNCT3_SH:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;//store指令不写回

                    imm_o          =  imm_S;
                    aluop_o        = `EX_SH_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b0;
                    mem_we_o = 1'b1;
                    mem_op_o = `MEM_SH;
                    wb_sel_o = `WB_SEL_NONE;//不写回rd，不用选择写回的数据来源
                end
                `FUNCT3_SW:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteDisable;//store指令不写回

                    imm_o          =  imm_S;
                    aluop_o        = `EX_SW_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_IMM;

                    mem_re_o = 1'b0;
                    mem_we_o = 1'b1;
                    mem_op_o = `MEM_SW;
                    wb_sel_o = `WB_SEL_NONE;//不写回rd，不用选择写回的数据来源
                end
            endcase
        end

        //fence用来约束load和store对于mem的访问，这里是单核的cpu，无cache，先不管，当成nop
        `OP_MISC_MEM: begin
            case (funct3)
                `FUNCT3_FENCE: begin
                    // 对单核、无 cache、无乱序的小 CPU，可以先把 FENCE 当 NOP
                    re1_o          = `ReadDisable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = `ZeroWord;
                    aluop_o        = `EX_NOP_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;

                    mem_op_o       = `MEM_NONE;
                    wb_sel_o       = `WB_SEL_NONE;
                    mem_re_o       = 1'b0;
                    mem_we_o       = 1'b0;

                    fence_o        = 1'b1;
                end
                `FUNCT3_FENCEI: begin
                    re1_o          = `ReadDisable;
                    re2_o          = `ReadDisable;
                    reg_we_o       = `WriteDisable;

                    imm_o          = `ZeroWord;
                    aluop_o        = `EX_NOP_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;

                    mem_op_o       = `MEM_NONE;
                    wb_sel_o       = `WB_SEL_NONE;
                    mem_re_o       = 1'b0;
                    mem_we_o       = 1'b0;

                    fence_o        = 1'b1;
                end
            endcase
        end
        `OP_CMP:begin
            case(funct3)
                `FUNCT3_CMP:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;

                    imm_o          = `ZeroWord;
                    aluop_o        = `EX_CMP_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;

                    mem_re_o       = 1'b0;
                    mem_we_o       = 1'b0;
                    mem_op_o       = `MEM_NONE;
                    wb_sel_o       = `WB_SEL_ALU;
                end
                `FUNCT3_CMPU:begin
                    re1_o          = `ReadEnable;
                    re2_o          = `ReadEnable;
                    reg_we_o       = `WriteEnable;
        
                    imm_o          = `ZeroWord;
                    aluop_o        = `EX_CMPU_OP;
                    alu_src1_sel_o = `ALU_SRC1_RS1;
                    alu_src2_sel_o = `ALU_SRC2_RS2;

                    mem_re_o       = 1'b0;
                    mem_we_o       = 1'b0;
                    mem_op_o       = `MEM_NONE;
                    wb_sel_o       = `WB_SEL_ALU;
                end
            endcase
        end
        default: begin
        end
    endcase
end

endmodule