// cursor_controller.sv
// Takes decoded key events and maintains: a selection cursor (moved by
// arrow keys, clamped to grid bounds), the current start/end cell
// (updated by pressing '1'/'2' at the cursor's position), and a
// single-cycle `trigger_search` pulse when Enter is pressed.
//
// Defaults on reset: cursor at (0,0), start at (0,0), end at the
// bottom-right corner - the same fixed points used before keyboard
// input existed, so the design still does something sensible with no
// keyboard attached.

`timescale 1ns/1ps

import key_pkg::*;

module cursor_controller #(
    parameter int GRID_WIDTH  = 19,
    parameter int GRID_HEIGHT = 15
) (
    input  logic clk,
    input  logic rst_n,

    input  key_event_t key_event,
    input  logic       key_event_valid,

    output logic [$clog2(GRID_WIDTH)-1:0]  cursor_col,
    output logic [$clog2(GRID_HEIGHT)-1:0] cursor_row,
    output logic [$clog2(GRID_WIDTH)-1:0]  start_col,
    output logic [$clog2(GRID_HEIGHT)-1:0] start_row,
    output logic [$clog2(GRID_WIDTH)-1:0]  end_col,
    output logic [$clog2(GRID_HEIGHT)-1:0] end_row,
    output logic                           trigger_search
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cursor_row <= '0;
            cursor_col <= '0;
            start_row  <= '0;
            start_col  <= '0;
            end_row    <= GRID_HEIGHT - 1;
            end_col    <= GRID_WIDTH - 1;
            trigger_search <= 1'b0;
        end else begin
            trigger_search <= 1'b0; // default: single-cycle pulse only

            if (key_event_valid) begin
                case (key_event)
                    KEY_UP:    if (cursor_row != 0)              cursor_row <= cursor_row - 1'b1;
                    KEY_DOWN:  if (cursor_row != GRID_HEIGHT - 1) cursor_row <= cursor_row + 1'b1;
                    KEY_LEFT:  if (cursor_col != 0)              cursor_col <= cursor_col - 1'b1;
                    KEY_RIGHT: if (cursor_col != GRID_WIDTH - 1)  cursor_col <= cursor_col + 1'b1;
                    KEY_SET_START: begin
                        start_row <= cursor_row;
                        start_col <= cursor_col;
                    end
                    KEY_SET_END: begin
                        end_row <= cursor_row;
                        end_col <= cursor_col;
                    end
                    KEY_CONFIRM: trigger_search <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

endmodule
