// control_unit.sv
// decodes opcode/funct3/funct7 into control signals for the datapath

`timescale 1ns/1ps

import alu_pkg::*;
import imm_pkg::*;

package ctrl_pkg;
    typedef enum logic [1:0] {
        WB_ALU  = 2'b00,
        WB_MEM  = 2'b01,
        WB_PC4  = 2'b10
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
    input  logic        funct7_b5,

    output alu_ctrl_t   alu_ctrl,
    output logic        alu_src_b,
    output imm_type_t   imm_type,
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output wb_sel_t      wb_sel,
    output logic        is_branch,
    output logic        is_jal,
    output logic        is_jalr,
    output logic        alu_a_is_pc
);

    always_comb begin
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
                // add/sub and srl/sra share funct3, funct7 bit 5 tells them apart
                case (funct3)
                    3'b000:  if (funct7_b5) alu_ctrl = ALU_SUB; else alu_ctrl = ALU_ADD;
                    3'b001:  alu_ctrl = ALU_SLL;
                    3'b010:  alu_ctrl = ALU_SLT;
                    3'b011:  alu_ctrl = ALU_SLTU;
                    3'b100:  alu_ctrl = ALU_XOR;
                    3'b101:  if (funct7_b5) alu_ctrl = ALU_SRA; else alu_ctrl = ALU_SRL;
                    3'b110:  alu_ctrl = ALU_OR;
                    3'b111:  alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
                alu_src_b = 1'b0;
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
            end

            OPC_ITYPE: begin
                // same funct3 table as above but addi doesn't care about funct7
                // (only slli/srli/srai actually use that bit, for the shift type)
                case (funct3)
                    3'b000:  alu_ctrl = ALU_ADD;
                    3'b001:  alu_ctrl = ALU_SLL;
                    3'b010:  alu_ctrl = ALU_SLT;
                    3'b011:  alu_ctrl = ALU_SLTU;
                    3'b100:  alu_ctrl = ALU_XOR;
                    3'b101:  if (funct7_b5) alu_ctrl = ALU_SRA; else alu_ctrl = ALU_SRL;
                    3'b110:  alu_ctrl = ALU_OR;
                    3'b111:  alu_ctrl = ALU_AND;
                    default: alu_ctrl = ALU_ADD;
                endcase
                alu_src_b = 1'b1;
                imm_type  = IMM_I;
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
            end

            OPC_LOAD: begin
                alu_ctrl  = ALU_ADD;
                alu_src_b = 1'b1;
                imm_type  = IMM_I;
                mem_read  = 1'b1;
                reg_write = 1'b1;
                wb_sel    = WB_MEM;
            end

            OPC_STORE: begin
                alu_ctrl  = ALU_ADD;
                alu_src_b = 1'b1;
                imm_type  = IMM_S;
                mem_write = 1'b1;
            end

            OPC_BRANCH: begin
                if (!funct3[2])      alu_ctrl = ALU_SUB;
                else if (!funct3[1]) alu_ctrl = ALU_SLT;
                else                 alu_ctrl = ALU_SLTU;
                alu_src_b = 1'b0;
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
                alu_ctrl  = ALU_ADD;
                alu_src_b = 1'b1;
                imm_type  = IMM_I;
                reg_write = 1'b1;
                wb_sel    = WB_PC4;
                is_jalr   = 1'b1;
            end

            OPC_LUI: begin
                alu_ctrl  = ALU_PASSB;
                alu_src_b = 1'b1;
                imm_type  = IMM_U;
                reg_write = 1'b1;
                wb_sel    = WB_ALU;
            end

            OPC_AUIPC: begin
                alu_ctrl    = ALU_ADD;
                alu_src_b   = 1'b1;
                imm_type    = IMM_U;
                alu_a_is_pc = 1'b1;
                reg_write   = 1'b1;
                wb_sel      = WB_ALU;
            end

            default: ;
        endcase
    end

endmodule
