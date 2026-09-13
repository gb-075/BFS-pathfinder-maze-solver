// bfs_engine.sv - hardware maze solver. FSM + queue + grid memory, does
// actual BFS (breadth-first search) in hardware instead of running on the CPU

`timescale 1ns/1ps

module bfs_engine #(
    parameter int GRID_WIDTH  = 10,
    parameter int GRID_HEIGHT = 8
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    input  logic step_en, // throttles how fast the search visibly progresses

    input  logic [$clog2(GRID_WIDTH)-1:0]  start_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] start_row,
    input  logic [$clog2(GRID_WIDTH)-1:0]  end_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] end_row,

    input  logic                            wall_write_en,
    input  logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0] wall_write_addr,
    input  logic                            wall_write_data,

    output logic done,
    output logic path_found,
    output logic busy,

    input  logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0] read_addr,
    output logic [5:0] read_cell
);

    localparam int NUM_CELLS  = GRID_WIDTH * GRID_HEIGHT;
    localparam int CELL_BITS  = $clog2(NUM_CELLS);
    localparam int COL_BITS   = $clog2(GRID_WIDTH);
    localparam int ROW_BITS   = $clog2(GRID_HEIGHT);

    // grid_mem[cell] = {on_path, parent_dir[2:0], visited, wall}
    logic [5:0] grid_mem [0:NUM_CELLS-1];

    assign read_cell = grid_mem[read_addr];

    logic [CELL_BITS-1:0] queue_mem [0:NUM_CELLS-1];
    logic [CELL_BITS-1:0] q_head, q_tail;
    logic q_empty;

    assign q_empty = (q_head == q_tail);

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

    logic [CELL_BITS-1:0] nid;

    assign start_id = start_row * GRID_WIDTH + start_col;
    assign end_id   = end_row   * GRID_WIDTH + end_col;

    assign busy       = (state != S_IDLE) && (state != S_DONE) && (state != S_NO_PATH);
    assign done        = (state == S_DONE) || (state == S_NO_PATH);
    assign path_found  = (state == S_DONE);

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
                if (wall_write_en) begin
                    grid_mem[wall_write_addr][0] <= wall_write_data;
                end
                if (start) begin
                    state <= S_INIT;
                    init_idx <= '0;
                end
            end else if (step_en) begin
            case (state)

                S_INIT: begin
                    grid_mem[init_idx][5:1] <= 5'd0;
                    if (init_idx == NUM_CELLS - 1) begin
                        state <= S_INIT_LOOP;
                    end else begin
                        init_idx <= init_idx + 1'b1;
                    end
                end

                S_INIT_LOOP: begin
                    grid_mem[start_id][1] <= 1'b1;
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

                // note: parent_dir on a discovered neighbor stores the
                // direction BACK to its parent, so discovering by going
                // UP means the parent is DOWN from the neighbor - got
                // this backwards on the first attempt, caught it by
                // tracing a small maze by hand
                S_NEIGHBOR_UP: begin
                    if (cur_row != 0) begin
                        nid = (cur_row - 1) * GRID_WIDTH + cur_col;
                        if (!grid_mem[nid][0] && !grid_mem[nid][1]) begin
                            grid_mem[nid][1]   <= 1'b1;
                            grid_mem[nid][4:2] <= DIR_DOWN;
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
                            grid_mem[nid][4:2] <= DIR_UP;
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
                            grid_mem[nid][4:2] <= DIR_RIGHT;
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
                            grid_mem[nid][4:2] <= DIR_LEFT;
                            queue_mem[q_tail]  <= nid;
                            q_tail <= q_tail + 1'b1;
                        end
                    end
                    state <= S_DEQUEUE;
                end

                S_BACKTRACK_INIT: begin
                    bt_row <= end_row;
                    bt_col <= end_col;
                    bt_id  <= end_id;
                    state  <= S_BACKTRACK_STEP;
                end

                S_BACKTRACK_STEP: begin
                    grid_mem[bt_id][5] <= 1'b1;
                    if (bt_id == start_id) begin
                        state <= S_DONE;
                    end else begin
                        case (grid_mem[bt_id][4:2])
                            DIR_UP:    begin bt_row <= bt_row - 1'b1; bt_id <= bt_id - GRID_WIDTH; end
                            DIR_DOWN:  begin bt_row <= bt_row + 1'b1; bt_id <= bt_id + GRID_WIDTH; end
                            DIR_LEFT:  begin bt_col <= bt_col - 1'b1; bt_id <= bt_id - 1'b1; end
                            DIR_RIGHT: begin bt_col <= bt_col + 1'b1; bt_id <= bt_id + 1'b1; end
                            default:   state <= S_NO_PATH;
                        endcase
                    end
                end

                S_DONE:    ;
                S_NO_PATH: ;

                default: state <= S_IDLE;
            endcase

            if ((state == S_DONE || state == S_NO_PATH) && start) begin
                state <= S_INIT;
                init_idx <= '0;
            end
            end
        end
    end

endmodule
