import libstf::*;

`include "axi_macros.svh"

`ifndef IN_NUM_ELEMENTS
    `define IN_NUM_ELEMENTS 64
`endif
`ifndef OUT_NUM_ELEMENTS
    `define OUT_NUM_ELEMENTS 64
`endif

parameter IN_NUM_ELEMENTS  = `IN_NUM_ELEMENTS;
parameter OUT_NUM_ELEMENTS  = `OUT_NUM_ELEMENTS;
parameter NUM_ELEMENTS_AXI = 512 / $bits(data8_t);

// -- Tie-off unused interfaces and signals --------------------------------------------------------
always_comb axi_ctrl.tie_off_s();
always_comb notify.tie_off_m();
always_comb sq_rd.tie_off_m();
always_comb sq_wr.tie_off_m();
always_comb cq_rd.tie_off_s();
always_comb cq_wr.tie_off_s();

for (genvar I = 1; I < N_STRM_AXI; I++) begin
    always_comb axis_host_send[I].tie_off_m();
    always_comb axis_host_recv[I].tie_off_s();
end

// -- Fix clock and reset names --------------------------------------------------------------------
logic clk;
logic rst_n;

assign clk   = aclk;
assign rst_n = aresetn;

// -- Interfaces -----------------------------------------------------------------------------------
AXI4S #(.AXI4S_DATA_BITS(512)) axis_host_recv_0(.aclk(clk), .aresetn(rst_n));
ndata_i #(data8_t, NUM_ELEMENTS_AXI) data_from_axi (.*);
ndata_i #(data8_t, IN_NUM_ELEMENTS) data_in (.*);
ndata_i #(data8_t, OUT_NUM_ELEMENTS) data_out (.*);
ndata_i #(data8_t, NUM_ELEMENTS_AXI) data_to_axi(.*);
AXI4S #(.AXI4S_DATA_BITS(512)) axis_host_send_0(.aclk(clk), .aresetn(rst_n));

`AXIS_ASSIGN(axis_host_recv[0], axis_host_recv_0)
`AXIS_ASSIGN(axis_host_send_0, axis_host_send[0])

// -- Input wiring ---------------------------------------------------------------------------------
// Split the 512-bit host stream into IN_NUM_ELEMENTS-wide ndata beats.
AXIToNData #(
    .data_t(data8_t),
    .NUM_ELEMENTS(NUM_ELEMENTS_AXI)
) inst_axi_to_ndata (
    .clk(clk),
    .rst_n(rst_n),

    .in(axis_host_recv_0),
    .out(data_from_axi)
);


// Daisy chain of DWCs
NDataWidthConverter #(
    .data_t(data8_t)
) from_axi_converter (
    .clk(clk),
    .rst_n(rst_n),

    .in(data_from_axi),
    .out(data_in)
);

NDataWidthConverter #(
    .data_t(data8_t)
) intermediate_converter (
    .clk(clk),
    .rst_n(rst_n),

    .in(data_in),
    .out(data_out)
);

NDataWidthConverter #(
    .data_t(data8_t)
) to_axi_converter (
    .clk(clk),
    .rst_n(rst_n),

    .in(data_out),
    .out(data_to_axi)
);

// -- Output wiring --------------------------------------------------------------------------------
// Re-assemble the OUT_NUM_ELEMENTS-wide ndata beats back into the 512-bit host stream.
NDataToAXI #(
    .data_t(data8_t),
    .NUM_ELEMENTS(NUM_ELEMENTS_AXI)
) inst_ndata_to_axi (
    .clk(clk),
    .rst_n(rst_n),

    .in(data_to_axi),
    .out(axis_host_send_0)
);
