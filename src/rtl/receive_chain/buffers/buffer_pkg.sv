// buffer_pkg.sv - Reed Foster
// parameterization of buffer

package buffer_pkg;

  localparam int TSTAMP_BUFFER_DEPTH = 512;
  localparam int SAMPLE_BUFFER_DEPTH = 2048;
  localparam int TSTAMP_WIDTH = 64;

  // derived parameters
  localparam int CLOCK_WIDTH = TSTAMP_WIDTH - $clog2(TSTAMP_BUFFER_DEPTH*rx_pkg::CHANNELS);

endpackage
