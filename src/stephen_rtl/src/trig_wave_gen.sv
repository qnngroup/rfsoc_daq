`timescale 1ns / 1ps
`default_nettype none

module trig_wave_gen #(parameter SAMPLE_WIDTH, BATCH_WIDTH, BATCH_SIZE) 
			 		  (input wire clk,rst,
			 		   input wire run,
			 		   output logic[BATCH_WIDTH-1:0] batch_out,batch_out_comb);
	logic[SAMPLE_WIDTH-1:0] batch_start, max_val; 
	logic[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] batch, batch_comb; 
	enum logic {RISE,FALL} trigGenState;

	assign batch_out = (run)? batch : 0;
	assign batch_out_comb = (run)? batch_comb : 0;
	assign max_val = -1 & ~(1'b1 << SAMPLE_WIDTH-1); 
	logic signed[BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] nxt_batch; 
	logic signed[SAMPLE_WIDTH-1:0] nxt_batch_start; 

	always_comb begin
		if (rst) {batch_comb, nxt_batch, nxt_batch_start} = 0;
		else begin
			case(trigGenState)
				RISE: begin
	    			nxt_batch_start = $signed(batch_start) + $signed(BATCH_SIZE);
					for (int i = 0; i < BATCH_SIZE; i++) begin 
						nxt_batch[i] = $signed(batch_start) + $signed(i);
		    			if (nxt_batch[i] < 0) batch_comb[i] = max_val; 
		    			else batch_comb[i] = nxt_batch[i];
		    		end 
				end 

				FALL: begin
					nxt_batch_start = $signed(batch_start) - $signed(BATCH_SIZE);
					for (int i = 0; i < BATCH_SIZE; i++) begin 
						nxt_batch[i] = $signed(batch_start) - $signed(i);
		    			if (nxt_batch[i] < 0) batch_comb[i] = 0; 
		    			else batch_comb[i] = nxt_batch[i];
		    		end 
				end 
				default: {batch_comb, nxt_batch, nxt_batch_start} = 0;
			endcase
		end
	end 
	always_ff @(posedge clk) begin
	    if (rst) begin 
	    	{batch, batch_start} <= 0;
	    	trigGenState <= RISE; 
	    end 
	    else begin
	    	if (run) begin 
	    		case(trigGenState)
	    			RISE: begin 
	    				if (nxt_batch_start < 0) begin
	    					batch_start <= max_val; 
	    					trigGenState <= FALL;	 
	    				end
	    				else batch_start <= batch_start + BATCH_SIZE; 
	    				batch <= batch_comb;
			    	end 

			    	FALL: begin 
			    		if (nxt_batch_start < 0) begin
	    					batch_start <= 0; 
	    					trigGenState <= RISE;	 
	    				end
	    				else batch_start <= batch_start - BATCH_SIZE; 
	    				batch <= batch_comb; 
			    	end 
			    endcase
			end 
		end 
    end
endmodule 

`default_nettype wire
