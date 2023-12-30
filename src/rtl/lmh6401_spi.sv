// lmh6401_spi.sv - Reed Foster
// Output-only SPI module for controlling the gain setting of multiple LMH6401
// variable-gain amplifiers (VGAs)
module lmh6401_spi #(
  parameter int AXIS_CLK_FREQ = 150_000_000,
  parameter int SPI_CLK_FREQ = 1_000_000,
  parameter int NUM_CHANNELS = 2
) (
  input wire clk, reset,
  Axis_If.Slave_Stream command_in, // {addr + data}
  output logic [NUM_CHANNELS-1:0] cs_n,
  output logic sck,
  output logic sdi
);

// use a counter for a clock divider to produce the SPI clock output
localparam int CLK_DIV = int'(AXIS_CLK_FREQ/SPI_CLK_FREQ);
localparam int CLK_COUNTER_BITS = $clog2(CLK_DIV);
localparam int CLK_COUNTER_MAX = int'(CLK_DIV / 2) - 1;

// update data output on the falling edge of SCK
logic sck_last;

logic [CLK_COUNTER_BITS-1:0] clk_counter;
always_ff @(posedge clk) begin
  sck_last <= sck;
  if (reset) begin
    sck <= 1'b0;
    clk_counter <= '0;
  end else begin
    if (clk_counter == CLK_COUNTER_MAX) begin
      sck <= ~sck;
      clk_counter <= '0;
    end else begin
      clk_counter <= clk_counter + 1;
    end
  end
end

enum {IDLE, SENDING, FINISH} state;
logic [15:0] data;
logic [$clog2(NUM_CHANNELS)-1:0] addr;
logic [3:0] bits_sent;

logic sck_negedge;
assign sck_negedge = (sck_last == 1'b1 && clk_counter == CLK_COUNTER_MAX);

// only accept new data when idling
assign command_in.ready = state == IDLE;

always_ff @(posedge clk) begin
  if (reset) begin
    state <= IDLE;
    bits_sent <= '0;
    cs_n <= '1;
    sdi <= 1'b0;
  end else begin
    unique case (state)
      IDLE: if (command_in.ok) begin 
        state <= SENDING;
        addr <= command_in.data[16+:$clog2(NUM_CHANNELS)];
        // only perform writes, so set MSB of data to 0 so we don't
        // accidentally read data from one of the VGAs
        data <= {1'b0, command_in.data[14:0]};
      end
      SENDING: begin
        if (sck_negedge) begin
          cs_n[addr] <= 1'b0;
          // shift data
          sdi <= data[15];
          data <= {data[14:0], 1'b1};
          bits_sent <= bits_sent + 1'b1;
          if (bits_sent == 15) begin
            state <= FINISH;
          end
        end
      end
      FINISH: if (sck_negedge) begin
        // deassert CS to disable the current slave module
        cs_n[addr] <= 1'b1;
        state <= IDLE;
      end
    endcase
  end
end

endmodule
