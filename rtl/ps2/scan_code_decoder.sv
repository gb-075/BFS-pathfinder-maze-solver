// scan_code_decoder.sv
// Sits on top of ps2_receiver and interprets the raw byte stream into
// discrete "key pressed" events for the specific keys this project
// cares about: arrow keys (to move a selection cursor), '1'/'2' (to
// set start/end points), and Enter (to trigger a search).
//
// PS/2 Set 2 scan codes send a "make" code on key press, and a "break"
// sequence (0xF0 followed by the same make code) on release. Extended
// keys (like the arrows) are additionally prefixed with 0xE0. This
// decoder tracks that prefix state and only fires an event on an
// actual key PRESS (make code), ignoring releases entirely - a
// released key isn't a meaningful event for this project.
//
// Recognized Set 2 make codes:
//   '1' = 0x16          '2' = 0x1E          Enter = 0x5A
//   Up (extended)   = 0xE0 0x75
//   Down (extended) = 0xE0 0x72
//   Left (extended) = 0xE0 0x6B
//   Right (extended)= 0xE0 0x74

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
    input  logic       data_valid, // pulses once per received byte (from ps2_receiver)

    output key_event_t key_event,  // pulses one cycle when a recognized key is pressed
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
            key_event_valid <= 1'b0; // default: only pulse on an actual recognized press

            if (data_valid) begin
                if (scan_code == CODE_EXT) begin
                    extended_pending <= 1'b1;
                end else if (scan_code == CODE_BREAK) begin
                    break_pending <= 1'b1;
                end else begin
                    // This byte is an actual key code (make code), possibly
                    // preceded by extended/break prefixes already latched.
                    if (break_pending) begin
                        // It's a release - consume the prefix, fire nothing.
                        break_pending <= 1'b0;
                        extended_pending <= 1'b0;
                    end else begin
                        // It's a press - decode it if recognized.
                        if (extended_pending) begin
                            case (scan_code)
                                CODE_UP:    begin key_event <= KEY_UP;    key_event_valid <= 1'b1; end
                                CODE_DOWN:  begin key_event <= KEY_DOWN;  key_event_valid <= 1'b1; end
                                CODE_LEFT:  begin key_event <= KEY_LEFT;  key_event_valid <= 1'b1; end
                                CODE_RIGHT: begin key_event <= KEY_RIGHT; key_event_valid <= 1'b1; end
                                default: ; // unrecognized extended key - ignore
                            endcase
                            extended_pending <= 1'b0;
                        end else begin
                            case (scan_code)
                                CODE_1:     begin key_event <= KEY_SET_START; key_event_valid <= 1'b1; end
                                CODE_2:     begin key_event <= KEY_SET_END;   key_event_valid <= 1'b1; end
                                CODE_ENTER: begin key_event <= KEY_CONFIRM;   key_event_valid <= 1'b1; end
                                default: ; // unrecognized key - ignore
                            endcase
                        end
                    end
                end
            end
        end
    end

endmodule
