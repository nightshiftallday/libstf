`timescale 1ns / 1ps

`include "libstf_macros.svh"

/**
 * Converts an ndata_i stream to a different width.
 *
 * Note: Supports any power-of-two IN_WIDTH that is <= OUT_WIDTH. OUT_WIDTH must be a multiple of 
 * IN_WIDTH.
 */
module NDataWidthConverter #(
    parameter type data_t
) (
    input logic clk,
    input logic rst_n,

    ndata_i.s in, // #(data_t, IN_WIDTH)
    ndata_i.m out // #(data_t, OUT_WIDTH)
);

localparam IN_WIDTH           = in.NUM_ELEMENTS;
localparam OUT_WIDTH          = out.NUM_ELEMENTS;

// Global constraints
`ASSERT_ELAB((IN_WIDTH & (IN_WIDTH - 1)) == 0)   // IN_WIDTH is power of 2
`ASSERT_ELAB((OUT_WIDTH & (OUT_WIDTH - 1)) == 0) // OUT_WIDTH is power of 2

generate

if (IN_WIDTH == OUT_WIDTH) begin
    `DATA_ASSIGN(in, out)
end else if (IN_WIDTH < OUT_WIDTH) begin
    `ASSERT_ELAB(OUT_WIDTH % IN_WIDTH == 0) // Exact multiple
    
    localparam NUM_SLOTS          = OUT_WIDTH / IN_WIDTH;
    localparam SLOT_COUNTER_WIDTH = $clog2(NUM_SLOTS);

    logic[SLOT_COUNTER_WIDTH - 1:0] slot_idx, n_slot_idx;

    data_t[OUT_WIDTH - 1:0] data,  n_data;
    logic [OUT_WIDTH - 1:0] keep,  n_keep;
    logic                   last,  n_last;
    logic                   valid, n_valid;

    assign in.ready = !out.valid || out.ready;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            slot_idx <= '0;
            valid    <= 1'b0;
        end else begin
            slot_idx <= n_slot_idx;
            data     <= n_data;
            keep     <= n_keep;
            last     <= n_last;
            valid    <= n_valid;
        end
    end

    always_comb begin
        n_slot_idx = slot_idx;
        n_data     = data;
        n_keep     = keep;
        n_last     = last;
        n_valid    = 1'b0;

        if (!out.valid || out.ready) begin
            if (in.valid) begin
                if (in.last) begin
                    n_slot_idx = '0;
                end else begin
                    n_slot_idx = slot_idx + 1; // Wraps around
                end
            end

            if (slot_idx == 0) begin
                n_keep = '0;
            end

            for (int i = 0; i < IN_WIDTH; i++) begin
                n_data[slot_idx * IN_WIDTH + i] = in.data[i];
                n_keep[slot_idx * IN_WIDTH + i] = in.keep[i];
            end

            if (in.valid && (in.last || slot_idx == SLOT_COUNTER_WIDTH'(NUM_SLOTS - 1))) begin
                n_valid = 1'b1;
            end

            n_last = in.last;
        end else begin
            n_valid = valid;
        end
    end

    assign out.data  = data;
    assign out.keep  = keep;
    assign out.last  = last;
    assign out.valid = valid;
end else begin
    `ASSERT_ELAB(IN_WIDTH % OUT_WIDTH == 0) // Exact multiple
    
    localparam NUM_SLOTS          = IN_WIDTH / OUT_WIDTH;

    data_t[IN_WIDTH-1:0]            data;
    logic [IN_WIDTH-1:0]            keep;
    logic [NUM_SLOTS-1:0]  slot_keep_agg;
    logic                           last;
    logic                           valid;

    logic fetch_next;
    assign fetch_next = !slot_keep_agg[0] || !slot_keep_agg[1];
    assign in.ready = fetch_next && out.ready;

    task fetchNext();
        data <= in.data;
        keep <= in.keep;
        last <= in.last;
        for (int i = 0; i < NUM_SLOTS; ++i) begin
            slot_keep_agg[i] <= |(in.keep[i * OUT_WIDTH+:OUT_WIDTH]);
        end
    endtask
    
    task shift();
        for (int i = 0; i < NUM_SLOTS - 1; ++i) begin
            data[i * OUT_WIDTH +: OUT_WIDTH] <= data[(i + 1) * OUT_WIDTH +: OUT_WIDTH];
            keep[i * OUT_WIDTH +: OUT_WIDTH] <= keep[(i + 1) * OUT_WIDTH +: OUT_WIDTH];
            slot_keep_agg[i] <= slot_keep_agg[i + 1];
        end
        slot_keep_agg[NUM_SLOTS - 1] <= '0;
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            slot_keep_agg <= '0;
            last <= 0;
            valid <= 1'b0;
        end else begin
            if (fetch_next && out.ready) begin
                if (in.valid)
                    fetchNext();
                else
                    shift();
            end else if (out.ready) begin
                shift();
            end
        end
    end

    assign out.data  = data[OUT_WIDTH-1:0];
    assign out.keep  = keep[OUT_WIDTH-1:0];
    assign out.last  = last && fetch_next;
    assign out.valid = slot_keep_agg[0];
    
end

endgenerate

endmodule
