`timescale 1ns / 1ps
`default_nettype none
import mem_layout_pkg::*;

module DAC_Interface (input wire ps_clk,dac_clk,ps_rst, dac_rst,
					  input wire[`MEM_SIZE-1:0] fresh_bits,
					  input wire[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] read_resps,
					  input wire[$clog2(`SAMPLE_WIDTH)-1:0] scale_factor_in,
					  input wire halt,
					  input wire dac0_rdy, 
					  output logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] dac_batch,
					  output logic valid_dac_batch,
					  Axis_IF pwl_dma_if);
	localparam CMD_WIDTH = 5;
	localparam RESP_WIDTH = 2;
	localparam SCALE_WIDTH = $clog2(`SAMPLE_WIDTH); 

	enum logic[2:0] {IDLE,SEND_CMD,RUN_PWL_DELAY,RST_DAC, HALT_DAC} dacConfigState;
	logic[`BATCH_SAMPLES-1:0][`SAMPLE_WIDTH-1:0] seed_set, dac_batch_out; 
	logic[SCALE_WIDTH-1:0] scale_factor_out;
	logic[1:0] scale_edge; 
	logic scale_changed;  
	logic state_rdy; 
	logic[(`BATCH_WIDTH+SCALE_WIDTH+CMD_WIDTH)-1:0] ps_cmd_in, ps_cmd_out;
	logic ps_in_valid, ps_out_valid; 
	logic cmd_transfer_rdy, cmd_transfer_done;
	logic[RESP_WIDTH-1:0] resp_in, resp_out;
	logic resp_in_valid, resp_out_valid; 
	logic resp_transfer_rdy, resp_transfer_done;
	logic pwl_rdy;

	assign ps_cmd_in[CMD_WIDTH+:`BATCH_WIDTH] = seed_set;
	assign ps_cmd_in[(`BATCH_WIDTH+CMD_WIDTH)+:SCALE_WIDTH] = scale_factor_in; 
	assign scale_factor_out = ps_cmd_out[(`BATCH_WIDTH+CMD_WIDTH)+:SCALE_WIDTH]; 

	always_comb begin
        for (int i = 0; i < `BATCH_SAMPLES; i++) begin
            dac_batch[i] = dac_batch_out[i] >> scale_factor_out;
        end 
    end

	edetect	scale_ed(.clk(ps_clk), .rst(ps_rst),
	                   .val(scale_factor_in),
	                   .comb_posedge_out(scale_edge)); 

	//cmd: [scale_factor(4),sample_seed(256),rst_cmd(1),halt_cmd(1),run_shift_regs(1),run_trig_wave(1),run_pwl(1)]
	data_handshake #(.DATA_WIDTH(`BATCH_WIDTH+SCALE_WIDTH+CMD_WIDTH))
	    cmd_transfer(.clk_src(ps_clk), .rst_src(ps_rst),
	                 .clk_dst(dac_clk), .rst_dst(dac_rst),
	                 .data_in(ps_cmd_in),
	                 .valid_in(ps_in_valid),
	                 .data_out(ps_cmd_out),
	                 .valid_out(ps_out_valid),
	                 .rdy(cmd_transfer_rdy),
	                 .done(cmd_transfer_done));
	//resp: [null(1),pwl_rdy(1)]
	data_handshake #(.DATA_WIDTH(RESP_WIDTH))
	   resp_transfer(.clk_src(dac_clk), .rst_src(dac_rst),
	                 .clk_dst(ps_clk), .rst_dst(ps_rst),
	                 .data_in(resp_in),
	                 .valid_in(resp_in_valid),
	                 .data_out(resp_out),
	                 .valid_out(resp_out_valid),
	                 .rdy(resp_transfer_rdy),
	                 .done(resp_transfer_done));
	sample_generator #(.CMD_WIDTH(CMD_WIDTH), .RESP_WIDTH(RESP_WIDTH), .SAMPLE_WIDTH(`SAMPLE_WIDTH), .BATCH_WIDTH(`BATCH_WIDTH), .DMA_DATA_WIDTH(`DMA_DATA_WIDTH), .DENSE_BRAM_DEPTH(`DENSE_BRAM_DEPTH), .SPARSE_BRAM_DEPTH(`SPARSE_BRAM_DEPTH))
	sample_gen(.clk(dac_clk),.rst_in(dac_rst),
	           .ps_cmd(ps_cmd_out),.valid_cmd(ps_out_valid),
	           .dac0_rdy(dac0_rdy),
	           .resp(resp_in),.resp_valid(resp_in_valid),
	           .dac_batch(dac_batch_out),.valid_dac_batch(valid_dac_batch),
	           .pwl_dma_if(pwl_dma_if));

	always_ff @(posedge ps_clk) begin
		if (ps_rst || halt) begin 
			if (ps_rst) {pwl_rdy,seed_set,scale_changed} <= 0; 
			state_rdy <= 0;
			{ps_cmd_in[0+:CMD_WIDTH],ps_in_valid} <= 0; 
			dacConfigState <= (ps_rst)? RST_DAC : HALT_DAC;
		end else begin
			if (resp_out_valid) pwl_rdy <= resp_out[0];
			if (scale_edge != 0 && scale_changed == 0) scale_changed <= 1; 
			case (dacConfigState) 
				IDLE: begin
					if (fresh_bits[`RUN_PWL_ID]) begin
						ps_cmd_in[0+:CMD_WIDTH] <= 1; //run_pwl command 
						if (~pwl_rdy) begin
							dacConfigState <= RUN_PWL_DELAY;
						end else ps_in_valid <= 1; 
						state_rdy <= 0;
					end else 
					if (fresh_bits[`PS_SEED_VALID_ID]) begin
						ps_cmd_in[0+:CMD_WIDTH] <= 1<<2; //run_shift_regs command
						for (int i = 0; i < `BATCH_SAMPLES; i++) seed_set[i] <= read_resps[`PS_SEED_BASE_ID+i];
						ps_in_valid <= 1;
						state_rdy <= 0;
					end else 
					if (fresh_bits[`TRIG_WAVE_ID]) begin
						ps_cmd_in[0+:CMD_WIDTH] <= 1<<1; //run_trig_wave command
						ps_in_valid <= 1; 
						state_rdy <= 0;
					end else 
					if (scale_changed) begin
						scale_changed <= 0; 
						ps_in_valid <= 1;
						state_rdy <= 0;
					end
					if (ps_in_valid && cmd_transfer_rdy) begin
						ps_in_valid <= 0;
						dacConfigState <= SEND_CMD;
					end
				end 
				SEND_CMD: begin
					if (cmd_transfer_done) begin
						ps_cmd_in[0+:CMD_WIDTH] <= 0;
						dacConfigState <= IDLE; 
						state_rdy <= 1;
					end
				end 
				RUN_PWL_DELAY: begin
					if (pwl_rdy) begin
						ps_in_valid <= 1; 
						dacConfigState <= IDLE; 
					end
				end 
				RST_DAC: begin
					ps_cmd_in[0+:CMD_WIDTH] <= 1 << 4;
					ps_in_valid <= 1;
					dacConfigState <= IDLE;
				end 
				HALT_DAC: begin
					ps_cmd_in[0+:CMD_WIDTH] <= 1 << 3;
					ps_in_valid <= 1;
					dacConfigState <= IDLE;
				end 
			endcase 
		end
	end	

endmodule 



`default_nettype wire