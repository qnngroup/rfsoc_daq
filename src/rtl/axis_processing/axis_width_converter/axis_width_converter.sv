// axis_width_converter.sv - Reed Foster
// width converter modules for Axis_If interfaces
// axis_width_converter constructs a single UP -> DOWN resizer
// The UP resizer always accepts samples, so it can run at full rate.
// Therefore, the rate of the input is limited by the output rate.
// If DOWN > UP, then the input must stall occasionally, which is to be
// expected.
module axis_width_converter #(
  parameter int DWIDTH_IN = 192,
  parameter int DWIDTH_OUT = 256
) (
  input wire clk, reset,
  Axis_If.Slave_Full data_in,
  Axis_If.Master_Full data_out
);

// merge both buffer outputs into a word that is AXI_MM_WIDTH bits
// first step down/up the width of the outputs
function automatic int GCD(input int A, input int B);
  if (B == 0) begin
    return A;
  end else begin
    return GCD(B, A % B);
  end
endfunction

localparam int IN_OUT_GCD = GCD(DWIDTH_IN, DWIDTH_OUT);
localparam int DOWN = DWIDTH_IN / IN_OUT_GCD;
localparam int UP = DWIDTH_OUT / IN_OUT_GCD;

Axis_If #(.DWIDTH(DWIDTH_IN*UP)) data ();

axis_upsizer #(
  .DWIDTH(DWIDTH_IN),
  .UP(UP)
) up_i (
  .clk,
  .reset,
  .data_in,
  .data_out(data)
);

axis_downsizer #(
  .DWIDTH(DWIDTH_IN*UP),
  .DOWN(DOWN)
) down_i (
  .clk,
  .reset,
  .data_in(data),
  .data_out
);

endmodule

// axis_downsizer
// converts a stream of wide transactions into multiple narrower transactions
module axis_downsizer #(
  parameter int DWIDTH = 256,
  parameter int DOWN = 2
) (
  input wire clk, reset,
  Axis_If.Slave_Full data_in,
  Axis_If.Master_Full data_out
);

localparam int DWIDTH_OUT = DWIDTH/DOWN;

logic [DOWN-1:0][DWIDTH_OUT-1:0] data_reg;
logic valid_reg, last_reg;
logic [$clog2(DOWN)-1:0] counter;
logic read_final, rollover;

assign read_final = counter == DOWN - 1;
assign rollover = read_final & data_out.ready;

// only accept new samples when we're done breaking up the current sample
assign data_in.ready = rollover | (~data_out.valid);

assign data_out.data = data_reg[counter];
assign data_out.valid = valid_reg;
assign data_out.last = last_reg & read_final;

always_ff @(posedge clk) begin
  if (reset) begin
    counter <= '0;
    data_reg <= '0;
    valid_reg <= '0;
    last_reg <= '0;
  end else begin
    if (data_in.ready) begin
      data_reg <= data_in.data;
      valid_reg <= data_in.valid;
      last_reg <= data_in.last;
    end
    if (data_out.ok) begin
      if (read_final) begin
        counter <= '0;
      end else begin
        counter <= counter + 1'b1;
      end
    end
  end
end

endmodule

// axis_upsizer
// combines subsequent narrow transactions into a single large transaction
module axis_upsizer #(
  parameter int DWIDTH = 16,
  parameter int UP = 8
) (
  input wire clk, reset,
  Axis_If.Slave_Full data_in,
  Axis_If.Master_Full data_out
);

localparam DWIDTH_OUT = DWIDTH*UP;

logic [UP-1:0][DWIDTH-1:0] data_reg;
logic [$clog2(UP)-1:0] counter;
logic write_final;

// finish assembling the large word when its full or if the last value
// from data_in arrives (the MSBs of the final word will be invalid if
// the input burst size is not an integer multiple of UP)
assign write_final = ((counter == UP - 1) | data_in.last) && data_in.ok;

assign data_in.ready = data_out.ready;
assign data_out.data = data_reg;

always_ff @(posedge clk) begin
  if (reset) begin
    counter <= '0;
    data_reg <= '0;
    data_out.valid <= '0;
    data_out.last <= '0;
  end else begin
    if ((!data_out.valid) || data_out.ready) begin
      data_out.valid <= write_final;
      data_out.last <= data_in.last;
    end
    if (data_in.ok) begin
      data_reg[counter] <= data_in.data;
      if (write_final) begin
        // reset counter when we get the last word
        counter <= '0;
      end else begin
        counter <= counter + 1'b1;
      end
    end
  end
end

endmodule
