// bfs_engine.sv
// Hardware BFS (breadth-first search) maze solver.
//
// This is a genuine hardware accelerator implementing a graph
// algorithm as an FSM + hardware queue + memory, NOT software running
// on a CPU. Given a maze (wall/open per cell) and start/end
// coordinates, it finds the shortest path (if one exists) using
// standard 4-directional grid BFS, and reconstructs the actual path by
// storing a "parent direction" per cell during the search, then
// backtracking from the end cell once found.
//
// Per-cell state (packed into CELL_WIDTH bits each, stored in
// grid_mem):
//   bit 0     : wall        (1 = wall, 0 = open; loaded from maze ROM)
//   bit 1     : visited     (set when a cell enters the BFS frontier)
//   bits [4:2]: parent_dir  (0=none/start, 1=up, 2=down, 3=left, 4=right -
//                            direction FROM this cell back toward its parent)
//   bit 5     : on_path     (set during backtrack, for the final rendered path)
//
// FSM: IDLE -> INIT -> BFS_DEQUEUE -> BFS_NEIGHBOR (x4 directions) ->
//      (loop back to BFS_DEQUEUE, or -> FOUND / NO_PATH) ->
//      BACKTRACK -> DONE

`timescale 1ns/1ps

module bfs_engine #(
    parameter int GRID_WIDTH  = 10,
    parameter int GRID_HEIGHT = 8
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,                 // pulse to begin a new search
    input  logic step_en,               // when 0, freeze FSM progress (once
                                         // searching) - used to throttle how
                                         // fast the search visibly animates
                                         // on a real display; tie to 1'b1 for
                                         // full-speed operation (e.g. in
                                         // testbenches). Wall loading and
                                         // `start` detection in S_IDLE are
                                         // NOT gated by this - only the
                                         // active search/backtrack states are.

    input  logic [$clog2(GRID_WIDTH)-1:0]  start_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] start_row,
    input  logic [$clog2(GRID_WIDTH)-1:0]  end_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] end_row,

    // Maze wall data: caller writes wall bits before pulsing `start`.
    input  logic                            wall_write_en,
    input  logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0] wall_write_addr,
    input  logic                            wall_write_data,

    output logic done,                  // path search finished (found or not)
    output logic path_found,
    output logic busy,

    // Read interface for a renderer (or a testbench) to inspect final
    // cell state after `done`.
    input  logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0] read_addr,
    output logic [5:0] read_cell                       // {on_path, parent_dir[2:0], visited, wall}
);

    localparam int NUM_CELLS  = GRID_WIDTH * GRID_HEIGHT;
    localparam int CELL_BITS  = $clog2(NUM_CELLS);
    localparam int COL_BITS   = $clog2(GRID_WIDTH);
    localparam int ROW_BITS   = $clog2(GRID_HEIGHT);

    // ---------------- Grid memory: 6 bits/cell ----------------
    logic [5:0] grid_mem [0:NUM_CELLS-1];

    assign read_cell = grid_mem[read_addr];

    // ---------------- BFS queue (FIFO of cell ids) ----------------
    logic [CELL_BITS-1:0] queue_mem [0:NUM_CELLS-1]; // worst case every cell enqueued once
    logic [CELL_BITS-1:0] q_head, q_tail;
    logic q_empty;

    assign q_empty = (q_head == q_tail);

    // ---------------- FSM ----------------
    typedef enum logic [3:0] {
        S_IDLE, S_INIT, S_INIT_LOOP,
        S_DEQUEUE, S_CHECK_END,
        S_NEIGHBOR_UP, S_NEIGHBOR_DOWN, S_NEIGHBOR_LEFT, S_NEIGHBOR_RIGHT,
        S_NEXT_CELL_OR_DONE,
        S_BACKTRACK_INIT, S_BACKTRACK_STEP,
        S_DONE, S_NO_PATH
    } state_t;

    state_t state;

    logic [CELL_BITS-1:0] init_idx;
    logic [CELL_BITS-1:0] cur_id;
    logic [COL_BITS-1:0]  cur_col;
    logic [ROW_BITS-1:0]  cur_row;
    logic [CELL_BITS-1:0] start_id, end_id;

    logic [COL_BITS-1:0] bt_col;
    logic [ROW_BITS-1:0] bt_row;
    logic [CELL_BITS-1:0] bt_id;

    logic [CELL_BITS-1:0] nid; // scratch: neighbor cell id, computed then used within the same cycle

    assign start_id = start_row * GRID_WIDTH + start_col;
    assign end_id   = end_row   * GRID_WIDTH + end_col;

    assign busy       = (state != S_IDLE) && (state != S_DONE) && (state != S_NO_PATH);
    assign done        = (state == S_DONE) || (state == S_NO_PATH);
    assign path_found  = (state == S_DONE);

    // Direction encoding for parent_dir field
    localparam logic [2:0] DIR_NONE  = 3'd0;
    localparam logic [2:0] DIR_UP    = 3'd1;
    localparam logic [2:0] DIR_DOWN  = 3'd2;
    localparam logic [2:0] DIR_LEFT  = 3'd3;
    localparam logic [2:0] DIR_RIGHT = 3'd4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            q_head  <= '0;
            q_tail  <= '0;
            init_idx <= '0;
        end else begin
            if (state == S_IDLE) begin
                // Wall loading and start-detection always respond
                // immediately, regardless of step_en - throttling only
                // applies once a search is actually in progress.
                if (wall_write_en) begin
                    grid_mem[wall_write_addr][0] <= wall_write_data; // wall bit
                end
                if (start) begin
                    state <= S_INIT;
                    init_idx <= '0;
                end
            end else if (step_en) begin
            case (state)

                // Clear visited/parent/on_path bits for every cell
                // (wall bits were already loaded and must be preserved).
                S_INIT: begin
                    grid_mem[init_idx][5:1] <= 5'd0;
                    if (init_idx == NUM_CELLS - 1) begin
                        state <= S_INIT_LOOP;
                    end else begin
                        init_idx <= init_idx + 1'b1;
                    end
                end

                S_INIT_LOOP: begin
                    // Enqueue the start cell.
                    grid_mem[start_id][1] <= 1'b1; // visited
                    grid_mem[start_id][4:2] <= DIR_NONE;
                    queue_mem[0] <= start_id;
                    q_head <= '0;
                    q_tail <= {{(CELL_BITS-1){1'b0}}, 1'b1};
                    cur_id  <= start_id;
                    cur_row <= start_row;
                    cur_col <= start_col;
                    state <= S_CHECK_END;
                end

                S_DEQUEUE: begin
                    if (q_empty) begin
                        state <= S_NO_PATH;
                    end else begin
                        cur_id  <= queue_mem[q_head];
                        cur_row <= queue_mem[q_head] / GRID_WIDTH;
                        cur_col <= queue_mem[q_head] % GRID_WIDTH;
                        q_head  <= q_head + 1'b1;
                        state   <= S_CHECK_END;
                    end
                end

                S_CHECK_END: begin
                    if (cur_id == end_id) begin
                        state <= S_BACKTRACK_INIT;
                    end else begin
                        state <= S_NEIGHBOR_UP;
                    end
                end

                // ---- Check each of 4 neighbors, one FSM state each ----
                // IMPORTANT: parent_dir stores "which direction to move FROM
                // this cell TO REACH its parent" (used during backtrack).
                // So if we discover a neighbor by moving UP from cur, that
                // neighbor's parent (cur) is BELOW it - so we store DIR_DOWN,
                // not DIR_UP. Same inverted relationship for the other three.
                S_NEIGHBOR_UP: begin
                    if (cur_row != 0) begin
                        nid = (cur_row - 1) * GRID_WIDTH + cur_col;
                        if (!grid_mem[nid][0] && !grid_mem[nid][1]) begin // open and unvisited
                            grid_mem[nid][1]   <= 1'b1;
                            grid_mem[nid][4:2] <= DIR_DOWN; // parent is below this neighbor
                            queue_mem[q_tail]  <= nid;
                            q_tail <= q_tail + 1'b1;
                        end
                    end
                    state <= S_NEIGHBOR_DOWN;
                end

                S_NEIGHBOR_DOWN: begin
                    if (cur_row != GRID_HEIGHT - 1) begin
                        nid = (cur_row + 1) * GRID_WIDTH + cur_col;
                        if (!grid_mem[nid][0] && !grid_mem[nid][1]) begin
                            grid_mem[nid][1]   <= 1'b1;
                            grid_mem[nid][4:2] <= DIR_UP; // parent is above this neighbor
                            queue_mem[q_tail]  <= nid;
                            q_tail <= q_tail + 1'b1;
                        end
                    end
                    state <= S_NEIGHBOR_LEFT;
                end

                S_NEIGHBOR_LEFT: begin
                    if (cur_col != 0) begin
                        nid = cur_row * GRID_WIDTH + (cur_col - 1);
                        if (!grid_mem[nid][0] && !grid_mem[nid][1]) begin
                            grid_mem[nid][1]   <= 1'b1;
                            grid_mem[nid][4:2] <= DIR_RIGHT; // parent is to the right
                            queue_mem[q_tail]  <= nid;
                            q_tail <= q_tail + 1'b1;
                        end
                    end
                    state <= S_NEIGHBOR_RIGHT;
                end

                S_NEIGHBOR_RIGHT: begin
                    if (cur_col != GRID_WIDTH - 1) begin
                        nid = cur_row * GRID_WIDTH + (cur_col + 1);
                        if (!grid_mem[nid][0] && !grid_mem[nid][1]) begin
                            grid_mem[nid][1]   <= 1'b1;
                            grid_mem[nid][4:2] <= DIR_LEFT; // parent is to the left
                            queue_mem[q_tail]  <= nid;
                            q_tail <= q_tail + 1'b1;
                        end
                    end
                    state <= S_DEQUEUE;
                end

                // ---- Backtrack from end cell to start, marking on_path ----
                S_BACKTRACK_INIT: begin
                    bt_row <= end_row;
                    bt_col <= end_col;
                    bt_id  <= end_id;
                    state  <= S_BACKTRACK_STEP;
                end

                S_BACKTRACK_STEP: begin
                    grid_mem[bt_id][5] <= 1'b1; // mark on_path
                    if (bt_id == start_id) begin
                        state <= S_DONE;
                    end else begin
                        case (grid_mem[bt_id][4:2])
                            DIR_UP:    begin bt_row <= bt_row - 1'b1; bt_id <= bt_id - GRID_WIDTH; end
                            DIR_DOWN:  begin bt_row <= bt_row + 1'b1; bt_id <= bt_id + GRID_WIDTH; end
                            DIR_LEFT:  begin bt_col <= bt_col - 1'b1; bt_id <= bt_id - 1'b1; end
                            DIR_RIGHT: begin bt_col <= bt_col + 1'b1; bt_id <= bt_id + 1'b1; end
                            default:   state <= S_NO_PATH; // shouldn't happen if a path was found
                        endcase
                    end
                end

                S_DONE:    ; // hold, wait for next `start`
                S_NO_PATH: ; // hold, wait for next `start`

                default: state <= S_IDLE;
            endcase

            // Allow re-arming from DONE/NO_PATH on a new `start` pulse
            if ((state == S_DONE || state == S_NO_PATH) && start) begin
                state <= S_INIT;
                init_idx <= '0;
            end
            end
        end
    end

endmodule
