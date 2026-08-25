// cpu.sv
// Single-cycle RV32I-subset CPU datapath.
// Instructions supported: R-type ALU ops, I-type ALU ops (incl. shifts),
// LW, SW, BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL, JALR, LUI, AUIPC.
// Not supported: FENCE, ECALL/EBREAK, CSR instructions, byte/half loads.

`timescale 1ns/1ps

import alu_pkg::*;
import imm_pkg::*;
import ctrl_pkg::*;

module cpu (
    input  logic clk,
    input  logic rst_n,

    // Debug/verification visibility
    output logic [31:0] pc_out,
    output logic [31:0] instr_out
);

    // ---------------- Program Counter ----------------
    logic [31:0] pc, pc_next, pc_plus4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 32'd0;
        else        pc <= pc_next;
    end

    assign pc_plus4 = pc + 32'd4;
    assign pc_out   = pc;

    // ---------------- Fetch ----------------
    logic [31:0] instr;

    instr_mem u_imem (
        .addr  (pc),
        .instr (instr)
    );

    assign instr_out = instr;

    // ---------------- Decode fields ----------------
    // NOTE: these must be continuous (assign), not initializer syntax
    // ("logic x = ..."), which in SystemVerilog only evaluates once at
    // time 0 and would NOT track instr as it changes each cycle.
    logic [6:0] opcode;
    logic [4:0] rd_addr;
    logic [2:0] funct3;
    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    logic       funct7_b5;

    assign opcode    = instr[6:0];
    assign rd_addr   = instr[11:7];
    assign funct3    = instr[14:12];
    assign rs1_addr  = instr[19:15];
    assign rs2_addr  = instr[24:20];
    assign funct7_b5 = instr[30];

    // ---------------- Control ----------------
    alu_ctrl_t alu_ctrl;
    logic      alu_src_b;
    imm_type_t imm_type;
    logic      reg_write;
    logic      mem_read;
    logic      mem_write;
    wb_sel_t    wb_sel;
    logic      is_branch;
    logic      is_jal;
    logic      is_jalr;
    logic      alu_a_is_pc;

    control_unit u_ctrl (
        .opcode      (opcode),
        .funct3      (funct3),
        .funct7_b5   (funct7_b5),
        .alu_ctrl    (alu_ctrl),
        .alu_src_b   (alu_src_b),
        .imm_type    (imm_type),
        .reg_write   (reg_write),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .wb_sel      (wb_sel),
        .is_branch   (is_branch),
        .is_jal      (is_jal),
        .is_jalr     (is_jalr),
        .alu_a_is_pc (alu_a_is_pc)
    );

    // ---------------- Immediate ----------------
    logic [31:0] imm;

    imm_gen u_immgen (
        .instr    (instr),
        .imm_type (imm_type),
        .imm_out  (imm)
    );

    // ---------------- Register File ----------------
    logic [31:0] rs1_data, rs2_data, rd_data;

    regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1_addr),
        .rs2_addr (rs2_addr),
        .rd_addr  (rd_addr),
        .rd_data  (rd_data),
        .rd_we    (reg_write),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    // ---------------- ALU ----------------
    logic [31:0] alu_a, alu_b, alu_result;
    logic        alu_zero;

    assign alu_a = alu_a_is_pc ? pc : rs1_data;
    assign alu_b = alu_src_b   ? imm : rs2_data;

    alu u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_ctrl (alu_ctrl),
        .result   (alu_result),
        .zero     (alu_zero)
    );

    // ---------------- Data Memory ----------------
    logic [31:0] mem_rdata;

    data_mem u_dmem (
        .clk       (clk),
        .addr      (alu_result),
        .wdata     (rs2_data),
        .mem_read  (mem_read),
        .mem_write (mem_write),
        .rdata     (mem_rdata)
    );

    // ---------------- Writeback mux ----------------
    always_comb begin
        case (wb_sel)
            WB_ALU: rd_data = alu_result;
            WB_MEM: rd_data = mem_rdata;
            WB_PC4: rd_data = pc_plus4;
            default: rd_data = alu_result;
        endcase
    end

    // ---------------- Branch resolution ----------------
    // funct3[2]=0 -> equality (use ALU_SUB + zero flag)
    // funct3[2]=1 -> less-than (use ALU_SLT/ALU_SLTU + result bit0)
    // funct3[0]   -> inverts the base comparison (BNE/BGE/BGEU)
    logic branch_base, branch_taken;

    assign branch_base  = funct3[2] ? alu_result[0] : alu_zero;
    assign branch_taken = is_branch && (branch_base ^ funct3[0]);

    // ---------------- Next PC ----------------
    always_comb begin
        if (branch_taken)
            pc_next = pc + imm;
        else if (is_jal)
            pc_next = pc + imm;
        else if (is_jalr)
            pc_next = (rs1_data + imm) & 32'hFFFFFFFE;
        else
            pc_next = pc_plus4;
    end

    // ---------------- Assertions (design-internal invariants) ----------------
    // Immediate assertions checking properties that should ALWAYS hold
    // regardless of which program is running, independent of the directed
    // register checks in the testbench. (Concurrent `assert property`/SVA
    // syntax was tried first but Icarus Verilog's support for it is
    // incomplete; immediate assertions inside always_ff are fully
    // supported and check the same invariants.)
    `ifndef SYNTHESIS
        always_ff @(posedge clk) begin
            if (rst_n) begin
                // x0 must always read as zero.
                assert (rs1_addr != 5'd0 || rs1_data == 32'd0)
                    else $error("ASSERTION FAILED: x0 read as nonzero (rs1) at t=%0t", $time);

                // PC must always be word-aligned - true for this ISA
                // subset since we don't support compressed instructions.
                assert (pc[1:0] == 2'b00)
                    else $error("ASSERTION FAILED: PC misaligned: 0x%08h at t=%0t", pc, $time);
            end
        end
    `endif

endmodule
