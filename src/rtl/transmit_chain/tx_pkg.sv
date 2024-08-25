// tx_pkg.sv - Reed Foster
// parameterization of transmit chain

`timescale 1ns/1ps

package tx_pkg;

  localparam int CHANNELS = 8;
  localparam int SAMPLE_WIDTH = 16;
  localparam int RFDC_CLK_MHZ = 6144;
  localparam int PL_CLK_MHZ = 384;

  // DMA width
  localparam int AXI_MM_WIDTH = 128;

  // derived parameters
  localparam int PARALLEL_SAMPLES = RFDC_CLK_MHZ/PL_CLK_MHZ; // = 16 for 6.144 GS/s @ 384 MHz
  localparam int DATA_WIDTH = PARALLEL_SAMPLES*SAMPLE_WIDTH;

  typedef logic signed [SAMPLE_WIDTH-1:0] sample_t;
  typedef logic [DATA_WIDTH-1:0] batch_t;

endpackage
