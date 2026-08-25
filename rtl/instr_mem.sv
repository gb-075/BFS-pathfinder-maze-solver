// instr_mem.sv
// Word-addressed instruction memory. Loaded from a $readmemh hex file
// (one 32-bit instruction per line) at elaboration time.
// addr is a BYTE address (from PC); internally we index by word.

`timescale 1ns/1ps

module instr_mem #(
    parameter int DEPTH_WORDS = 1024
) (
    input  logic [31:0] addr,       // byte address (PC)
    output logic [31:0] instr
);

    logic [31:0] mem [0:DEPTH_WORDS-1];
    string hexfile;

    initial begin
        for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = 32'h00000013; // NOP (ADDI x0,x0,0)
        // Read from a +HEXFILE=path.hex simulator plusarg (set at run time,
        // e.g. via `vvp sim.vvp +HEXFILE=program.hex`). Icarus does not
        // support runtime strings as module parameters, so we read the
        // plusarg directly here instead of taking HEXFILE as a parameter.
        if ($value$plusargs("HEXFILE=%s", hexfile) && hexfile != "") begin
            $readmemh(hexfile, mem);
        end
    end

    assign instr = mem[addr[31:2]]; // word-aligned index

endmodule
