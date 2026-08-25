// data_mem.sv
// Simple word-addressed data RAM. Only 32-bit aligned LW/SW are
// supported in this core (no LB/LH/SB/SH in this subset).
//
// A single memory-mapped "console" address is carved out at the top of
// the address space: any SW to CONSOLE_ADDR prints the stored value to
// the simulation console. This isn't real hardware I/O - it's a
// simulation-only convenience so a running program can produce visible
// output instead of only being checkable via final register values.
// (On a real FPGA build, this would be replaced by an actual peripheral -
// e.g. UART or memory-mapped LEDs.)

`timescale 1ns/1ps

module data_mem #(
    parameter int DEPTH_WORDS = 1024
) (
    input  logic        clk,
    input  logic [31:0] addr,       // byte address
    input  logic [31:0] wdata,
    input  logic        mem_read,
    input  logic        mem_write,
    output logic [31:0] rdata
);

    localparam logic [31:0] CONSOLE_ADDR = 32'h00000100; // must fit in a 12-bit signed addi immediate

    logic [31:0] mem [0:DEPTH_WORDS-1];

    initial begin
        for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = 32'd0;
    end

    assign rdata = mem_read ? mem[addr[31:2]] : 32'd0;

    always_ff @(posedge clk) begin
        if (mem_write) begin
            mem[addr[31:2]] <= wdata;
            if (addr == CONSOLE_ADDR) begin
                $display("CONSOLE: %0d (0x%08h)", $signed(wdata), wdata);
            end
        end
    end

endmodule
