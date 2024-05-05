
`default_nettype wire
module BRAM #(
  parameter DATA_WIDTH = 18,                   
  parameter BRAM_DEPTH = 2,
  parameter RAM_PERFORMANCE = "HIGH_PERFORMANCE"                    
) (
  input [$clog2(BRAM_DEPTH)-1:0] addra,
  input [$clog2(BRAM_DEPTH)-1:0] addrb,
  input [DATA_WIDTH-1:0] dina,           
  input [DATA_WIDTH-1:0] dinb,           
  input clka,                           
  input clkb,                           
  input wea,                            
  input web,                            
  input ena,                            
  input enb,                            
  input rsta,                           
  input rstb,                           
  input regcea,                         
  input regceb,                         
  output [DATA_WIDTH-1:0] douta,         
  output [DATA_WIDTH-1:0] doutb          
);

  reg [DATA_WIDTH-1:0] bram [BRAM_DEPTH-1:0];
  reg [DATA_WIDTH-1:0] ram_data_a = {DATA_WIDTH{1'b0}};
  reg [DATA_WIDTH-1:0] ram_data_b = {DATA_WIDTH{1'b0}};

  
  always @(posedge clka)
    if (ena) begin
      if (wea)
        bram[addra] <= dina;
      ram_data_a <= bram[addra];
    end

  always @(posedge clkb)
    if (enb) begin
      if (web)
        bram[addrb] <= dinb;
      ram_data_b <= bram[addrb];
    end

  generate
    if (RAM_PERFORMANCE == "LOW_LATENCY") begin: no_output_register
       assign douta = ram_data_a;
       assign doutb = ram_data_b;
    end else begin: output_register
      reg [DATA_WIDTH-1:0] douta_reg = {DATA_WIDTH{1'b0}};
      reg [DATA_WIDTH-1:0] douta_reg2 = {DATA_WIDTH{1'b0}};
      reg [DATA_WIDTH-1:0] doutb_reg = {DATA_WIDTH{1'b0}};

      always @(posedge clka)
        if (rsta) begin 
          douta_reg <= {DATA_WIDTH{1'b0}};
      	  douta_reg2 <= {DATA_WIDTH{1'b0}};
        end else if (regcea) begin 
          douta_reg <= ram_data_a;
      	  douta_reg2 <= douta_reg; 
      	end 

      always @(posedge clkb)
        if (rstb)
          doutb_reg <= {DATA_WIDTH{1'b0}};
        else if (regceb)
          doutb_reg <= ram_data_b;

      assign douta = douta_reg2;
      assign doutb = doutb_reg;
    end
  endgenerate

endmodule


