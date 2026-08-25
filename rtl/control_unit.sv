// control_unit.sv
// Decodes the instruction opcode/funct3/funct7 fields into control
// signals for the rest of the single-cycle datapath.
//
// Supported opcodes (standard RV32I encodings):
//   R-type ALU   : 0110011
//   I-type ALU   : 0010011
//   LOAD (LW)    : 0000011
//   STORE (SW)   : 0100011
//   BRANCH       : 1100011
//   JAL          : 1101111
//   JALR         : 1100111
//   LUI          : 0110111
//   AUIPC        : 0010111
//
// Not implemented: FENCE, ECALL, EBREAK, CSR instructions.

`timescale 1ns/1ps

import alu_pkg::*;
import imm_pkg::*;

package ctrl_pkg;
    typedef enum logic [1:0] {
        WB_ALU  = 2'b00,  // writeback = ALU result
        WB_MEM  = 2'b01,  // writeback = data memory read
        WB_PC4  = 2'b10   // writeback = PC + 4  (JAL / JALR)
    } wb_sel_t;

    localparam logic [6:0] OPC_RTYPE  = 7'b0110011;
    localparam logic [6:0] OPC_ITYPE  = 7'b0010011;
    localparam logic [6:0] OPC_LOAD   = 7'b0000011;
    localparam logic [6:0] OPC_STORE  = 7'b0100011;
    localparam logic [6:0] OPC_BRANCH = 7'b1100011;
    localparam logic [6:0] OPC_JAL    = 7'b1101111;
    localparam logic [6:0] OPC_JALR   = 7'b1100111;
    localparam logic [6:0] OPC_LUI    = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
endpackage

import ctrl_pkg::*;

module control_unit (
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic        funct7_b5,   // instr[30]

    output alu_ctrl_t   alu_ctrl,
    output logic        alu_src_b,   // 0 = rs2, 1 = immediate
    output imm_type_t   imm_type,
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output wb_sel_t      wb_sel,
    output logic        is_branch,
    output logic        is_jal,
    output logic        is_jalr,
    output logic        alu_a_is_pc  // 1 => ALU operand A = PC (AUIPC)
);

    // Shared ALU decode for R-type and I-type-ALU instructions.
    function automatic alu_ctrl_t decode_alu_op(
        input logic [2:0] f3,
        input logic       f7b5,
        input logic       is_rtype
    );
        case (f3)
            3'b000: begin
                if (is_rtype && f7b5) decode_alu_op = ALU_SUB;
                else                  decode_alu_op = ALU_ADD;
            end
            3'b001:  decode_alu_op = ALU_SLL;
            3'b010:  decode_alu_op = ALU_SLT;
            3'b011:  decode_alu_op = ALU_SLTU;
            3'b100:  decode_alu_op = ALU_XOR;
            3'b101: begin
                if (f7b5) decode_alu_op = ALU_SRA;
                else      decode_alu_op = ALU_SRL;
            end
            3'b110:  decode_alu_op = ALU_OR;
            3'b111:  decode_alu_op = ALU_AND;
            default: decode_alu_op = ALU_ADD;
        endcase
    endfunction

    always_comb begin
        // Safe defaults (NOP-like / no side effects)
        alu_ctrl     = ALU_ADD;
        alu_src_b    = 1'b0;
        imm_type     = IMM_I;
        reg_write    = 1'b0;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        wb_sel       = WB_ALU;
        is_branch    = 1'b0;
        is_jal       = 1'b0;
        is_jalr      = 1'b0;
        alu_a_is_pc  = 1'b0;

        case (opcode)

            OPC_RTYPE: begin
                alu_ctrl  = decode_alu_op(funct3, funct7_b5, 1'b1);
                alu_src_b = 1'b0;      // operand B = rs2
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
            end

            OPC_ITYPE: begin
                // SLLI/SRLI/SRAI use funct7_b5 (instr[30]) the same way
                // shift amount is imm[4:0], handled naturally since ALU
                // uses b[4:0] as shift amount.
                alu_ctrl  = decode_alu_op(funct3, funct7_b5, 1'b0);
                alu_src_b = 1'b1;      // operand B = immediate
                imm_type  = IMM_I;
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
            end

            OPC_LOAD: begin // LW only
                alu_ctrl  = ALU_ADD;   // address = rs1 + imm
                alu_src_b = 1'b1;
                imm_type  = IMM_I;
                mem_read  = 1'b1;
                reg_write = 1'b1;
                wb_sel    = WB_MEM;
            end

            OPC_STORE: begin // SW only
                alu_ctrl  = ALU_ADD;   // address = rs1 + imm
                alu_src_b = 1'b1;
                imm_type  = IMM_S;
                mem_write = 1'b1;
            end

            OPC_BRANCH: begin
                // funct3[2]=0 -> equality test (ALU_SUB, use zero flag)
                // funct3[2]=1 -> less-than test (ALU_SLT / ALU_SLTU)
                if (!funct3[2])      alu_ctrl = ALU_SUB;
                else if (!funct3[1]) alu_ctrl = ALU_SLT;
                else                 alu_ctrl = ALU_SLTU;
                alu_src_b = 1'b0;      // operand B = rs2
                imm_type  = IMM_B;
                is_branch = 1'b1;
            end

            OPC_JAL: begin
                imm_type  = IMM_J;
                reg_write = 1'b1;
                wb_sel    = WB_PC4;
                is_jal    = 1'b1;
            end

            OPC_JALR: begin
                alu_ctrl  = ALU_ADD;   // target = rs1 + imm
                alu_src_b = 1'b1;
                imm_type  = IMM_I;
                reg_write = 1'b1;
                wb_sel    = WB_PC4;
                is_jalr   = 1'b1;
            end

            OPC_LUI: begin
                alu_ctrl  = ALU_PASSB; // result = imm
                alu_src_b = 1'b1;
                imm_type  = IMM_U;
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
            end

            OPC_AUIPC: begin
                alu_ctrl    = ALU_ADD; // result = PC + imm
                alu_src_b   = 1'b1;
                imm_type    = IMM_U;
                alu_a_is_pc = 1'b1;
                reg_write   = 1'b1;
                wb_sel      = WB_ALU;
            end

            default: ; // unsupported opcode - defaults above are inert
        endcase
    end

endmodule
