// data_mem.sv - regular memory for lw/sw, plus a "console" print hack for testing

`timescale 1ns/1ps

module data_mem #(
    parameter int DEPTH_WORDS = 1024
) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic        mem_read,
    input  logic        mem_write,
    output logic [31:0] rdata
);

    localparam logic [31:0] CONSOLE_ADDR = 32'h00000100;

    logic [31:0] mem [0:DEPTH_WORDS-1];

    initial begin
        for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = 32'd0;
    end

    assign rdata = mem_read ? mem[addr[31:2]] : 32'd0;

    always_ff @(posedge clk) begin
        if (mem_write == 1'b1) begin
            mem[addr[31:2]] <= wdata;
            if (addr == CONSOLE_ADDR) begin
                $display("CONSOLE: %0d (0x%08h)", $signed(wdata), wdata);
            end
        end
    end

endmodule
