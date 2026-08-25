#!/usr/bin/env python3
"""
Minimal assembler for the RV32I subset implemented by this core.

Supported instructions:
  R-type : add sub and or xor sll srl sra slt sltu
  I-type : addi andi ori xori slti sltiu slli srli srai lw jalr
  S-type : sw
  B-type : beq bne blt bge bltu bgeu
  J-type : jal
  U-type : lui auipc

Syntax (one instruction per line, '#' starts a comment):
  add  rd, rs1, rs2
  addi rd, rs1, imm
  lw   rd, imm(rs1)
  sw   rs2, imm(rs1)
  beq  rs1, rs2, label
  jal  rd, label
  lui  rd, imm
  label:

Registers may be written as x0-x31 or the ABI names (zero, ra, sp, ...).
Output: one 32-bit instruction per line, in hex, for $readmemh.

Usage: python3 assembler.py program.asm program.hex
"""
import sys
import re

ABI_NAMES = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7, "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15,
    "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23,
    "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}

R_TYPE = {
    "add":  (0b0110011, 0b000, 0),
    "sub":  (0b0110011, 0b000, 1),
    "sll":  (0b0110011, 0b001, 0),
    "slt":  (0b0110011, 0b010, 0),
    "sltu": (0b0110011, 0b011, 0),
    "xor":  (0b0110011, 0b100, 0),
    "srl":  (0b0110011, 0b101, 0),
    "sra":  (0b0110011, 0b101, 1),
    "or":   (0b0110011, 0b110, 0),
    "and":  (0b0110011, 0b111, 0),
}

I_TYPE_ALU = {
    "addi":  (0b0010011, 0b000, None),
    "slti":  (0b0010011, 0b010, None),
    "sltiu": (0b0010011, 0b011, None),
    "xori":  (0b0010011, 0b100, None),
    "ori":   (0b0010011, 0b110, None),
    "andi":  (0b0010011, 0b111, None),
    "slli":  (0b0010011, 0b001, 0),
    "srli":  (0b0010011, 0b101, 0),
    "srai":  (0b0010011, 0b101, 1),
}

B_TYPE = {
    "beq":  0b000, "bne":  0b001, "blt":  0b100,
    "bge":  0b101, "bltu": 0b110, "bgeu": 0b111,
}


def reg(tok):
    tok = tok.strip().rstrip(',')
    if tok in ABI_NAMES:
        return ABI_NAMES[tok]
    if tok.startswith('x'):
        return int(tok[1:])
    raise ValueError(f"Unknown register: {tok}")


def imm_val(tok, labels=None, cur_addr=None, rel=False):
    tok = tok.strip().rstrip(',')
    if labels is not None and tok in labels:
        target = labels[tok]
        return target - cur_addr if rel else target
    return int(tok, 0)


def to_bits(val, width):
    return val & ((1 << width) - 1)


def encode_r(mnemonic, rd, rs1, rs2):
    opcode, funct3, funct7b5 = R_TYPE[mnemonic]
    funct7 = 0b0100000 if funct7b5 else 0b0000000
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_i(opcode, funct3, rd, rs1, imm12, shamt_variant=None):
    if shamt_variant is not None:
        funct7 = 0b0100000 if shamt_variant else 0b0000000
        imm_field = (funct7 << 5) | (imm12 & 0x1F)
    else:
        imm_field = to_bits(imm12, 12)
    return (imm_field << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def encode_s(rs1, rs2, imm12):
    imm12 = to_bits(imm12, 12)
    imm_11_5 = (imm12 >> 5) & 0x7F
    imm_4_0 = imm12 & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0b010 << 12) | (imm_4_0 << 7) | 0b0100011


def encode_b(rs1, rs2, funct3, imm13):
    imm13 = to_bits(imm13, 13)
    bit12 = (imm13 >> 12) & 1
    bit11 = (imm13 >> 11) & 1
    bits10_5 = (imm13 >> 5) & 0x3F
    bits4_1 = (imm13 >> 1) & 0xF
    return (bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | 0b1100011


def encode_j(rd, imm21):
    imm21 = to_bits(imm21, 21)
    bit20 = (imm21 >> 20) & 1
    bits10_1 = (imm21 >> 1) & 0x3FF
    bit11 = (imm21 >> 11) & 1
    bits19_12 = (imm21 >> 12) & 0xFF
    return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | (rd << 7) | 0b1101111


def encode_u(rd, imm20, opcode):
    return (to_bits(imm20, 20) << 12) | (rd << 7) | opcode


def first_pass(lines):
    """Compute label -> address map (word count * 4)."""
    labels = {}
    addr = 0
    for line in lines:
        line = line.split('#')[0].strip()
        if not line:
            continue
        if line.endswith(':'):
            labels[line[:-1]] = addr
        else:
            addr += 4
    return labels


def assemble(lines):
    labels = first_pass(lines)
    out = []
    addr = 0

    for raw in lines:
        line = raw.split('#')[0].strip()
        if not line or line.endswith(':'):
            continue

        parts = re.split(r'\s+', line, maxsplit=1)
        mnemonic = parts[0].lower()
        rest = parts[1] if len(parts) > 1 else ""
        args = [a.strip() for a in rest.split(',')] if rest else []

        word = None

        if mnemonic in R_TYPE:
            rd, rs1, rs2 = reg(args[0]), reg(args[1]), reg(args[2])
            word = encode_r(mnemonic, rd, rs1, rs2)

        elif mnemonic in ("slli", "srli", "srai"):
            opcode, funct3, variant = I_TYPE_ALU[mnemonic]
            rd, rs1 = reg(args[0]), reg(args[1])
            shamt = imm_val(args[2])
            word = encode_i(opcode, funct3, rd, rs1, shamt, shamt_variant=variant)

        elif mnemonic in I_TYPE_ALU:
            opcode, funct3, _ = I_TYPE_ALU[mnemonic]
            rd, rs1 = reg(args[0]), reg(args[1])
            imm12 = imm_val(args[2])
            word = encode_i(opcode, funct3, rd, rs1, imm12)

        elif mnemonic == "lw":
            rd = reg(args[0])
            m = re.match(r'(-?\w+)\((\w+)\)', args[1])
            imm_tok, rs1 = m.group(1), reg(m.group(2))
            imm12 = int(imm_tok, 0) if imm_tok not in labels else labels[imm_tok]
            word = encode_i(0b0000011, 0b010, rd, rs1, imm12)

        elif mnemonic == "jalr":
            rd = reg(args[0])
            m = re.match(r'(-?\w+)\((\w+)\)', args[1])
            imm_tok, rs1 = m.group(1), reg(m.group(2))
            # If a label is given, resolve to its absolute address. This
            # only makes sense when rs1 is x0 (address = 0 + label_addr).
            imm12 = int(imm_tok, 0) if imm_tok not in labels else labels[imm_tok]
            word = encode_i(0b1100111, 0b000, rd, rs1, imm12)

        elif mnemonic == "sw":
            rs2 = reg(args[0])
            m = re.match(r'(-?\w+)\((\w+)\)', args[1])
            imm12, rs1 = int(m.group(1), 0), reg(m.group(2))
            word = encode_s(rs1, rs2, imm12)

        elif mnemonic in B_TYPE:
            rs1, rs2 = reg(args[0]), reg(args[1])
            target = imm_val(args[2], labels, addr, rel=True)
            word = encode_b(rs1, rs2, B_TYPE[mnemonic], target)

        elif mnemonic == "jal":
            rd = reg(args[0])
            target = imm_val(args[1], labels, addr, rel=True)
            word = encode_j(rd, target)

        elif mnemonic == "lui":
            rd = reg(args[0])
            word = encode_u(rd, imm_val(args[1]), 0b0110111)

        elif mnemonic == "auipc":
            rd = reg(args[0])
            word = encode_u(rd, imm_val(args[1]), 0b0010111)

        elif mnemonic == "nop":
            word = 0x00000013  # addi x0, x0, 0

        else:
            raise ValueError(f"Unsupported instruction: {mnemonic}")

        out.append(word)
        addr += 4

    return out


def main():
    if len(sys.argv) != 3:
        print("Usage: python3 assembler.py <input.asm> <output.hex>")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        lines = f.readlines()

    words = assemble(lines)

    with open(sys.argv[2], 'w') as f:
        for w in words:
            f.write(f"{w & 0xFFFFFFFF:08x}\n")

    print(f"Assembled {len(words)} instructions -> {sys.argv[2]}")


if __name__ == "__main__":
    main()
