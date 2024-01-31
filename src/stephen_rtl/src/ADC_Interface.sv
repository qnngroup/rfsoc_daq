`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module ADC_Interface (input wire clk,rst,
					  input wire[`MEM_SIZE-1:0] fresh_bits,
					  input wire[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] read_resps,
					  Axis_IF.stream_in bufft, 
					  Axis_IF.stream_out buffc, 
					  Axis_IF.stream_out cmc, 
					  Axis_IF.stream_out sdc);

	logic[`SDC_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] sdc_reg; 
	logic[`BUFF_CONFIG_WIDTH-1:0] buff_config_reg; 
	logic[`CHAN_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] channel_mux_reg; 
	logic[`BUFF_SAMPLES-1:0][`WD_DATA_WIDTH-1:0] buff_timestamp_reg; 
	logic buff_timestamp_writereq;
	logic state_rdy;

	enum logic[2:0] {IDLE, SEND_SDC, SEND_BUFFC, SEND_CHAN} adcState;

	assign sdc.last = sdc.valid; 
	assign buffc.last = buffc.valid; 
	assign cmc.last = cmc.valid; 

	assign sdc.data = (sdc.valid)? sdc_reg: 0; 
	assign cmc.data = (cmc.valid)? channel_mux_reg: 0; 
	assign buffc.data = (buffc.valid)? buff_config_reg : 0;

	assign buff_timestamp_reg = bufft.data; 
	assign buff_timestamp_writereq = bufft.valid;  
	assign bufft.ready = 1; 

	always_ff @(posedge clk) begin
		if (rst) begin
			{buffc.valid,cmc.valid,sdc.valid} <= 0;
			{buff_config_reg, sdc_reg, channel_mux_reg} <= 0; 
			state_rdy <= 0; 
			adcState <= IDLE; 
		end else begin
			if (sdc.valid && sdc.ready) sdc.valid <= 0;
			if (buffc.valid && buffc.ready) buffc.valid <= 0;
			if (cmc.valid && cmc.ready) cmc.valid <= 0;
			case(adcState)
				IDLE: begin
					if (fresh_bits[`SDC_VALID_ID]) begin
						if (state_rdy) begin
							state_rdy <= 0;
							adcState <= SEND_SDC; 
						end else state_rdy <= 1; 
					end else 
					if (fresh_bits[`BUFF_CONFIG_ID]) begin
						if (state_rdy) begin
							state_rdy <= 0;
							adcState <= SEND_BUFFC; 
						end else state_rdy <= 1; 
					end else 
					if (fresh_bits[`CHAN_MUX_VALID_ID]) begin
						if (state_rdy) begin
							state_rdy <= 0;
							adcState <= SEND_CHAN; 
						end else state_rdy <= 1; 
					end
				end
				SEND_SDC: begin
					for (int i = 0; i < `SDC_SAMPLES; i++) sdc_reg[i] <= read_resps[`SDC_BASE_ID+i]; 
					sdc.valid <= 1; 
					adcState <= IDLE; 
				end 
				SEND_BUFFC: begin
					buff_config_reg <= read_resps[`BUFF_CONFIG_ID]; 
					buffc.valid <= 1; 
					adcState <= IDLE; 
				end 
				SEND_CHAN: begin
					for (int i = 0; i < `CHAN_SAMPLES; i++) channel_mux_reg[i] <= read_resps[`CHAN_MUX_BASE_ID+i]; 
					cmc.valid <= 1;
					adcState <= IDLE;
				end 
			endcase 
		end
	end

endmodule 

//Known problem: Cannot handle it if the ps writes to any of these registers all at the same moment in time (which should be impossible anyways). There's one ready signal for the entire module, not one for each reg. Easier this way given the assumption.
//That said, it's able to hold onto data for all registers until an external module accepts each one. 

`default_nettype wire