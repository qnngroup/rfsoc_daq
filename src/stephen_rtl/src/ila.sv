`timescale 1ns / 1ps
`default_nettype none

module ila #(parameter LINE_WIDTH=256, parameter SAMPLE_WIDTH = 16, parameter MAX_ILA_BURST_SIZE = 100)
		    (input wire clk, rst,
		     input wire[LINE_WIDTH-1:0] ila_line_in,
		     input wire set_trigger,trigger_event,
		     input wire[1:0] save_condition, 
		     input wire sample_pulled, 
		     input wire[$clog2(MAX_ILA_BURST_SIZE):0] ila_burst_size_in, 
		     output logic[SAMPLE_WIDTH-1:0] sample_to_send,
		     output logic valid_sample_out);
		                          
	localparam SAMPLE_NUM = LINE_WIDTH/SAMPLE_WIDTH; 
	int sample_index; 
	logic [$clog2(MAX_ILA_BURST_SIZE)-1:0] ila_addr; 
	logic[LINE_WIDTH-1:0] ila_out;
	logic[LINE_WIDTH-1:0] curr_ila_sample; 
	logic ila_bram_en, ila_bram_we;
	logic[$clog2(MAX_ILA_BURST_SIZE)-1:0] ila_burst_size;
	logic[$clog2((MAX_ILA_BURST_SIZE*LINE_WIDTH)/SAMPLE_WIDTH):0] sample_counter; 
	enum logic[2:0] {IDLE, TRIGGER, SAVE_SAMPLES, BRAM_DELAY, GRAB_SAMPLE, SEND_SAMPLES} ilaState;

	assign ila_burst_size = (ila_burst_size_in < MAX_ILA_BURST_SIZE)? ila_burst_size_in : MAX_ILA_BURST_SIZE;
	assign sample_to_send = curr_ila_sample[SAMPLE_WIDTH*sample_index+:SAMPLE_WIDTH]; 
	always @(*) begin
		if (rst) {ila_bram_en, ila_bram_we} = 0; 
		else begin
			case(ilaState)
				TRIGGER: begin
					if (trigger_event) {ila_bram_en, ila_bram_we} = 3; 
					else {ila_bram_en, ila_bram_we} = 0; 
				end
				SAVE_SAMPLES: begin 
					if (save_condition[1]) {ila_bram_en, ila_bram_we} = (save_condition[0])? 3 : 0; 
					else {ila_bram_en, ila_bram_we} = 3; 
				end
				BRAM_DELAY: {ila_bram_en, ila_bram_we} = 2;
				GRAB_SAMPLE: {ila_bram_en, ila_bram_we} = 0;  
				default: {ila_bram_en, ila_bram_we} = 0; 
			endcase 
		end
	end
	always_ff @(posedge clk) begin 
		if (rst) begin
			ilaState <= IDLE;
			{ila_addr,sample_index,curr_ila_sample,valid_sample_out,sample_counter} <= 0;
		end else begin
			// For counting the samples the ps pulled
			case(ilaState) 
				TRIGGER: begin
					if (trigger_event) sample_counter <= 0; 
				end 

				SEND_SAMPLES: begin
					if (sample_pulled) sample_counter <= sample_counter + 1; 
				end 
			endcase 

			// For the actual ila state machine 
			case(ilaState) 
				IDLE: begin
					if (set_trigger) ilaState <= TRIGGER;
				end 

				TRIGGER: begin
					if (trigger_event) begin
						ilaState <= SAVE_SAMPLES;
						ila_addr <= 1;
					end
				end 
				SAVE_SAMPLES: begin
					if (save_condition[1] && save_condition[0] || ~save_condition[1]) begin  			//save_condition = {True/False, condition}, If False, we just save everything after the trigger, if true we save on the condition 
						if (ila_addr == ila_burst_size-1) begin
							ilaState <= BRAM_DELAY;
							ila_addr <= 0;
							sample_index <= 0;
						end else 
						ila_addr <= ila_addr + 1;
					end 
				end 

				BRAM_DELAY: ilaState <= GRAB_SAMPLE; 
				GRAB_SAMPLE: begin
					if (ila_addr == ila_burst_size) begin
						ila_addr <= 0; 
						ilaState <= IDLE;
					end else begin
						ila_addr <= ila_addr + 1; 
						curr_ila_sample <= ila_out; 
						ilaState <= SEND_SAMPLES;
						valid_sample_out <= 1;  
					end
				end 

				SEND_SAMPLES: begin
					if (sample_pulled) begin 						
						if (sample_index == SAMPLE_NUM - 1) begin 
							ilaState <= BRAM_DELAY; 
							sample_index <= 0; 
							valid_sample_out <= 0;
						end else begin
							sample_index <= sample_index + 1; 
							valid_sample_out <= 1; 
						end
					end 					
				end 
			endcase
		end
	end  
	
	ILA_BRAM ila_bram(.clka(clk),       
			  		  .addra(ila_addr),     
			  		  .dina(ila_line_in),       
			  		  .wea(ila_bram_we),        
			  		  .ena(ila_bram_en),         
			  		  .douta(ila_out));

endmodule 

`default_nettype wire