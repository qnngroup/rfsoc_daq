`timescale 1ns / 1ps
`default_nettype none

import daq_params_pkg::DAC_NUM;
module DAC_Interface #(parameter DATAW, SAMPLEW, BS_WIDTH, BATCH_WIDTH, BATCH_SIZE, PWL_PERIOD_WIDTH, PWL_PERIOD_SIZE)
					  (input wire ps_clk,dac_clk,ps_rst, dac_rst,
					   input wire[(mem_layout_pkg::MEM_SIZE)-1:0] fresh_bits,
					   input wire[(mem_layout_pkg::MEM_SIZE)-1:0][DATAW-1:0] read_resps,
					   input wire[DAC_NUM-1:0][$clog2(SAMPLEW)-1:0] scale_factor_ins,
					   input wire[DAC_NUM-1:0][BS_WIDTH-1:0] dac_bs_ins,
					   input wire[DAC_NUM-1:0] halts,
					   input wire[DAC_NUM-1:0] dac_rdys, 
					   output logic[DAC_NUM-1:0][BATCH_SIZE-1:0][SAMPLEW-1:0] dac_batches,
					   output logic[DAC_NUM-1:0] valid_dac_batches,
					   output logic[DAC_NUM-1:0] save_pwl_wave_periods, 
					   output logic[DAC_NUM-1:0][PWL_PERIOD_SIZE-1:0][DATAW-1:0] pwl_wave_periods,
					   Axis_IF pwl_dmas_if);
	localparam CMD_WIDTH = 4;
	localparam RESP_WIDTH = 2*DATAW + 1;
	localparam SCALE_WIDTH = $clog2(SAMPLEW); 
	localparam FULL_CMD_WIDTH = BS_WIDTH+SCALE_WIDTH+BATCH_WIDTH+CMD_WIDTH;
	
	logic[DAC_NUM-1:0][SCALE_WIDTH-1:0] scale_factor_outs;
	logic[DAC_NUM-1:0][BS_WIDTH-1:0] dac_bs_outs; 
	logic[DAC_NUM-1:0][BS_WIDTH-1:0] halt_counters;
	logic[DAC_NUM-1:0] state_rdys, ps_cmd_transfer_done, ps_halt_cmds, pwl_rdys; 

	logic[BATCH_WIDTH-1:0] dac_batches0,dac_batches1,dac_batches2,dac_batches3,dac_batches4,dac_batches5,dac_batches6,dac_batches7;
	assign dac_batches0 = dac_batches[0];
	assign dac_batches1 = dac_batches[1];
	assign dac_batches2 = dac_batches[2];
	assign dac_batches3 = dac_batches[3];
	assign dac_batches4 = dac_batches[4];
	assign dac_batches5 = dac_batches[5];
	assign dac_batches6 = dac_batches[6];
	assign dac_batches7 = dac_batches[7];

	generate
		for (genvar dac_i = 0; dac_i < DAC_NUM; dac_i++) begin: DACS

			enum logic[1:0] {IDLE,SEND_CMD,RUN_PWL_DELAY,HALT_DAC} dacConfigState;
			logic[BATCH_SIZE-1:0][SAMPLEW-1:0] seed_set, dac_batch_out; 
			logic[1:0] scale_edge, dac_bs_edge; 
			logic scale_changed, dac_bs_changed; 
			logic[FULL_CMD_WIDTH-1:0] ps_cmd_in, ps_cmd_out;
			logic ps_cmd_in_valid, ps_cmd_out_valid; 
			logic ps_cmd_transfer_rdy;
			logic[RESP_WIDTH-1:0] dac_cmd_in, dac_cmd_out;
			logic dac_cmd_in_valid, dac_cmd_out_valid; 
			logic dac_cmd_transfer_rdy, dac_cmd_transfer_done;
			
			logic[1:0] wave_period_edge; 
			Axis_IF #(daq_params_pkg::DMA_DATA_WIDTH) pwl_dma_if();


			assign pwl_dma_if.data = pwl_dmas_if.data[dac_i];
		    assign pwl_dma_if.valid = pwl_dmas_if.valid[dac_i];
		    assign pwl_dma_if.last = pwl_dmas_if.last[dac_i];
		    assign pwl_dmas_if.ready[dac_i] = pwl_dma_if.ready; 

			assign ps_cmd_in[CMD_WIDTH+:BATCH_WIDTH] = seed_set;
			assign ps_cmd_in[(CMD_WIDTH+BATCH_WIDTH)+:SCALE_WIDTH] = scale_factor_ins[dac_i];
			assign ps_cmd_in[(CMD_WIDTH+BATCH_WIDTH+SCALE_WIDTH)+:BS_WIDTH] = dac_bs_ins[dac_i];

			assign scale_factor_outs[dac_i] = ps_cmd_out[(CMD_WIDTH+BATCH_WIDTH)+:SCALE_WIDTH]; 
			assign dac_bs_outs[dac_i] = ps_cmd_out[(CMD_WIDTH+BATCH_WIDTH+SCALE_WIDTH)+:BS_WIDTH]; 
			assign save_pwl_wave_periods[dac_i] = wave_period_edge != 0;
			assign halt_counters[dac_i] = sample_gen.halt_counter;
			assign ps_halt_cmds[dac_i] = sample_gen.ps_halt_cmd;

			always_comb begin
		        for (int i = 0; i < BATCH_SIZE; i++) begin
		            dac_batches[dac_i][i] = dac_batch_out[i] >> scale_factor_outs[dac_i];
		        end 
		    end

			edetect	#(.DATA_WIDTH(SCALE_WIDTH))
			scale_ed(.clk(ps_clk), .rst(ps_rst),
					 .val(scale_factor_ins[dac_i]),
					 .comb_edge_out(scale_edge)); 
			edetect	#(.DATA_WIDTH(BS_WIDTH))
			dac_bs_ed(.clk(ps_clk), .rst(ps_rst),
					 .val(dac_bs_ins[dac_i]),
					 .comb_edge_out(dac_bs_edge)); 
			edetect #(.DATA_WIDTH(PWL_PERIOD_WIDTH))
			wave_period_ed(.clk(ps_clk), .rst(ps_rst),
			               .val(pwl_wave_periods[dac_i]),
			               .comb_edge_out(wave_period_edge));

			//cmd: [dac_burst_size(16),scale_factor(4),sample_seed(256),ps_halt_cmd(1),run_shift_regs(1),run_trig_wave(1),run_pwl(1)]
			data_handshake #(.DATA_WIDTH(FULL_CMD_WIDTH))
			    ps_cmd_transfer(.clk_src(ps_clk), .rst_src(ps_rst),
			                 	.clk_dst(dac_clk), .rst_dst(dac_rst),
			                 	.data_in(ps_cmd_in),
			                 	.valid_in(ps_cmd_in_valid),
			                 	.data_out(ps_cmd_out),
			                 	.valid_out(ps_cmd_out_valid),
			                 	.rdy(ps_cmd_transfer_rdy),
			                 	.done(ps_cmd_transfer_done[dac_i]));
			//resp: [pwl_wave_period(32), pwl_ready(1)]
			data_handshake #(.DATA_WIDTH(RESP_WIDTH))
			dac_cmd_transfer(.clk_src(dac_clk), .rst_src(dac_rst),
			             	.clk_dst(ps_clk), .rst_dst(ps_rst),
			             	.data_in(dac_cmd_in),
			             	.valid_in(dac_cmd_in_valid),
			             	.data_out(dac_cmd_out),
			             	.valid_out(dac_cmd_out_valid),
			             	.rdy(dac_cmd_transfer_rdy),
			             	.done(dac_cmd_transfer_done));
			sample_generator #(.FULL_CMD_WIDTH(FULL_CMD_WIDTH), .CMD_WIDTH(CMD_WIDTH), .RESP_WIDTH(RESP_WIDTH), .SAMPLE_WIDTH(SAMPLEW), .BATCH_WIDTH(BATCH_WIDTH), .BATCH_SIZE(BATCH_SIZE), .DMA_DATA_WIDTH(daq_params_pkg::DMA_DATA_WIDTH), .DENSE_BRAM_DEPTH(daq_params_pkg::DENSE_BRAM_DEPTH), .SPARSE_BRAM_DEPTH(daq_params_pkg::SPARSE_BRAM_DEPTH), .BS_WIDTH(BS_WIDTH), .PWL_PERIOD_WIDTH(PWL_PERIOD_WIDTH))
			sample_gen(.clk(dac_clk),.rst(dac_rst),
			           .ps_cmd(ps_cmd_out),.valid_ps_cmd(ps_cmd_out_valid),
			           .dac_rdy(dac_rdys[dac_i]), .dac_bs(dac_bs_outs[dac_i]),
			           .dac_cmd(dac_cmd_in),.valid_dac_cmd(dac_cmd_in_valid),
			           .transfer_rdy(dac_cmd_transfer_rdy), .transfer_done(dac_cmd_transfer_done),
			           .dac_batch(dac_batch_out),.valid_dac_batch(valid_dac_batches[dac_i]),
			           .pwl_dma_if(pwl_dma_if));

			// State machine for transmitting ps commands
			always_ff @(posedge ps_clk) begin
				if (ps_rst || (halts[dac_i] != 0)) begin 
					{ps_cmd_in[0+:CMD_WIDTH],ps_cmd_in_valid} <= 0; 
					if (ps_rst) begin
						{pwl_rdys[dac_i],seed_set,scale_changed,dac_bs_changed} <= 0;
						state_rdys[dac_i] <= 1;
						dacConfigState <= IDLE;
					end else begin
						state_rdys[dac_i] <= 0;
						dacConfigState <= HALT_DAC;
					end
				end else begin
					if (dac_cmd_out_valid) begin
						pwl_rdys[dac_i] <= dac_cmd_out[0];
						pwl_wave_periods[dac_i] <= dac_cmd_out[1+:PWL_PERIOD_WIDTH];
					end 
					if (scale_edge != 0 && scale_changed == 0) scale_changed <= 1;
					if (dac_bs_edge != 0 && dac_bs_changed == 0) dac_bs_changed <= 1; 
					case (dacConfigState) 
						IDLE: begin
							if (fresh_bits[mem_layout_pkg::RUN_PWL_IDS[dac_i]]) begin
								ps_cmd_in[0+:CMD_WIDTH] <= 1; //run_pwl command 
								if (~pwl_rdys[dac_i]) begin
									dacConfigState <= RUN_PWL_DELAY;
								end else ps_cmd_in_valid <= 1; 
								state_rdys[dac_i] <= 0;
							end else 
							if (fresh_bits[mem_layout_pkg::PS_SEED_VALID_IDS[dac_i]]) begin
								ps_cmd_in[0+:CMD_WIDTH] <= 1<<2; //run_shift_regs command
								for (int i = 0; i < BATCH_SIZE; i++) seed_set[i] <= read_resps[(mem_layout_pkg::PS_SEED_BASE_IDS[dac_i])+i];
								ps_cmd_in_valid <= 1;
								state_rdys[dac_i] <= 0;
							end else 
							if (fresh_bits[mem_layout_pkg::TRIG_WAVE_IDS[dac_i]]) begin
								ps_cmd_in[0+:CMD_WIDTH] <= 1<<1; //run_trig_wave command
								ps_cmd_in_valid <= 1; 
								state_rdys[dac_i] <= 0;
							end else 
							if (scale_changed) begin
								scale_changed <= 0; 
								ps_cmd_in_valid <= 1;
								state_rdys[dac_i] <= 0;
							end else 
							if (dac_bs_changed) begin
								dac_bs_changed <= 0;
								ps_cmd_in_valid <= 1;
								state_rdys[dac_i] <= 0;
							end

							if (ps_cmd_in_valid && ps_cmd_transfer_rdy) begin
								ps_cmd_in_valid <= 0;
								ps_cmd_in[3] <= 0; //clear halt command to avoid repeat halts. 
								dacConfigState <= SEND_CMD;
							end
						end 
						SEND_CMD: begin
							if (ps_cmd_transfer_done[dac_i]) begin
								dacConfigState <= IDLE; 
								state_rdys[dac_i] <= 1;
							end
						end 
						RUN_PWL_DELAY: begin
							if (pwl_rdys[dac_i]) begin
								ps_cmd_in_valid <= 1; 
								dacConfigState <= IDLE; 
							end
						end 
						
						HALT_DAC: begin
							ps_cmd_in[0+:CMD_WIDTH] <= 1 << 3;
							ps_cmd_in_valid <= 1;
							dacConfigState <= IDLE;
						end 
					endcase 
				end
			end	
		end
	endgenerate	

endmodule 



`default_nettype wire