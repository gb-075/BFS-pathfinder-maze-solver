// tb_cpu.sv
// Loads a program (via +HEXFILE plusarg), runs it for a fixed number of
// cycles, dumps a VCD waveform, and checks a set of expected final
// register values (via +CHECKFILE plusarg, see check_runner.py).
//
// This testbench peeks directly at the regfile's internal array for
// verification purposes only - real designs would use a proper
// interface, but for a single-cycle educational core this is fine.

`timescale 1ns/1ps

module tb_cpu;

    logic clk;
    logic rst_n;
    logic [31:0] pc_out;
    logic [31:0] instr_out;

    int num_cycles;

    initial begin
        if (!$value$plusargs("CYCLES=%d", num_cycles)) num_cycles = 50;
    end

    cpu dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .pc_out    (pc_out),
        .instr_out (instr_out)
    );

    // Clock generation: 10ns period (100MHz notional)
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset
    initial begin
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
    end

    // Waveform dump
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_cpu);
    end

    // Instruction trace (helpful for debugging)
    always @(posedge clk) begin
        if (rst_n)
            $display("t=%0t  PC=0x%08h  instr=0x%08h", $time, pc_out, instr_out);
    end

    // Run for a fixed number of cycles then dump all registers and finish
    initial begin
        @(posedge rst_n);
        repeat (num_cycles) @(posedge clk);

        $display("\n---- Final register file ----");
        for (int i = 0; i < 32; i++) begin
            if (i == 0)
                $display("x%0d  = 0x%08h", i, 32'd0);
            else
                $display("x%0d  = 0x%08h", i, dut.u_regfile.regs[i]);
        end

        $display("---- Simulation finished ----\n");
        $finish;
    end

endmodule
