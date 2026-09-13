// maze_loader.sv - reads a maze file, writes it into bfs_engine one cell at a time

`timescale 1ns/1ps

module maze_loader #(
    parameter int GRID_WIDTH  = 19,
    parameter int GRID_HEIGHT = 15,
    parameter string MEMFILE  = ""
) (
    input  logic clk,
    input  logic rst_n,

    output logic                                       wall_write_en,
    output logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0]   wall_write_addr,
    output logic                                        wall_write_data,
    output logic                                        load_done,
    output logic                                        bfs_start
);

    localparam int NUM_CELLS = GRID_WIDTH * GRID_HEIGHT;
    localparam int ADDR_BITS = $clog2(NUM_CELLS);

    logic wall_rom [0:NUM_CELLS-1];
    string memfile;

    initial begin
        for (int i = 0; i < NUM_CELLS; i++) wall_rom[i] = 1'b0;
        if ($value$plusargs("MAZEFILE=%s", memfile) && memfile != "") begin
            $readmemb(memfile, wall_rom);
        end else if (MEMFILE != "") begin
            $readmemb(MEMFILE, wall_rom);
        end
    end

    typedef enum logic [1:0] {L_LOAD, L_START_PULSE, L_DONE} lstate_t;
    lstate_t lstate;

    logic [ADDR_BITS-1:0] addr;

    assign wall_write_en   = (lstate == L_LOAD);
    assign wall_write_addr = addr;
    assign wall_write_data = wall_rom[addr];
    assign load_done       = (lstate == L_DONE);
    assign bfs_start       = (lstate == L_START_PULSE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lstate <= L_LOAD;
            addr   <= '0;
        end else begin
            case (lstate)
                L_LOAD: begin
                    if (addr == NUM_CELLS - 1) begin
                        lstate <= L_START_PULSE;
                    end else begin
                        addr <= addr + 1'b1;
                    end
                end
                L_START_PULSE: lstate <= L_DONE;
                L_DONE: ;
                default: lstate <= L_LOAD;
            endcase
        end
    end

endmodule
