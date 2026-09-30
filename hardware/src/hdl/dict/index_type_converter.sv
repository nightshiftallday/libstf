`timescale 1ns / 1ps

`include "libstf_macros.svh"

import libstf::*;

/**
    Converts the dictionary IDs of a type to IDs of the dictionary
    base type. For example, if the dictionary base type is int32
    and the incoming ID stream is for the data type int64,
    then this modules expands each 64-bit data ID into two 32-bit
    data ID:

    int64IDs'{i, j} => int32IDs'{2 * i, 2 * i + 1}, int32IDs'{2 * j, 2 * j + 1}
*/
module IndexTypeConverter #(
    parameter type   id_t,
    parameter int    NUM_ELEMENTS,
    parameter type_t BASE_TYPE = INT32_T,
    parameter int    NUM_TYPES = 5,
    parameter type_t TYPES[NUM_TYPES] = '{
        INT32_T, INT64_T,
        FLOAT_T, DOUBLE_T,
        GERMAN_STR_T
    }
) (
    input logic clk,
    input logic rst_n,

    typed_ndata_i.s in,               // #(id_t, NUM_ELEMENTS)
    typed_ndata_i.m out               // #(id_t, NUM_ELEMENTS * FACTOR)
);

localparam int BASE_WIDTH = GET_TYPE_WIDTH(BASE_TYPE);

// We calculate the expansion factors for each individual type
function automatic int max_factor();
    max_factor = 1;
    foreach (TYPES[i])
        if (GET_TYPE_WIDTH(TYPES[i]) / BASE_WIDTH > max_factor)
            max_factor = GET_TYPE_WIDTH(TYPES[i]) / BASE_WIDTH;
endfunction
localparam int MAX_FACTOR = max_factor();

typedef logic [$clog2(MAX_FACTOR + 1) - 1:0] factor_t;
typedef factor_t factors_t[NUM_TYPES];

function automatic factors_t factors_by_type();
    foreach (TYPES[i]) factors_by_type[i] = factor_t'(GET_TYPE_WIDTH(TYPES[i]) / BASE_WIDTH);
endfunction

localparam factors_t FACTOR_BY_TYPE = factors_by_type();

function automatic factors_t factors_log_by_type();
    foreach (TYPES[i]) factors_log_by_type[i] = factor_t'($clog2(GET_TYPE_WIDTH(TYPES[i]) / BASE_WIDTH));
endfunction
localparam factors_t FACTOR_LOG_BY_TYPE = factors_log_by_type();

typedef logic [$clog2(NUM_TYPES)-1:0] type_idx_t;
function automatic type_idx_t type_idx(type_t t);
    for (int i = 0; i < NUM_TYPES; i++)
        if (TYPES[i] == t) return type_idx_t'(i);
    return 'x;
endfunction

typedef logic [$clog2(NUM_ELEMENTS):0] shift_t;
typedef shift_t shifts_t[NUM_TYPES];

function automatic shifts_t shifts_by_type();
    foreach (TYPES[i]) begin
        automatic shift_t shift_amount = NUM_ELEMENTS / FACTOR_BY_TYPE[type_idx(TYPES[i])];
        shifts_by_type[i] = shift_t'(shift_amount <= NUM_ELEMENTS ? shift_amount : 0);
    end
endfunction

localparam shifts_t SHIFT_BY_TYPE = shifts_by_type();

typedef enum logic {
    IDLE,
    PROCESS
} state_t;
state_t state;

typed_ndata_i#(NUM_ELEMENTS, id_t) input_buffer (.*);
`ifndef SYNTHESIS
assign input_buffer.ready = 1;
assign input_buffer.valid = 1;
`else
assign input_buffer.ready = 'x;
assign input_buffer.valid = 'x;
`endif

shift_t shifts_left;
factor_t factor_log;
shift_t shift;
logic current_input_finished;
assign current_input_finished = shifts_left <= shift || input_buffer.keep[shift] == 0;

always_ff @(posedge clk) begin
if (!rst_n) begin
    state <= IDLE;
    shifts_left <= 0;
end else begin
    automatic type_idx_t idx = type_idx(in.typ);
    case (state)
        IDLE: begin
            if (in.valid) begin
                state <= PROCESS;
                input_buffer.data <= in.data;
                input_buffer.typ <= in.typ;
                input_buffer.keep <= in.keep;
                input_buffer.last <= in.last;
                shifts_left <= NUM_ELEMENTS;
                factor_log <= FACTOR_LOG_BY_TYPE[idx];
                shift <= SHIFT_BY_TYPE[idx];
            end
        end
        PROCESS: begin
            if (out.ready) begin
                if (current_input_finished) begin
                    if (in.valid) begin
                        state <= PROCESS;
                        shifts_left <= NUM_ELEMENTS;
                    end else begin
                        state <= IDLE;
                        shifts_left <= NUM_ELEMENTS;
                    end
                    factor_log <= FACTOR_LOG_BY_TYPE[idx];
                    shift <= SHIFT_BY_TYPE[idx];
                    input_buffer.data <= in.data;
                    input_buffer.typ <= in.typ;
                    input_buffer.keep <= in.keep;
                    input_buffer.last <= in.last;
                end else begin
                    for (int i = 0; i < NUM_ELEMENTS; ++i) begin
                        input_buffer.data[i] <= input_buffer.data[i + shift];
                    end
                    input_buffer.keep <= input_buffer.keep >> shift;
                    shifts_left <= shifts_left - shift;
                end
            end
        end
        default: begin
            
        end
    endcase
end
end

always_comb begin
    out.typ = input_buffer.typ;

    for (int i = 0; i < NUM_ELEMENTS; ++i) begin
        automatic shift_t base_idx = i >> factor_log;
        automatic shift_t offset = i & ((1 << factor_log) - 1);

        out.data[i] = (input_buffer.data[base_idx] << factor_log) | offset;
        out.keep[i] = input_buffer.keep[base_idx];
    end

    out.valid = state == PROCESS;
    out.last = input_buffer.last && current_input_finished;

    in.ready = state == IDLE || (current_input_finished && out.ready);
end

endmodule
