`timescale 1ns / 1ps

module DataCompactorLevel #(
    parameter ID,
    parameter type data_t,
    parameter NUM_ELEMENTS,
    parameter REGISTER = 0,
    parameter COUNTER_WIDTH = $clog2(NUM_ELEMENTS)
) (
    input logic clk,
    input logic rst_n,

    ndata_i.s in, // #(data_t, NUM_ELEMENTS)
    input logic[COUNTER_WIDTH - 1:0] counter_in,

    ndata_i.m out, // #(data_t, NUM_ELEMENTS)
    output logic[COUNTER_WIDTH - 1:0] counter_out
);

data_t[NUM_ELEMENTS - 1:0] next_data;
logic[NUM_ELEMENTS - 1:0]  next_keep;
logic[COUNTER_WIDTH - 1:0] next_counter;

always_comb begin
    next_data = in.data;
    next_keep = in.keep;

    for (int i = 0; i < ID; i++) begin
        if (in.keep[ID] && i == counter_in) begin
            next_data[i] = in.data[ID];
            next_keep[i] = 1'b1;
        end
    end

    if (counter_in < ID || ~in.keep[ID]) begin
        next_keep[ID] = 1'b0;
    end
    
    if (in.keep[ID]) begin
        next_counter = counter_in + 1;
    end else begin
        next_counter = counter_in;
    end
end

generate if (REGISTER) begin
    typedef struct packed {
        data_t[NUM_ELEMENTS - 1:0] data;
        logic[NUM_ELEMENTS - 1:0]  keep;
        logic                      last;
        logic[COUNTER_WIDTH - 1:0] counter;
    } stage_t;

    ready_valid_i #(stage_t) skid_in(clk, rst_n), skid_out(clk, rst_n);

    assign skid_in.data.data    = next_data;
    assign skid_in.data.keep    = next_keep;
    assign skid_in.data.last    = in.last;
    assign skid_in.data.counter = next_counter;
    assign skid_in.valid        = in.valid;
    assign in.ready             = skid_in.ready;

    SkidBuffer #(
        .data_t(stage_t)
    ) inst_skid_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .in(skid_in),
        .out(skid_out)
    );

    assign out.data       = skid_out.data.data;
    assign out.keep       = skid_out.data.keep;
    assign out.last       = skid_out.data.last;
    assign out.valid      = skid_out.valid;
    assign counter_out    = skid_out.data.counter;
    assign skid_out.ready = out.ready;
end else begin
    assign out.data  = next_data;
    assign out.keep  = next_keep;
    assign out.last  = in.last;
    assign out.valid = in.valid;

    assign counter_out = next_counter;

    assign in.ready = out.ready;
end endgenerate

endmodule
