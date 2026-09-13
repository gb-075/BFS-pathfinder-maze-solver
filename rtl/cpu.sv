// cpu.sv - top level, wires everything together into a single-cycle CPU

`timescale 1ns/1ps

import alu_pkg::*;
import imm_pkg::*;
import ctrl_pkg::*;

module cpu (
    input  logic clk,
    input  logic rst_n,

    output logic [31:0] pc_out,
    output logic [31:0] instr_out
);

    logic [31:0] pc, pc_next;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc <= 32'd0;
        else        pc <= pc_next;
    end

    assign pc_out = pc;

    logic [31:0] instr;

    instr_mem u_imem (
        .addr  (pc),
        .instr (instr)
    );

    assign instr_out = instr;

    // NOTE: these have to be "assign", not "logic x = instr[...]" -
    // learned that one the hard way (only runs once at time 0, doesn't
    // stay connected to instr as it changes)
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

    logic [31:0] imm;

    imm_gen u_immgen (
        .instr    (instr),
        .imm_type (imm_type),
        .imm_out  (imm)
    );

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

    logic [31:0] mem_rdata;

    data_mem u_dmem (
        .clk       (clk),
        .addr      (alu_result),
        .wdata     (rs2_data),
        .mem_read  (mem_read),
        .mem_write (mem_write),
        .rdata     (mem_rdata)
    );

    always_comb begin
        if (wb_sel == WB_ALU) begin
            rd_data = alu_result;
        end else if (wb_sel == WB_MEM) begin
            rd_data = mem_rdata;
        end else if (wb_sel == WB_PC4) begin
            rd_data = pc + 32'd4;
        end else begin
            rd_data = alu_result;
        end
    end

    // reuse the ALU for branch compares instead of a separate comparator -
    // beq/bne use subtract+zero, blt/bge/bltu/bgeu use slt/sltu
    logic branch_base, branch_taken;

    assign branch_base  = funct3[2] ? alu_result[0] : alu_zero;
    assign branch_taken = is_branch && (branch_base ^ funct3[0]);

    always_comb begin
        if (branch_taken) begin
            pc_next = pc + imm;
        end else if (is_jal) begin
            pc_next = pc + imm;
        end else if (is_jalr) begin
            pc_next = (rs1_data + imm) & 32'hFFFFFFFE;
        end else begin
            pc_next = pc + 32'd4;
        end
    end

    `ifndef SYNTHESIS
        always_ff @(posedge clk) begin
            if (rst_n) begin
                assert (rs1_addr != 5'd0 || rs1_data == 32'd0)
                    else $error("ASSERTION FAILED: x0 read as nonzero (rs1) at t=%0t", $time);
                assert (pc[1:0] == 2'b00)
                    else $error("ASSERTION FAILED: PC misaligned: 0x%08h at t=%0t", pc, $time);
            end
        end
    `endif

endmodule
