`include "define.sv"

module ex(

    // 寄存器地址
    input wire [`RegAddrBus] rs1_i,
    input wire [`RegAddrBus] rs2_i,

    // 目的寄存器地址
    input wire [`RegAddrBus] rd_i,

    // 立即数
    input wire [`RegBus] imm_i,

    // regfile 读/写使能
    input wire re1_i,
    input wire re2_i,
    input wire reg_we_i,

    // 跳转/分支，用来判断redirect_o是否拉高，jal/jalr怎么算
    input wire jump_flag_i,
    input wire branch_flag_i,
    input wire jalr_flag_i,

    // 来自 IF/ID 的 PC 信息
    input wire [`InstAddrBus] pc_i,
    input wire [`InstAddrBus] pc_plus4_i,

    // regfile 读出的数据
    input wire [`RegBus] rs1_data_i,
    input wire [`RegBus] rs2_data_i,

    // MEM / WB 控制
    input wire mem_re_i,
    input wire mem_we_i,
    input wire [`MemOpBus] mem_op_i,
    input wire [`WbSelBus] wb_sel_i,

    // fence
    input wire fence_i,

    // ALU 控制
    input wire [`AluOpBus] aluop_i,
    input wire [`AluSrc1SelBus] alu_src1_sel_i,
    input wire [`AluSrc2SelBus] alu_src2_sel_i,

    output redirect_o,//判断是否有分支跳转信号，需要对前两条指令进行冲刷
    output reg [`InstAddrBus] redirect_pc_o,//经过计算后真正要跳转的地址

    // 传给后级的目的寄存器和写回控制
    output [`RegAddrBus] rd_o,//目的寄存器地址
    output reg_we_o,//写寄存器使能信号
    output [`WbSelBus] wb_sel_o,//写回的数据源选择，在wb选真正写回的数据

    //alu/地址运算结果
    output reg [`RegBus] alu_result_o,

    // store 要写入 data memory 的数据，一般就是 rs2 的值
    output reg [`RegBus] store_data_o,

    // 传给 MEM 级的访存控制
    output mem_re_o,//mem读使能
    output mem_we_o,//mem写使能
    output [`MemOpBus] mem_op_o,//对mem做的操作

    // jal/jalr 后面写回要用 pc+4
    output [`InstAddrBus] pc_plus4_o,

    // 可选：fence 继续往后传
    output  fence_o,

    // 来自 EX/MEM 级的前递信息，从ex_mem流水线寄存器取出（打拍后的信号）
    input wire                 ex_mem_reg_we_i,//写寄存器使能，确定要写回
    input wire [`RegAddrBus]   ex_mem_rd_i,//写回的目的寄存器地址，判断要用的rs1/rs2是不是目的寄存器的还没更新的值
    //必须是最终的写回值，不只是alu_result
    input wire [`RegBus]       ex_mem_forward_result_i,//本次运算的result打一拍的值，写回rd，如果要用，直接通过旁路个下一条指令

    // 来自 MEM/WB 级的前递信息，从mem_wb流水线寄存器取出（打拍后的信号）
    input wire                 mem_wb_reg_we_i,
    input wire [`RegAddrBus]   mem_wb_rd_i,
    input wire [`RegBus]       mem_wb_forward_result_i,

    //判断是否是load指令，load不前递，单可以在mem_wb前递，因为load要到mem才能有数据
    output load_flag_o,
    //打拍后的load标志信号
    input ex_mem_load_flag_i,

    //csr输入
    input wire [`CsrAddrBus] csr_addr_i,
    input wire [`CsrCmdBus] csr_cmd_i,
    input wire csr_en_i,
    input wire [`CsrDataBus] csr_rdata_i,//csrfile里面读出来的csr旧值
    input wire csr_mret_i,

    input [`InstAddrBus] csr_mepc_i,//中断结束后恢复的pc

    //csr写回信息
    output reg                csr_we_o,
    output  [`CsrAddrBus]  csr_waddr_o,
    output reg [`CsrDataBus]  csr_wdata_o,

    output csr_mret_o,

    // 当前EX阶段指令是否有效
    input wire ex_valid_i,
    //ex后的流水线是否暂停ex_advance = 1：EX当前指令可以完成 ex_advance = 0：后级stall，EX当前指令必须保持
    input ex_advance
);

wire csr_mret_valid;
//与mem,wb有关的，在id阶段产生的信号直接传
assign mem_re_o = mem_re_i;
assign mem_we_o = mem_we_i;
assign pc_plus4_o = pc_plus4_i;//在if阶段+4
assign mem_op_o = mem_op_i;
assign wb_sel_o = wb_sel_i;
assign fence_o = fence_i;
assign rd_o = rd_i;
assign reg_we_o = reg_we_i;
assign csr_mret_valid = csr_mret_i && ex_valid_i && ex_advance;//只有在指令有效且能向前传递时拉高一拍
assign csr_mret_o = csr_mret_valid;
assign load_flag_o = (aluop_i == `EX_LB_OP || aluop_i == `EX_LH_OP ||aluop_i == `EX_LW_OP
                        || aluop_i == `EX_LBU_OP || aluop_i == `EX_LHU_OP)? 1'b1 : 1'b0;
assign csr_waddr_o = csr_addr_i;

//模块中所需的reg/wire
reg branch_taken;//判断branch信号中的分支跳转条件是否成立
reg [`RegBus] alu_src1;// 第一个操作数
reg [`RegBus] alu_src2;//第二个操作数
reg [`RegBus] rs1_data_final;//rs1数据前递后的最终值（直接从ex_mem，mem_wb寄存器把更新的值拿回来）
reg [`RegBus] rs2_data_final;//rs2数据前递后的最终值（直接从ex_mem，mem_wb寄存器把更新的值拿回来）

//判断是否需要数据前递（当前阶段要用的数据有没有要更新的）
always @(*) begin
    rs1_data_final = rs1_data_i;
    rs2_data_final = rs2_data_i;

    //做旁路选择
    //判断条件：1.re1_i拉高说明要从寄存器读值 2.ex_mem_reg_we_i说明往reg里面写数据了 3.目的寄存器的地址要存在 4.要取的数据地址确实是刚刚写进去的 5.确保不是load前递
    // 优先从 EX/MEM 前递，因为它更新
    if (re1_i && ex_mem_reg_we_i && (ex_mem_rd_i != `NOPRegAddr) && (rs1_i == ex_mem_rd_i) && !ex_mem_load_flag_i)
        rs1_data_final = ex_mem_forward_result_i;//将ex计算出来的result打拍后直接通过旁路给到下一条指令做计算

    // 如果 EX/MEM 不匹配，再从 MEM/WB 前递，load可以在mem_wb前递
    else if (re1_i && mem_wb_reg_we_i && (mem_wb_rd_i != `NOPRegAddr) && (rs1_i == mem_wb_rd_i))
        rs1_data_final = mem_wb_forward_result_i;

    if (re2_i && ex_mem_reg_we_i && (ex_mem_rd_i != `NOPRegAddr) && (rs2_i == ex_mem_rd_i) && !ex_mem_load_flag_i)
        rs2_data_final = ex_mem_forward_result_i;
    else if (re2_i && mem_wb_reg_we_i && (mem_wb_rd_i != `NOPRegAddr) && (rs2_i == mem_wb_rd_i))
        rs2_data_final = mem_wb_forward_result_i;
end

//普通csr前递，后一条csr指令要用前一条的数据


//redirect信号产生，csr要跳转回原来的pc
assign redirect_o = jump_flag_i || jalr_flag_i || (branch_flag_i && branch_taken) || csr_mret_valid;

//操作数选择
always @(*)begin
    alu_src1 = `ZeroWord;
    alu_src2 = `ZeroWord;
    case (alu_src1_sel_i)
        `ALU_SRC1_PC:   alu_src1 = pc_i;
        `ALU_SRC1_ZERO: alu_src1 = `ZeroWord;
        default:        alu_src1 = rs1_data_final;
    endcase

    case (alu_src2_sel_i)
        `ALU_SRC2_IMM:  alu_src2 = imm_i;
        `ALU_SRC2_FOUR: alu_src2 = 32'd4;
        default:        alu_src2 = rs2_data_final;
    endcase
end

//做运算
always @(*)begin
    alu_result_o = `ZeroWord;
    store_data_o = rs2_data_final;//给存储器store的地数据就是rs2的数据，直接给
    branch_taken = 1'b0;
    csr_we_o = 1'b0;
    csr_wdata_o = 'd0;

    if(csr_en_i && ex_valid_i) begin
        case(csr_cmd_i)
            `CSR_CMD_CSRRW: begin
                alu_result_o = csr_rdata_i;
                csr_we_o = 1'b1;
                csr_wdata_o = rs1_data_final;
            end

            `CSR_CMD_CSRRS: begin
                alu_result_o = csr_rdata_i;
                csr_we_o = (rs1_i != 5'd0);
                csr_wdata_o = rs1_data_final | csr_rdata_i;
            end

            `CSR_CMD_CSRRC: begin
                alu_result_o = csr_rdata_i;
                csr_we_o = (rs1_i != 5'd0);
                csr_wdata_o = csr_rdata_i & ~rs1_data_final;
            end

            `CSR_CMD_CSRRWI: begin
                alu_result_o = csr_rdata_i;
                csr_we_o = 1'b1;
                csr_wdata_o = imm_i;
            end

            `CSR_CMD_CSRRSI: begin
                alu_result_o = csr_rdata_i;
                csr_we_o = (imm_i[4:0] != 5'd0);
                csr_wdata_o = csr_rdata_i | imm_i;
            end

            `CSR_CMD_CSRRCI: begin
                alu_result_o = csr_rdata_i;
                csr_we_o = (imm_i[4:0] != 5'd0);
                csr_wdata_o = csr_rdata_i & ~imm_i;
            end

            default: begin
                alu_result_o = `ZeroWord;
                csr_we_o = 1'b0;
                csr_wdata_o = `ZeroWord;
            end
        endcase
    end

    else begin
        case(aluop_i)
            `EX_ADD_OP:  alu_result_o = alu_src1 + alu_src2;
            `EX_SUB_OP:  alu_result_o = alu_src1 - alu_src2;
            `EX_XOR_OP:  alu_result_o = alu_src1 ^ alu_src2;//异或操作
            `EX_OR_OP:   alu_result_o = alu_src1 | alu_src2;
            `EX_AND_OP:  alu_result_o = alu_src1 & alu_src2;
            `EX_SLL_OP:  alu_result_o = alu_src1 << alu_src2[4:0];//把 alu_src1 左移 alu_src2[4:0]位右边补 0
            `EX_SRL_OP:  alu_result_o = alu_src1 >> alu_src2[4:0];//把 alu_src1 右移 alu_src2[4:0]位坐边补 0
            `EX_SRA_OP:  alu_result_o = $signed(alu_src1) >>> alu_src2[4:0];//右移，但左边补的是“符号位”，如果是负数，左边补 1，如果是正数，左边补 0
            `EX_SLT_OP:  alu_result_o = ($signed(alu_src1) < $signed(alu_src2)) ? 32'd1 : 32'd0;//把两个数当作有符号数比较，如果 src1 < src2，结果写 1，否则写 0
            `EX_SLTU_OP: alu_result_o = (alu_src1 < alu_src2) ? 32'd1 : 32'd0;//把两个数当作无符号数比较，小于就输出 1，否则 0

            // load/store 地址计算本质也是加法
            `EX_LB_OP,
            `EX_LH_OP,
            `EX_LW_OP,
            `EX_LBU_OP,
            `EX_LHU_OP,
            `EX_SB_OP,
            `EX_SH_OP,
            `EX_SW_OP:   alu_result_o = alu_src1 + alu_src2;

            `EX_BEQ_OP:  branch_taken = (alu_src1 == alu_src2);
            `EX_BNE_OP:  branch_taken = (alu_src1 != alu_src2);
            `EX_BLT_OP:  branch_taken = ($signed(alu_src1) < $signed(alu_src2));
            `EX_BGE_OP:  branch_taken = ($signed(alu_src1) >= $signed(alu_src2));
            `EX_BLTU_OP: branch_taken = (alu_src1 < alu_src2);//判断两个值的大小
            `EX_BGEU_OP: branch_taken = (alu_src1 >= alu_src2);//判断两个值的大小

            `EX_CMP_OP: alu_result_o = ($signed(alu_src1) >= $signed(alu_src2)) ? alu_src1 : alu_src2;
            `EX_CMPU_OP: alu_result_o = (alu_src1 >= alu_src2) ? alu_src1 : alu_src2;
            default:     branch_taken = 1'b0;
        endcase
    end

end

always @(*)begin
    redirect_pc_o = `ZeroWord;
    if (csr_mret_valid) begin
        // mret回到被中断程序
        redirect_pc_o = csr_mepc_i;
    end
    else if (jump_flag_i) begin
        redirect_pc_o = pc_i + imm_i;       // jal
    end
    else if (jalr_flag_i) begin
        redirect_pc_o = (rs1_data_final + imm_i) & 32'hffff_fffe; // jalr
    end
    else if (branch_taken) begin
        redirect_pc_o = pc_i + imm_i;       // branch 成立
    end
    else begin
        redirect_pc_o = `ZeroWord;
    end
end

endmodule
