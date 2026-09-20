// tb_cpu_bfs_top.sv - end-to-end CPU -> MMIO -> BFS integration test.
// The CPU runs real assembly, writes the accelerator registers, starts BFS,
// polls status, and leaves the hardware engine to solve the maze.

`timescale 1ns/1ps

module tb_cpu_bfs_top;

    localparam int W = 5;
    localparam int H = 5;
    localparam int NUM_CELLS = W * H;

    localparam logic [31:0] BFS_START_COL = 32'h00000300;
    localparam logic [31:0] BFS_START_ROW = 32'h00000304;
    localparam logic [31:0] BFS_END_COL   = 32'h00000308;
    localparam logic [31:0] BFS_END_ROW   = 32'h0000030C;
    localparam logic [31:0] BFS_CONTROL   = 32'h00000310;
    localparam logic [31:0] BFS_STATUS    = 32'h00000314;

    logic clk, rst_n;
    logic ps2_clk, ps2_data;
    logic vga_hsync, vga_vsync;
    logic [3:0] vga_red, vga_green, vga_blue;
    logic [31:0] cpu_pc;
    logic bfs_busy, bfs_done, bfs_path_found;

    cpu_bfs_top #(
        .GRID_WIDTH(W),
        .GRID_HEIGHT(H),
        .SLOWDOWN_FACTOR(1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .vga_hsync(vga_hsync), .vga_vsync(vga_vsync),
        .vga_red(vga_red), .vga_green(vga_green), .vga_blue(vga_blue),
        .cpu_pc(cpu_pc),
        .bfs_busy(bfs_busy), .bfs_done(bfs_done), .bfs_path_found(bfs_path_found)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int errors = 0;
    int write_count = 0;
    int status_read_count = 0;
    int start_pulse_count = 0;
    logic busy_seen = 1'b0;
    logic done_seen = 1'b0;

    function automatic bit expected_path_cell(input int id);
        begin
            case (id)
                0, 5, 10, 15, 16, 17, 18, 23, 24: expected_path_cell = 1'b1;
                default: expected_path_cell = 1'b0;
            endcase
        end
    endfunction

    // Observe the real CPU bus. No MMIO writes are forced from the testbench.
    always @(posedge clk) begin
        if (rst_n) begin
            if (!dut.load_done && cpu_pc !== 32'd0) begin
                $display("FAIL: CPU advanced before maze loading completed (PC=0x%08h)", cpu_pc);
                errors = errors + 1;
            end

            if (dut.mmio_write) begin
                case (write_count)
                    0: if (dut.mmio_addr !== BFS_START_COL || dut.mmio_wdata !== 32'd0) begin
                        $display("FAIL: first MMIO write should set start_col=0"); errors = errors + 1;
                    end
                    1: if (dut.mmio_addr !== BFS_START_ROW || dut.mmio_wdata !== 32'd0) begin
                        $display("FAIL: second MMIO write should set start_row=0"); errors = errors + 1;
                    end
                    2: if (dut.mmio_addr !== BFS_END_COL || dut.mmio_wdata !== 32'd4) begin
                        $display("FAIL: third MMIO write should set end_col=4"); errors = errors + 1;
                    end
                    3: if (dut.mmio_addr !== BFS_END_ROW || dut.mmio_wdata !== 32'd4) begin
                        $display("FAIL: fourth MMIO write should set end_row=4"); errors = errors + 1;
                    end
                    4: if (dut.mmio_addr !== BFS_CONTROL || dut.mmio_wdata[0] !== 1'b1) begin
                        $display("FAIL: fifth MMIO write should start BFS"); errors = errors + 1;
                    end
                    default: begin
                        $display("FAIL: unexpected extra MMIO write to 0x%08h", dut.mmio_addr);
                        errors = errors + 1;
                    end
                endcase
                write_count = write_count + 1;
            end

            if (dut.mmio_read && dut.mmio_addr == BFS_STATUS)
                status_read_count = status_read_count + 1;

            if (dut.bfs_start_pulse)
                start_pulse_count = start_pulse_count + 1;

            if (bfs_busy) busy_seen = 1'b1;
            if (bfs_done) done_seen = 1'b1;
        end
    end

    initial begin
        rst_n = 1'b0;
        ps2_clk = 1'b1;
        ps2_data = 1'b1;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;

        fork
            begin
                wait (bfs_done == 1'b1);
            end
            begin
                repeat (5000) @(posedge clk);
                $display("FAIL: CPU/BFS integration timed out");
                errors = errors + 1;
            end
        join_any
        disable fork;

        // Give monitors one extra edge to see the final state.
        @(posedge clk);
        #1;

        if (write_count == 5)
            $display("PASS: CPU performed the five expected MMIO writes");
        else begin
            $display("FAIL: expected 5 MMIO writes, saw %0d", write_count);
            errors = errors + 1;
        end

        if (dut.bfs_start_col_reg == 0 && dut.bfs_start_row_reg == 0 &&
            dut.bfs_end_col_reg == 4 && dut.bfs_end_row_reg == 4)
            $display("PASS: MMIO coordinate registers latched (0,0) -> (4,4)");
        else begin
            $display("FAIL: MMIO coordinate registers contain wrong values");
            errors = errors + 1;
        end

        if (start_pulse_count == 1)
            $display("PASS: exactly one CPU-caused BFS start pulse occurred");
        else begin
            $display("FAIL: expected exactly one BFS start pulse, saw %0d", start_pulse_count);
            errors = errors + 1;
        end

        if (busy_seen && done_seen)
            $display("PASS: BFS status progressed through busy to done");
        else begin
            $display("FAIL: did not observe both busy and done");
            errors = errors + 1;
        end

        if (status_read_count >= 2)
            $display("PASS: CPU repeatedly polled BFS_STATUS (%0d reads)", status_read_count);
        else begin
            $display("FAIL: expected repeated status polling, saw %0d read(s)", status_read_count);
            errors = errors + 1;
        end

        if (bfs_path_found)
            $display("PASS: BFS reported path_found");
        else begin
            $display("FAIL: BFS completed without path_found");
            errors = errors + 1;
        end

        for (int i = 0; i < NUM_CELLS; i++) begin
            if (dut.u_bfs.grid_mem[i][5] !== expected_path_cell(i)) begin
                $display("FAIL: cell %0d on_path=%b expected=%b",
                         i, dut.u_bfs.grid_mem[i][5], expected_path_cell(i));
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("PASS: final hardware path matches the hand-computed 5x5 shortest path");
            $display("\nALL CPU/BFS INTEGRATION CHECKS PASSED");
        end else begin
            $display("\n%0d CPU/BFS INTEGRATION CHECK(S) FAILED", errors);
        end

        $finish;
    end

endmodule
