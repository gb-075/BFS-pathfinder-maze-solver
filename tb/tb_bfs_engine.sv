// tb_bfs_engine.sv
// Verifies bfs_engine.sv against a hand-solved 5x5 test maze:
//
//   S . # . .
//   . . # . .
//   . # # . .
//   . . . . .
//   # # # . E
//
// Hand-computed shortest path (verified by manual BFS trace):
//   (0,0)->(1,0)->(2,0)->(3,0)->(3,1)->(3,2)->(3,3)->(4,3)->(4,4)
//   9 cells, cell ids: 0, 5, 10, 15, 16, 17, 18, 23, 24

`timescale 1ns/1ps

module tb_bfs_engine;

    localparam int W = 5;
    localparam int H = 5;
    localparam int NUM_CELLS = W * H;

    logic clk, rst_n, start;
    logic step_en;
    logic [$clog2(W)-1:0] start_col, end_col;
    logic [$clog2(H)-1:0] start_row, end_row;
    logic wall_write_en;
    logic [$clog2(NUM_CELLS)-1:0] wall_write_addr;
    logic wall_write_data;
    logic done, path_found, busy;
    logic [$clog2(NUM_CELLS)-1:0] read_addr;
    logic [5:0] read_cell;

    bfs_engine #(.GRID_WIDTH(W), .GRID_HEIGHT(H)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .step_en(step_en),
        .start_col(start_col), .start_row(start_row),
        .end_col(end_col), .end_row(end_row),
        .wall_write_en(wall_write_en),
        .wall_write_addr(wall_write_addr),
        .wall_write_data(wall_write_data),
        .done(done), .path_found(path_found), .busy(busy),
        .read_addr(read_addr), .read_cell(read_cell)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Wall bit per cell id, 1=wall. Row-major, matches the maze above.
    int wall_bits[0:24];
    int expected_path[0:8];

    initial begin
        // row 0: . . # . .
        wall_bits[0]=0; wall_bits[1]=0; wall_bits[2]=1; wall_bits[3]=0; wall_bits[4]=0;
        // row 1: . . # . .
        wall_bits[5]=0; wall_bits[6]=0; wall_bits[7]=1; wall_bits[8]=0; wall_bits[9]=0;
        // row 2: . # # . .
        wall_bits[10]=0; wall_bits[11]=1; wall_bits[12]=1; wall_bits[13]=0; wall_bits[14]=0;
        // row 3: . . . . .
        wall_bits[15]=0; wall_bits[16]=0; wall_bits[17]=0; wall_bits[18]=0; wall_bits[19]=0;
        // row 4: # # # . .
        wall_bits[20]=1; wall_bits[21]=1; wall_bits[22]=1; wall_bits[23]=0; wall_bits[24]=0;

        expected_path[0]=0;  expected_path[1]=5;  expected_path[2]=10; expected_path[3]=15;
        expected_path[4]=16; expected_path[5]=17; expected_path[6]=18; expected_path[7]=23;
        expected_path[8]=24;
    end

    int errors = 0;

    initial begin
        rst_n = 0;
        start = 0;
        step_en = 1;
        wall_write_en = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Load maze walls
        for (int i = 0; i < NUM_CELLS; i++) begin
            @(posedge clk);
            wall_write_en   = 1;
            wall_write_addr = i[$clog2(NUM_CELLS)-1:0];
            wall_write_data = wall_bits[i][0];
        end
        @(posedge clk);
        wall_write_en = 0;

        // Set start=(0,0), end=(4,4), pulse start
        start_row = 0; start_col = 0;
        end_row   = 4; end_col   = 4;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for completion (generous timeout)
        fork
            begin
                wait (done == 1'b1);
            end
            begin
                repeat (5000) @(posedge clk);
                $display("FAIL: bfs_engine never asserted done (timeout)");
                errors++;
            end
        join_any
        disable fork;

        if (done) begin
            if (path_found)
                $display("PASS: path_found asserted");
            else begin
                $display("FAIL: expected path_found=1, got 0");
                errors++;
            end

            // Check every cell's on_path bit against the expected set
            for (int i = 0; i < NUM_CELLS; i++) begin
                bit expected_on_path;
                bit actual_on_path;
                expected_on_path = 0;
                for (int j = 0; j < 9; j++) begin
                    if (expected_path[j] == i) expected_on_path = 1;
                end

                @(posedge clk);
                #1;
                read_addr = i[$clog2(NUM_CELLS)-1:0];
                #1;
                actual_on_path = read_cell[5];

                if (actual_on_path !== expected_on_path) begin
                    $display("FAIL: cell %0d on_path=%b, expected %b", i, actual_on_path, expected_on_path);
                    errors++;
                end
            end
            if (errors == 0)
                $display("PASS: all 25 cells' on_path bits match the hand-computed path exactly");
        end

        if (errors == 0)
            $display("\nALL BFS ENGINE CHECKS PASSED");
        else
            $display("\n%0d BFS ENGINE CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
