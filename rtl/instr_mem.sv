// instr_mem.sv - holds the program, loaded from a hex file

`timescale 1ns/1ps

module instr_mem #(
    parameter int DEPTH_WORDS = 1024
) (
    input  logic [31:0] addr,
    output logic [31:0] instr
);

    logic [31:0] mem [0:DEPTH_WORDS-1];
    string hexfile;

    initial begin
        for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = 32'h00000013; // NOP
        if ($value$plusargs("HEXFILE=%s", hexfile)) begin
            if (hexfile != "") begin
                $readmemh(hexfile, mem);
            end
        end
    end

    assign instr = mem[addr[31:2]]; // byte addr -> word index

endmodule
