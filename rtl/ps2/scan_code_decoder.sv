// scan_code_decoder.sv - turns raw PS/2 bytes into key press events.
// Set 2 scan codes: press sends a code, release sends 0xF0+code,
// extended keys (arrows) are prefixed with 0xE0

`timescale 1ns/1ps

package key_pkg;
    typedef enum logic [2:0] {
        KEY_NONE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SET_START, KEY_SET_END, KEY_CONFIRM
    } key_event_t;
endpackage

import key_pkg::*;

module scan_code_decoder (
    input  logic clk,
    input  logic rst_n,

    input  logic [7:0] scan_code,
    input  logic       data_valid,

    output key_event_t key_event,
    output logic       key_event_valid
);

    localparam logic [7:0] CODE_1       = 8'h16;
    localparam logic [7:0] CODE_2       = 8'h1E;
    localparam logic [7:0] CODE_ENTER   = 8'h5A;
    localparam logic [7:0] CODE_UP      = 8'h75;
    localparam logic [7:0] CODE_DOWN    = 8'h72;
    localparam logic [7:0] CODE_LEFT    = 8'h6B;
    localparam logic [7:0] CODE_RIGHT   = 8'h74;
    localparam logic [7:0] CODE_EXT     = 8'hE0;
    localparam logic [7:0] CODE_BREAK   = 8'hF0;

    logic extended_pending, break_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            extended_pending <= 1'b0;
            break_pending    <= 1'b0;
            key_event        <= KEY_NONE;
            key_event_valid  <= 1'b0;
        end else begin
            key_event_valid <= 1'b0;

            if (data_valid) begin
                if (scan_code == CODE_EXT) begin
                    extended_pending <= 1'b1;
                end else if (scan_code == CODE_BREAK) begin
                    break_pending <= 1'b1;
                end else begin
                    if (break_pending) begin
                        break_pending <= 1'b0;
                        extended_pending <= 1'b0;
                    end else begin
                        if (extended_pending) begin
                            case (scan_code)
                                CODE_UP:    begin key_event <= KEY_UP;    key_event_valid <= 1'b1; end
                                CODE_DOWN:  begin key_event <= KEY_DOWN;  key_event_valid <= 1'b1; end
                                CODE_LEFT:  begin key_event <= KEY_LEFT;  key_event_valid <= 1'b1; end
                                CODE_RIGHT: begin key_event <= KEY_RIGHT; key_event_valid <= 1'b1; end
                                default: ;
                            endcase
                            extended_pending <= 1'b0;
                        end else begin
                            case (scan_code)
                                CODE_1:     begin key_event <= KEY_SET_START; key_event_valid <= 1'b1; end
                                CODE_2:     begin key_event <= KEY_SET_END;   key_event_valid <= 1'b1; end
                                CODE_ENTER: begin key_event <= KEY_CONFIRM;   key_event_valid <= 1'b1; end
                                default: ;
                            endcase
                        end
                    end
                end
            end
        end
    end

endmodule
