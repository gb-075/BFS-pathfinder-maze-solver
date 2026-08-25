// regfile.sv
// 32 x 32-bit register file. x0 is hardwired to zero.
// Two combinational read ports, one synchronous write port.
// Write-then-read same cycle: read reflects the OLD value (standard
// single-cycle behavior since the write happens at the clock edge).

`timescale 1ns/1ps

module regfile (
    input  logic        clk,
    input  logic         rst_n,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    input  logic        rd_we,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

    logic [31:0] regs [1:31]; // x0 not stored, always 0

    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 : regs[rs2_addr];

    integer i;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i <= 31; i = i + 1)
                regs[i] <= 32'd0;
        end else if (rd_we && rd_addr != 5'd0) begin
            regs[rd_addr] <= rd_data;
        end
    end

endmodule
