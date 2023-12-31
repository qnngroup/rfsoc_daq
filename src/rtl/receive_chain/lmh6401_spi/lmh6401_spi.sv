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
  SPI_Parallel_If.Out spi
);

// use a counter for a clock divider to produce the SPI clock output
localparam int CLK_DIV = int'(AXIS_CLK_FREQ/SPI_CLK_FREQ);
localparam int CLK_COUNTER_BITS = $clog2(CLK_DIV);
localparam int CLK_COUNTER_MAX = int'(CLK_DIV / 2) - 1;

// counter to divide input clock down to SPI clock
logic [CLK_COUNTER_BITS-1:0] clk_counter;

always_ff @(posedge clk) begin
  if (reset) begin
    spi.sck <= 1'b0;
    clk_counter <= '0;
  end else begin
    if (clk_counter == CLK_COUNTER_MAX) begin
      spi.sck <= ~spi.sck;
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

// only accept new data when idling
assign command_in.ready = state == IDLE;

always_ff @(posedge clk) begin
  if (reset) begin
    state <= IDLE;
    bits_sent <= '0;
    spi.cs_n <= '1;
    spi.sdi <= 1'b0;
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
        // update data on every negative edge of SCK
        // when sck == 1 and clk_counter == CLK_COUNTER_MAX, then the counter
        // will overflow and toggle sck, so we can go ahead and update the
        // data
        if (spi.sck == 1'b1 && clk_counter == CLK_COUNTER_MAX) begin
          spi.cs_n[addr] <= 1'b0;
          // shift data
          spi.sdi <= data[15];
          data <= {data[14:0], 1'b1};
          bits_sent <= bits_sent + 1'b1;
          if (bits_sent == 15) begin
            state <= FINISH;
          end
        end
      end
      FINISH: if (spi.sck == 1'b1 && clk_counter == CLK_COUNTER_MAX) begin
        // deassert CS to disable the current slave module
        spi.cs_n[addr] <= 1'b1;
        state <= IDLE;
      end
    endcase
  end
end

endmodule
