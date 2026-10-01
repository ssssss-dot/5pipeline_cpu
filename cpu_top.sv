`include "define.sv"

// Five-stage CPU core. All memory ports use a native request/response protocol.
module cpu_top(
    input  wire                 clk,
    input  wire                 rst_n,

    // External machine interrupt (level-sensitive).
    input  wire                 irq_i,

    // Instruction-memory request/response interface.
    output wire                 imem_req_valid,
    input  wire                 imem_req_ready,
    output wire [`InstAddrBus]  imem_req_addr,
    input  wire                 imem_rsp_valid,
    input  wire [`InstBus]      imem_rsp_rdata,

    // Data-memory request/response interface.
    output wire                 dmem_req_valid,
    input  wire                 dmem_req_ready,
    output wire [`DataAddrBus]  dmem_req_addr,
    output wire [`DataBus]      dmem_req_wdata,
    output wire [3:0]           dmem_req_wstrb,
    output wire                 dmem_req_write,
    input  wire                 dmem_rsp_valid,
    input  wire [`DataBus]      dmem_rsp_rdata,

    // Memory-mapped I/O uses a separate native request/response port.
    output wire                 mmio_req_valid,
    input  wire                 mmio_req_ready,
    output wire [`DataAddrBus]  mmio_req_addr,
    output wire [`DataBus]      mmio_req_wdata,
    output wire [3:0]           mmio_req_wstrb,
    output wire                 mmio_req_write,
    input  wire                 mmio_rsp_valid,
    output wire                 mmio_rsp_ready,
    input  wire [`DataBus]      mmio_rsp_rdata,

    // Byte stream for stores to UART_TX_ADDR (0x4000_0000).
    output wire [`ByteWidth]    uart_tx_data,
    output wire                 uart_tx_valid,
    input  wire                 uart_tx_ready,

    // Useful waveform/debug outputs.
    output wire                 trap_enter_o,
    output wire [`InstAddrBus]  trap_pc_o,
    output wire [`InstAddrBus]  mtvec_o,
    output wire [`InstAddrBus]  mepc_o,
    output wire                 irq_request_o,
    output wire                 redirect_o,
    output wire [`InstAddrBus]  redirect_pc_o,
    output wire [5:0]           stall_o,
    output wire                 flush_if_id_o,
    output wire                 flush_id_ex_o,
    output wire                 flush_ex_mem_o,
    output wire                 flush_mem_wb_o,
    output wire                 wb_we_o,
    output wire [`RegAddrBus]   wb_waddr_o,
    output wire [`RegBus]       wb_wdata_o,
    output wire [`InstAddrBus]  ex_pc_o,
    output wire                 ex_valid_o
);

// -------------------------------------------------------------------------
// Control and IF stage
// -------------------------------------------------------------------------
wire        if_req;
wire        id_req;
wire        ex_req;
wire        mem_req;
wire        redirect;
wire        except_i;
wire [5:0]  stall;
wire        flush_if_id;
wire        flush_id_ex;
wire        flush_ex_mem;
wire        flush_mem_wb;

wire [`InstBus]     if_inst;
wire [`InstAddrBus] if_pc;
wire [`InstAddrBus] if_pc_plus4;
wire                if_valid;

wire [`InstAddrBus] id_pc;
wire [`InstAddrBus] id_pc_plus4;
wire [`InstBus]     id_inst;
wire                id_valid;

// -------------------------------------------------------------------------
// ID stage
// -------------------------------------------------------------------------
wire [`RegAddrBus] id_rs1;
wire [`RegAddrBus] id_rs2;
wire [`RegAddrBus] id_rd;
wire [`RegBus]     id_imm;
wire               id_re1;
wire               id_re2;
wire               id_reg_we;
wire               id_jump_flag;
wire               id_branch_flag;
wire               id_jalr_flag;
wire               id_mem_re;
wire               id_mem_we;
wire [`MemOpBus]   id_mem_op;
wire [`WbSelBus]   id_wb_sel;
wire               id_fence;
wire [`AluOpBus]   id_aluop;
wire [`AluSrc1SelBus] id_alu_src1_sel;
wire [`AluSrc2SelBus] id_alu_src2_sel;
wire [`InstAddrBus] id_pc_to_ex;
wire [`InstAddrBus] id_pc_plus4_to_ex;
wire [`RegBus]      id_rs1_data;
wire [`RegBus]      id_rs2_data;
wire [`CsrAddrBus]  id_csr_addr;
wire [`CsrCmdBus]   id_csr_cmd;
wire                id_csr_en;
wire                id_csr_mret;

// -------------------------------------------------------------------------
// ID/EX and EX stage
// -------------------------------------------------------------------------
wire [`RegAddrBus] ex_rs1;
wire [`RegAddrBus] ex_rs2;
wire [`RegAddrBus] ex_rd;
wire [`RegBus]     ex_imm;
wire               ex_re1;
wire               ex_re2;
wire               ex_reg_we;
wire               ex_jump_flag;
wire               ex_branch_flag;
wire               ex_jalr_flag;
wire               ex_mem_re;
wire               ex_mem_we;
wire [`MemOpBus]   ex_mem_op;
wire [`WbSelBus]   ex_wb_sel;
wire               ex_fence;
wire [`AluOpBus]   ex_aluop;
wire [`AluSrc1SelBus] ex_alu_src1_sel;
wire [`AluSrc2SelBus] ex_alu_src2_sel;
wire [`InstAddrBus] ex_pc;
wire [`InstAddrBus] ex_pc_plus4;
wire [`RegBus]      ex_rs1_data;
wire [`RegBus]      ex_rs2_data;
wire                ex_valid;
wire [`CsrAddrBus]  ex_csr_addr;
wire [`CsrCmdBus]   ex_csr_cmd;
wire                ex_csr_en;
wire                ex_csr_mret;
wire                ex_advance;

wire                ex_stage_redirect;
wire [`InstAddrBus] ex_stage_redirect_pc;
wire                ex_stage_reg_we;
wire [`RegAddrBus]  ex_stage_rd;
wire [`WbSelBus]    ex_stage_wb_sel;
wire [`RegBus]      ex_stage_alu_result;
wire [`RegBus]      ex_stage_store_data;
wire                ex_stage_mem_re;
wire                ex_stage_mem_we;
wire [`MemOpBus]    ex_stage_mem_op;
wire [`InstAddrBus] ex_stage_pc_plus4;
wire                ex_stage_fence;
wire                ex_stage_load_flag;
wire                ex_stage_csr_we;
wire [`CsrAddrBus]  ex_stage_csr_waddr;
wire [`CsrDataBus]  ex_stage_csr_wdata;

// -------------------------------------------------------------------------
// EX/MEM and MEM stage
// -------------------------------------------------------------------------
wire                mem_reg_we;
wire [`RegAddrBus]  mem_rd;
wire [`WbSelBus]    mem_wb_sel;
wire [`RegBus]      mem_alu_result;
wire [`RegBus]      mem_store_data;
wire                mem_mem_re;
wire                mem_mem_we;
wire [`MemOpBus]    mem_mem_op;
wire [`InstAddrBus] mem_pc_plus4;
wire                mem_fence;
wire                mem_load_flag;
wire [`RegBus]      ex_mem_forward_result;
wire                mem_csr_we;
wire [`CsrAddrBus]  mem_csr_waddr;
wire [`CsrDataBus]  mem_csr_wdata;

wire [`RegBus]      mem_stage_mem_data;
wire [`RegBus]      mem_stage_alu_result;
wire [`InstAddrBus] mem_stage_pc_plus4;
wire [`RegAddrBus]  mem_stage_rd;
wire                mem_stage_reg_we;
wire [`WbSelBus]    mem_stage_wb_sel;
wire                mem_stage_load_flag;
wire                mem_stage_fence;
wire                mem_stage_csr_we;
wire [`CsrAddrBus]  mem_stage_csr_waddr;
wire [`CsrDataBus]  mem_stage_csr_wdata;

// The byte-stream transfer completes one cycle after valid/ready handshakes.
reg uart_ack_q;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        uart_ack_q <= 1'b0;
    else
        uart_ack_q <= uart_tx_valid && uart_tx_ready;
end

// -------------------------------------------------------------------------
// MEM/WB and WB stage
// -------------------------------------------------------------------------
wire [`RegBus]      wb_mem_data;
wire [`RegBus]      wb_alu_result;
wire [`InstAddrBus] wb_pc_plus4;
wire [`RegAddrBus]  wb_rd;
wire                wb_reg_we;
wire [`WbSelBus]    wb_wb_sel;
wire                wb_load_flag;
wire                wb_fence;
wire                wb_csr_we;
wire [`CsrAddrBus]  wb_csr_waddr;
wire [`CsrDataBus]  wb_csr_wdata;

wire                wb_we;
wire [`RegAddrBus]  wb_waddr;
wire [`RegBus]      wb_wdata;
wire                wb_reg_we_for_ex;
wire [`RegAddrBus]  wb_rd_for_ex;
wire [`RegBus]      wb_forward_result_for_ex;
wire                csrfile_wb_we;
wire [`CsrAddrBus]  csrfile_wb_waddr;
wire [`CsrDataBus]  csrfile_wb_wdata;

// -------------------------------------------------------------------------
// Interrupt control
// -------------------------------------------------------------------------
wire [`InstAddrBus] csr_mtvec;
wire [`InstAddrBus] csr_mepc;
wire                csr_irq_request;
wire                trap_enter;
wire [`InstAddrBus] trap_pc;
wire [`InstAddrBus] redirect_pc;

// Interrupt has priority over the normal EX redirect.
assign redirect    = trap_enter || ex_stage_redirect;
assign redirect_pc = trap_enter ? csr_mtvec : ex_stage_redirect_pc;

// EX and the younger ID/IF instructions are flushed on interrupt entry.
// Therefore MEPC records the current EX PC so that MRET re-executes it.
assign trap_pc   = ex_pc;
assign except_i  = trap_enter;

// Wait for older memory and CSR operations to retire before taking the IRQ.
assign trap_enter = csr_irq_request && ex_valid &&
                    !mem_req && !ex_req &&
                    !mem_csr_we && !wb_csr_we;

// Current EX instruction commits only when EX/MEM can accept it.
assign ex_advance = !stall[3] && !flush_ex_mem;

Ctrl u_ctrl (
    .rst_n            (rst_n),
    .if_req           (if_req),
    .id_req           (id_req),
    .ex_req           (ex_req),
    .mem_req          (mem_req),
    .redirect_i       (redirect),
    .except_i         (except_i),
    .stall            (stall),
    .flush_if_id      (flush_if_id),
    .flush_id_ex      (flush_id_ex),
    .flush_ex_mem     (flush_ex_mem),
    .flush_mem_wb     (flush_mem_wb),
    .i_loader_stall   (1'b0)
);

if_stage u_if_stage (
    .clk               (clk),
    .rst_n             (rst_n),
    .stall_i           (stall[0]),
    .redirect_i        (redirect),
    .redirect_pc_i     (redirect_pc),
    .inst_o            (if_inst),
    .pc_o              (if_pc),
    .pc_plus4_o        (if_pc_plus4),
    .if_valid_o        (if_valid),
    .if_req_o          (if_req),
    .fetch_enable      (1'b1),
    .imem_req_valid    (imem_req_valid),
    .imem_req_ready    (imem_req_ready),
    .imem_req_addr     (imem_req_addr),
    .imem_rsp_valid    (imem_rsp_valid),
    .imem_rsp_rdata    (imem_rsp_rdata)
);

if_id u_if_id (
    .clk           (clk),
    .rst_n         (rst_n),
    .stall_i       (stall[1]),
    .flush_i       (flush_if_id),
    .if_pc_i       (if_pc),
    .if_pc_plus4_i (if_pc_plus4),
    .if_inst_i     (if_inst),
    .if_valid_i    (if_valid),
    .id_pc_o       (id_pc),
    .id_pc_plus4_o (id_pc_plus4),
    .id_inst_o     (id_inst),
    .id_valid_o    (id_valid)
);

id_stage u_id_stage (
    .clk              (clk),
    .rst_n            (rst_n),
    .inst_i           (id_inst),
    .pc_i             (id_pc),
    .pc_plus4_i       (id_pc_plus4),
    .wb_we_i          (wb_we),
    .wb_waddr_i       (wb_waddr),
    .wb_wdata_i       (wb_wdata),
    .rs1_o            (id_rs1),
    .rs2_o            (id_rs2),
    .rd_o             (id_rd),
    .imm_o            (id_imm),
    .re1_o            (id_re1),
    .re2_o            (id_re2),
    .reg_we_o         (id_reg_we),
    .jump_flag_o      (id_jump_flag),
    .branch_flag_o    (id_branch_flag),
    .jalr_flag_o      (id_jalr_flag),
    .mem_re_o         (id_mem_re),
    .mem_we_o         (id_mem_we),
    .mem_op_o         (id_mem_op),
    .wb_sel_o         (id_wb_sel),
    .fence_o          (id_fence),
    .aluop_o          (id_aluop),
    .alu_src1_sel_o   (id_alu_src1_sel),
    .alu_src2_sel_o   (id_alu_src2_sel),
    .pc_o             (id_pc_to_ex),
    .pc_plus4_o       (id_pc_plus4_to_ex),
    .rs1_data_o       (id_rs1_data),
    .rs2_data_o       (id_rs2_data),
    .ex_mem_re_i      (ex_mem_re),
    .ex_rd_i          (ex_rd),
    .ex_csr_we_i      (ex_stage_csr_we),
    .mem_csr_we_i     (mem_csr_we),
    .wb_csr_we_i      (wb_csr_we),
    .id_req_o         (id_req),
    .csr_addr_o       (id_csr_addr),
    .csr_cmd_o        (id_csr_cmd),
    .csr_en_o         (id_csr_en),
    .mret_o           (id_csr_mret)
);

id_ex u_id_ex (
    .clk               (clk),
    .rst_n             (rst_n),
    .id_valid_i        (id_valid),
    .id_rs1_i          (id_rs1),
    .id_rs2_i          (id_rs2),
    .id_rd_i           (id_rd),
    .id_imm_i          (id_imm),
    .id_re1_i          (id_re1),
    .id_re2_i          (id_re2),
    .id_reg_we_i       (id_reg_we),
    .id_jump_flag_i    (id_jump_flag),
    .id_branch_flag_i  (id_branch_flag),
    .id_jalr_flag_i    (id_jalr_flag),
    .pc_i              (id_pc_to_ex),
    .pc_plus4_i        (id_pc_plus4_to_ex),
    .rs1_data_i        (id_rs1_data),
    .rs2_data_i        (id_rs2_data),
    .id_mem_re_i       (id_mem_re),
    .id_mem_we_i       (id_mem_we),
    .id_mem_op_i       (id_mem_op),
    .id_wb_sel_i       (id_wb_sel),
    .id_fence_i        (id_fence),
    .id_csr_addr_i     (id_csr_addr),
    .id_csr_en_i       (id_csr_en),
    .id_csr_cmd_i      (id_csr_cmd),
    .id_csr_mret_i     (id_csr_mret),
    .id_aluop_i        (id_aluop),
    .id_alu_src1_sel_i (id_alu_src1_sel),
    .id_alu_src2_sel_i (id_alu_src2_sel),
    .flush_i           (flush_id_ex),
    .stall_i           (stall[2]),
    .ex_rs1_o          (ex_rs1),
    .ex_rs2_o          (ex_rs2),
    .ex_rd_o           (ex_rd),
    .ex_imm_o          (ex_imm),
    .ex_re1_o          (ex_re1),
    .ex_re2_o          (ex_re2),
    .ex_reg_we_o       (ex_reg_we),
    .ex_jump_flag_o    (ex_jump_flag),
    .ex_branch_flag_o  (ex_branch_flag),
    .ex_jalr_flag_o    (ex_jalr_flag),
    .ex_mem_re_o       (ex_mem_re),
    .ex_mem_we_o       (ex_mem_we),
    .ex_mem_op_o       (ex_mem_op),
    .ex_wb_sel_o       (ex_wb_sel),
    .ex_fence_o        (ex_fence),
    .ex_aluop_o        (ex_aluop),
    .ex_alu_src1_sel_o (ex_alu_src1_sel),
    .ex_alu_src2_sel_o (ex_alu_src2_sel),
    .pc_o              (ex_pc),
    .pc_plus4_o        (ex_pc_plus4),
    .rs1_data_o        (ex_rs1_data),
    .rs2_data_o        (ex_rs2_data),
    .ex_valid_o        (ex_valid),
    .ex_csr_addr_o     (ex_csr_addr),
    .ex_csr_en_o       (ex_csr_en),
    .ex_csr_cmd_o      (ex_csr_cmd),
    .ex_csr_mret_o     (ex_csr_mret)
);

ex_stage u_ex_stage (
    .clk                         (clk),
    .rst_n                       (rst_n),
    .ex_valid_i                  (ex_valid),
    .ex_advance_i                (ex_advance),
    .rs1_i                       (ex_rs1),
    .rs2_i                       (ex_rs2),
    .rd_i                        (ex_rd),
    .imm_i                       (ex_imm),
    .re1_i                       (ex_re1),
    .re2_i                       (ex_re2),
    .reg_we_i                    (ex_reg_we),
    .jump_flag_i                 (ex_jump_flag),
    .branch_flag_i               (ex_branch_flag),
    .jalr_flag_i                 (ex_jalr_flag),
    .pc_i                        (ex_pc),
    .pc_plus4_i                  (ex_pc_plus4),
    .rs1_data_i                  (ex_rs1_data),
    .rs2_data_i                  (ex_rs2_data),
    .mem_re_i                    (ex_mem_re),
    .mem_we_i                    (ex_mem_we),
    .mem_op_i                    (ex_mem_op),
    .wb_sel_i                    (ex_wb_sel),
    .fence_i                     (ex_fence),
    .aluop_i                     (ex_aluop),
    .alu_src1_sel_i              (ex_alu_src1_sel),
    .alu_src2_sel_i              (ex_alu_src2_sel),
    .redirect_o                  (ex_stage_redirect),
    .redirect_pc_o               (ex_stage_redirect_pc),
    .rd_o                        (ex_stage_rd),
    .reg_we_o                    (ex_stage_reg_we),
    .wb_sel_o                    (ex_stage_wb_sel),
    .alu_result_o                (ex_stage_alu_result),
    .store_data_o                (ex_stage_store_data),
    .mem_re_o                    (ex_stage_mem_re),
    .mem_we_o                    (ex_stage_mem_we),
    .mem_op_o                    (ex_stage_mem_op),
    .pc_plus4_o                  (ex_stage_pc_plus4),
    .fence_o                     (ex_stage_fence),
    .ex_mem_reg_we_i             (mem_reg_we),
    .ex_mem_rd_i                 (mem_rd),
    .ex_mem_forward_result_i     (ex_mem_forward_result),
    .mem_wb_reg_we_i             (wb_reg_we_for_ex),
    .mem_wb_rd_i                 (wb_rd_for_ex),
    .mem_wb_forward_result_i     (wb_forward_result_for_ex),
    .load_flag_o                 (ex_stage_load_flag),
    .ex_mem_load_flag_i          (mem_load_flag),
    .ex_req_o                    (ex_req),
    .dma_irq_i                   (irq_i),
    .trap_enter_i                (trap_enter),
    .trap_pc_i                   (trap_pc),
    .wb_csr_we_i                 (csrfile_wb_we),
    .wb_csr_waddr_i              (csrfile_wb_waddr),
    .wb_csr_wdata_i              (csrfile_wb_wdata),
    .mtvec_o                     (csr_mtvec),
    .mepc_o                      (csr_mepc),
    .irq_request_o               (csr_irq_request),
    .csr_addr_i                  (ex_csr_addr),
    .csr_cmd_i                   (ex_csr_cmd),
    .csr_en_i                    (ex_csr_en),
    .csr_mret_i                  (ex_csr_mret),
    .csr_we_o                    (ex_stage_csr_we),
    .csr_waddr_o                 (ex_stage_csr_waddr),
    .csr_wdata_o                 (ex_stage_csr_wdata),
    .ex_mem_csr_we_i             (mem_csr_we),
    .ex_mem_csr_waddr_i          (mem_csr_waddr),
    .ex_mem_csr_wdata_i          (mem_csr_wdata)
);

ex_mem u_ex_mem (
    .clk                  (clk),
    .rst_n                (rst_n),
    .stall_i              (stall[3]),
    .flush_i              (flush_ex_mem),
    .ex_reg_we_i          (ex_stage_reg_we),
    .ex_rd_i              (ex_stage_rd),
    .ex_wb_sel_i          (ex_stage_wb_sel),
    .ex_alu_result_i      (ex_stage_alu_result),
    .ex_store_data_i      (ex_stage_store_data),
    .ex_mem_re_i          (ex_stage_mem_re),
    .ex_mem_we_i          (ex_stage_mem_we),
    .ex_mem_op_i          (ex_stage_mem_op),
    .ex_pc_plus4_i        (ex_stage_pc_plus4),
    .ex_fence_i           (ex_stage_fence),
    .ex_csr_we_i          (ex_stage_csr_we),
    .ex_csr_waddr_i       (ex_stage_csr_waddr),
    .ex_csr_wdata_i       (ex_stage_csr_wdata),
    .ex_load_flag_i       (ex_stage_load_flag),
    .mem_reg_we_o         (mem_reg_we),
    .mem_rd_o             (mem_rd),
    .mem_wb_sel_o         (mem_wb_sel),
    .mem_alu_result_o     (mem_alu_result),
    .mem_store_data_o     (mem_store_data),
    .mem_mem_re_o         (mem_mem_re),
    .mem_mem_we_o         (mem_mem_we),
    .mem_mem_op_o         (mem_mem_op),
    .mem_pc_plus4_o       (mem_pc_plus4),
    .mem_fence_o          (mem_fence),
    .mem_load_flag_o      (mem_load_flag),
    .mem_csr_we_o         (mem_csr_we),
    .mem_csr_waddr_o      (mem_csr_waddr),
    .mem_csr_wdata_o      (mem_csr_wdata),
    .forward_result_o     (ex_mem_forward_result)
);

mem_stage u_mem_stage (
    .clk                (clk),
    .rst_n              (rst_n),
    .reg_we_i           (mem_reg_we),
    .rd_i               (mem_rd),
    .wb_sel_i           (mem_wb_sel),
    .alu_result_i       (mem_alu_result),
    .store_data_i       (mem_store_data),
    .mem_re_i           (mem_mem_re),
    .mem_we_i           (mem_mem_we),
    .mem_op_i           (mem_mem_op),
    .pc_plus4_i         (mem_pc_plus4),
    .fence_i            (mem_fence),
    .csr_we_i           (mem_csr_we),
    .csr_waddr_i        (mem_csr_waddr),
    .csr_wdata_i        (mem_csr_wdata),
    .load_flag_i        (mem_load_flag),
    .alu_result_o       (mem_stage_alu_result),
    .pc_plus4_o         (mem_stage_pc_plus4),
    .rd_o               (mem_stage_rd),
    .reg_we_o           (mem_stage_reg_we),
    .mem_data_o         (mem_stage_mem_data),
    .wb_sel_o           (mem_stage_wb_sel),
    .load_flag_o        (mem_stage_load_flag),
    .fence_o            (mem_stage_fence),
    .csr_we_o           (mem_stage_csr_we),
    .csr_waddr_o        (mem_stage_csr_waddr),
    .csr_wdata_o        (mem_stage_csr_wdata),
    .mem_accept_i       (!stall[4]),
    .mem_req_o          (mem_req),
    .uart_tx_data       (uart_tx_data),
    .uart_tx_valid      (uart_tx_valid),
    .uart_tx_ready      (uart_tx_ready),
    .uart_rsp_valid     (uart_ack_q),
    .uart_rsp_error     (1'b0),
    .dmem_req_valid     (dmem_req_valid),
    .dmem_req_ready     (dmem_req_ready),
    .dmem_req_addr      (dmem_req_addr),
    .dmem_req_wdata     (dmem_req_wdata),
    .dmem_req_wstrb     (dmem_req_wstrb),
    .dmem_req_write     (dmem_req_write),
    .dmem_rsp_valid     (dmem_rsp_valid),
    .dmem_rsp_rdata     (dmem_rsp_rdata),
    .mmio_req_valid     (mmio_req_valid),
    .mmio_req_ready     (mmio_req_ready),
    .mmio_req_addr      (mmio_req_addr),
    .mmio_req_wdata     (mmio_req_wdata),
    .mmio_req_wstrb     (mmio_req_wstrb),
    .mmio_req_write     (mmio_req_write),
    .mmio_rsp_valid     (mmio_rsp_valid),
    .mmio_rsp_ready     (mmio_rsp_ready),
    .mmio_rsp_rdata     (mmio_rsp_rdata)
);

mem_wb u_mem_wb (
    .clk                  (clk),
    .rst_n                (rst_n),
    .stall_i              (stall[4]),
    .flush_i              (flush_mem_wb),
    .mem_alu_result_i     (mem_stage_alu_result),
    .mem_pc_plus4_i       (mem_stage_pc_plus4),
    .mem_rd_i             (mem_stage_rd),
    .mem_reg_we_i         (mem_stage_reg_we),
    .mem_mem_data_i       (mem_stage_mem_data),
    .mem_wb_sel_i         (mem_stage_wb_sel),
    .mem_load_flag_i      (mem_stage_load_flag),
    .mem_fence_i          (mem_stage_fence),
    .mem_csr_we_i         (mem_stage_csr_we),
    .mem_csr_waddr_i      (mem_stage_csr_waddr),
    .mem_csr_wdata_i      (mem_stage_csr_wdata),
    .wb_alu_result_o      (wb_alu_result),
    .wb_pc_plus4_o        (wb_pc_plus4),
    .wb_rd_o              (wb_rd),
    .wb_reg_we_o          (wb_reg_we),
    .wb_mem_data_o        (wb_mem_data),
    .wb_wb_sel_o          (wb_wb_sel),
    .wb_load_flag_o       (wb_load_flag),
    .wb_fence_o           (wb_fence),
    .wb_csr_we_o          (wb_csr_we),
    .wb_csr_waddr_o       (wb_csr_waddr),
    .wb_csr_wdata_o       (wb_csr_wdata)
);

wb_stage u_wb_stage (
    .mem_data_i                    (wb_mem_data),
    .alu_result_i                  (wb_alu_result),
    .pc_plus4_i                    (wb_pc_plus4),
    .rd_i                          (wb_rd),
    .reg_we_i                      (wb_reg_we),
    .wb_sel_i                      (wb_wb_sel),
    .wb_we_o                       (wb_we),
    .wb_waddr_o                    (wb_waddr),
    .wb_wdata_o                    (wb_wdata),
    .wb_reg_we_for_ex_o            (wb_reg_we_for_ex),
    .wb_rd_for_ex_o                (wb_rd_for_ex),
    .wb_forward_result_for_ex_o    (wb_forward_result_for_ex),
    .csr_we_i                      (wb_csr_we),
    .csr_waddr_i                   (wb_csr_waddr),
    .csr_wdata_i                   (wb_csr_wdata),
    .wb_csr_we_o                   (csrfile_wb_we),
    .wb_csr_waddr_o                (csrfile_wb_waddr),
    .wb_csr_wdata_o                (csrfile_wb_wdata)
);

// Export the signals that are most useful when checking interrupt entry,
// handler execution, and MRET return in a waveform.
assign trap_enter_o        = trap_enter;
assign trap_pc_o           = trap_pc;
assign mtvec_o             = csr_mtvec;
assign mepc_o              = csr_mepc;
assign irq_request_o       = csr_irq_request;
assign redirect_o          = redirect;
assign redirect_pc_o       = redirect_pc;
assign stall_o             = stall;
assign flush_if_id_o       = flush_if_id;
assign flush_id_ex_o       = flush_id_ex;
assign flush_ex_mem_o      = flush_ex_mem;
assign flush_mem_wb_o      = flush_mem_wb;
assign wb_we_o             = wb_we;
assign wb_waddr_o          = wb_waddr;
assign wb_wdata_o          = wb_wdata;
assign ex_pc_o             = ex_pc;
assign ex_valid_o          = ex_valid;
endmodule
