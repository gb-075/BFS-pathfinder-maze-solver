// alu.sv
// Combinational ALU. alu_ctrl selects the operation.
// Encoding chosen arbitrarily (not tied to RISC-V funct fields) -
// control_unit.sv is responsible for translating funct3/funct7/opcode
// into these alu_ctrl codes.

`timescale 1ns/1ps

package alu_pkg;
    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_AND  = 4'b0010,
        ALU_OR   = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SLL  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_SLT  = 4'b1000,
        ALU_SLTU = 4'b1001,
        ALU_PASSB= 4'b1010  // pass operand B through (used for LUI)
    } alu_ctrl_t;
endpackage

import alu_pkg::*;

module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  alu_ctrl_t   alu_ctrl,
    output logic [31:0] result,
    output logic        zero
);

    always_comb begin
        case (alu_ctrl)
            ALU_ADD:   result = a + b;
            ALU_SUB:   result = a - b;
            ALU_AND:   result = a & b;
            ALU_OR:    result = a | b;
            ALU_XOR:   result = a ^ b;
            ALU_SLL:   result = a << b[4:0];
            ALU_SRL:   result = a >> b[4:0];
            ALU_SRA:   result = $signed(a) >>> b[4:0];
            ALU_SLT:   result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU:  result = (a < b) ? 32'd1 : 32'd0;
            ALU_PASSB: result = b;
            default:   result = 32'hxxxxxxxx;
        endcase
    end

    assign zero = (result == 32'd0);

endmodule
