`default_nettype none
`timescale 1ns / 1ps
import mem_layout_pkg::PS_SEED_BASE_IDS;
import mem_layout_pkg::PS_SEED_VALID_IDS;
import daq_params_pkg::DAC_NUM;
module dac_intf_tb #(MEM_SIZE, DATA_WIDTH, BATCH_SIZE, DMA_DATA_WIDTH, MAX_DAC_BURST_SIZE, BS_WIDTH)
					   (input wire ps_clk,dac_clk,
					   	input wire[DAC_NUM-1:0] dac_intf_rdys, pwl_rdys,
					   	input wire[DAC_NUM-1:0][BATCH_SIZE-1:0][DATA_WIDTH-1:0] dac_batches,
					   	input wire[DAC_NUM-1:0][$clog2(DATA_WIDTH)-1:0] scale_factor_outs,
					   	input wire[DAC_NUM-1:0][$clog2(MAX_DAC_BURST_SIZE):0] dac_bs_outs, halt_counters,
					  	input wire[DAC_NUM-1:0] valid_dac_batches,
					   	output logic ps_rst, dac_rst, 
						output logic[MEM_SIZE-1:0] fresh_bits,
						output logic[MEM_SIZE-1:0][DATA_WIDTH-1:0] read_resps,
						output logic[DAC_NUM-1:0][$clog2(DATA_WIDTH)-1:0] scale_factor_ins,
						output logic[DAC_NUM-1:0][BS_WIDTH-1:0] dac_bs_ins,
						output logic[DAC_NUM-1:0] halts, dac_rdys,
						Axis_IF dmas);					 
	localparam BATCH_WIDTH = BATCH_SIZE*DATA_WIDTH;					   
	int period_len;	
	int expc_wave [$];
	logic ps_clk2,dac_clk2;
	assign ps_clk2 = ps_clk;	
	assign dac_clk2 = dac_clk;	

	task automatic init();
		for (int dac_i = 0; dac_i < DAC_NUM; dac_i++) begin
			{dmas.valid[dac_i], dmas.last[dac_i], dmas.data[dac_i]} <= 0;
			{scale_factor_ins[dac_i], dac_bs_ins[dac_i], halts[dac_i]} <= 0; 
			dac_rdys[dac_i] <= 1; 
		end 
		{read_resps, fresh_bits} <= 0;
		fork 
			begin sim_util_pkg::flash_signal(ps_rst,ps_clk2); end 
			begin sim_util_pkg::flash_signal(dac_rst, dac_clk2); end 
		join_none 
	endtask 

	task automatic notify_dac(input int mem_id, dac_id);
		fresh_bits[mem_id] <= 1; 
		@(posedge ps_clk);
		while (~dac_intf_rdys[dac_id]) @(posedge ps_clk);
		fresh_bits[mem_id] <= 0; 
	endtask 
	
	task automatic send_rand_samples(inout sim_util_pkg::debug debug, input int dac_id);
		logic[BATCH_SIZE-1:0][DATA_WIDTH-1:0] expected;
		for (int i = 0; i < BATCH_SIZE; i++) expected[i] = 16'hBEEF+i;	
		for (int i = PS_SEED_BASE_IDS[dac_id]; i < PS_SEED_VALID_IDS[dac_id]; i++) read_resps[i] <= 16'hBEEF+(i-PS_SEED_BASE_IDS[dac_id]);
		read_resps[PS_SEED_VALID_IDS[dac_id]] <= 1; 
		for (int i = PS_SEED_BASE_IDS[dac_id]; i <= PS_SEED_VALID_IDS[dac_id]; i++) notify_dac(i, dac_id); 
		while (~valid_dac_batches[dac_id]) @(posedge dac_clk);
		for (int i = 0; i < BATCH_SIZE; i++) debug.disp_test_part(i,dac_batches[dac_id][i] == expected[i], $sformatf("Error on random wave sample #%0d: expected %0d got %0d",i, expected[i], dac_batches[dac_id][i]));
		while (~dac_intf_rdys[dac_id]) @(posedge ps_clk);	
	endtask 

	task automatic send_trig_wave(inout sim_util_pkg::debug debug, input int samples_to_check, dac_id);	
		int starting_val = 0;
		logic[BATCH_SIZE-1:0][DATA_WIDTH-1:0] expected = 0;			
		notify_dac(mem_layout_pkg::TRIG_WAVE_IDS[dac_id], dac_id);
		for (int n = 0; n < samples_to_check; n++) begin
			while (~valid_dac_batches[dac_id]) @(posedge dac_clk);
			for (int i = 0; i < BATCH_SIZE; i++) expected[i] = starting_val+i;
			starting_val+=BATCH_SIZE; 
			for (int i = 0; i < BATCH_SIZE; i++) debug.disp_test_part(i,dac_batches[dac_id][i] == expected[i], $sformatf("Error on triangle wave sample #%0d: expected %0d got %0d",n, expected[i], dac_batches[dac_id][i]));
			@(posedge dac_clk);
		end
		while (~dac_intf_rdys[dac_id]) @(posedge ps_clk);
	endtask


	function void clear_wave();
		while (expc_wave.size() > 0) expc_wave.pop_back();
		period_len = 0;
	endfunction

	task automatic halt_dac(input int dac_id);
		sim_util_pkg::flash_signal(halts[dac_id],ps_clk2);
		while (valid_dac_batches[dac_id]) @(posedge dac_clk);
		while (~dac_intf_rdys[dac_id]) @(posedge ps_clk);
	endtask 

	task automatic send_buff(input logic[DMA_DATA_WIDTH-1:0] dma_buff [$], input int dac_id);
		int delay_timer; 
		halt_dac(dac_id); 
		while (~pwl_rdys[dac_id]) @(posedge dac_clk); 
		for (int i = 0; i < dma_buff.size(); i++) begin
			dmas.valid[dac_id] <= 1; 
			dmas.data[dac_id] <= dma_buff[i]; 
			if (i == dma_buff.size()-1) dmas.last[dac_id] <= 1; 
			@(posedge dac_clk); 
			while (~dmas.ready[dac_id]) @(posedge dac_clk); 
			{dmas.valid[dac_id],dmas.last[dac_id]} <= 0; 
			@(posedge dac_clk);
			delay_timer = $urandom_range(0,10);
			repeat(delay_timer) @(posedge dac_clk);				
		end
		{dmas.valid[dac_id],dmas.last[dac_id]} <= 0; 
		@(posedge dac_clk);		
	endtask 

	task automatic send_pwl_wave(input int dac_id, input int wave_num = 0);
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$];
		clear_wave();
		case(wave_num)
			0: begin 
				dma_buff = {64'd281469822763018, 64'd18445055228534718486, 64'd1688850576113697, 64'd2533275506245648, 64'd3096222954225680, 64'd2251798024093729, 64'd4294967316, 64'd3096214006398988, 64'd18445618163065290760, 64'd18442521951393087512, 64'd18444492276230062145, 64'd2533277124591620, 64'd3096216153882634, 64'd18};
				expc_wave = {0,0,0,0,0,0,0,0,0,2,4,6,8,10,10,9,9,8,8,7,7,6,6,5,4,4,3,3,2,2,1,1,0,0,-1,-1,-2,-3,-3,-4,-4,-5,-5,-6,-6,-7,-7,-8,-9,-10,-10,-11,-11,-12,-12,-13,-13,-14,-14,-15,-12,-10,-7,-5,-2,0,3,5,8,10,9,8,7,6,5,4,3,2,1,0,1,1,2,2,2,3,3,4,4,4,5,5,6,6,7,7,7,7,8,8,9,9,10,10,10,10,10,10,10,9,9,9,9,8,8,8,8,8,8,7,7,7,7,7,7,6,6,6,5,4,3,2,1,-1,-2,-3,-4,-5,-6,-5,-4,-2,-1,0};
			end 
			1: begin
				dma_buff = {64'd40598894215174, 64'd7982070370268086274, 64'd8177621661479075842, 64'd3535303137432698888, 64'd16065379059642662914, 64'd10382485990949257228};
				period_len = 1;
			end 
			2: begin
				dma_buff = {64'd11020495618070, 64'd7944887776992821258, 64'd18227168676233084934, 64'd13328439948881362954, 64'd6957498450711674896, 64'd6945113551736406024, 64'd6938820391708131330, 64'd336925547122655254}; 
				period_len = 3;
			end 
			3: begin
				dma_buff = {64'd6377015869473, 64'd6686725923754213378, 64'd7104976324495409170, 64'd16681898263498915852, 64'd17583744088879857686, 64'd790673397242658826, 64'd4128966621031038990, 64'd8802841402061881360, 64'd5122281626180517890};
				period_len = 4;
			end 
			4: begin
				dma_buff = {64'd2695587561498, 64'd2296827156673593350, 64'd595592397434388498, 64'd13938082915964420110, 64'd16240548225457586209, 64'd3056823266283880466, 64'd6017630010310459406, 64'd13675747464624799766, 64'd16736783590192316426};
				period_len = 5;
			end 
			5: begin
				dma_buff = {64'd280290262188161, 64'd13477865125121818644, 64'd12701334612106805250, 64'd16486839595120459786, 64'd18382292088290017302, 64'd4105594009176768522, 64'd4105312534200057985, 64'd4100527459595976734, 64'd4099398041485967362, 64'd3868870035559940193, 64'd11244640325285969930, 64'd10091159390053728278};
				period_len = 15;
			end 
			6: begin
				dma_buff = {64'd280290262188161, 64'd13477865125121818644, 64'd12701334612106805250, 64'd16486839595120459786, 64'd18382292088290017302, 64'd4105594009176768522, 64'd4105312534200057985, 64'd4100527459595976734, 64'd4099400976064118786, 64'd4061120379231470209, 64'd10244844142587871240, 64'd10091159703425253400, 64'd10337731783023788801, 64'd18224097680502947848, 64'd18306006590365040664, 64'd18309947240038990977, 64'd52354350678999064, 64'd56294995832995848, 64'd56294995833009825, 64'd281193502224809992, 64'd281474976710656024};
				period_len = 532;
			end 
			7: begin
				dma_buff = {64'd1053451812961, 64'd3313805954266365972, 64'd4004544477292986380, 64'd3998070552828641345, 64'd3963730605669941278, 64'd3947677753705562114, 64'd3371217001402138640, 64'd17206850494004592656, 64'd696091310110933057, 64'd8440590052494475361, 64'd8207528771778052108, 64'd8177973973351399444};
				period_len = 14;
			end 
		endcase
		send_buff(dma_buff, dac_id);
		if (expc_wave.size() > 0) period_len = expc_wave.size()/BATCH_SIZE;
	endtask  	

	task automatic send_step_pwl_wave(input int dac_id);
		logic[DMA_DATA_WIDTH-1:0] dma_buff [$];
		clear_wave();
		dma_buff = {64'd1407374883553280030, 64'd1407643473628102658, 64'd562949953421312030, 64'd563223267960160258, 64'd28147497671065633};
		expc_wave = {100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,100,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,2000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000};
		send_buff(dma_buff, dac_id);
		period_len = expc_wave.size()/BATCH_SIZE;
	endtask 				   

	task automatic check_pwl_wave(inout sim_util_pkg::debug debug, input int periods_to_check, dac_id);
		int expc_wave_tmp [$];
		int samples_seen,periods_seen,expc_sample;
		periods_seen = 0; 
		notify_dac(mem_layout_pkg::RUN_PWL_IDS[dac_id], dac_id);
		@(posedge ps_clk);
		repeat(periods_to_check) begin
			expc_wave_tmp = expc_wave;
			samples_seen = 0; 
			if (periods_to_check > 1) debug.displayc($sformatf("\nPeriod %0d",periods_seen), .msg_color(sim_util_pkg::BLUE), .msg_verbosity(sim_util_pkg::DEBUG));
			for (int i = 0; i < period_len; i++) begin
				while (~valid_dac_batches[dac_id]) @(posedge dac_clk); 
				for (int j = 0; j < BATCH_SIZE; j++) begin 
					expc_sample = expc_wave_tmp.pop_back();
					debug.disp_test_part(1+samples_seen, $signed(dac_batches[dac_id][j]) == expc_sample,$sformatf("Error on %0dth sample: Expected %0d, Got %0d",samples_seen, expc_sample, $signed(dac_batches[dac_id][j])));
					samples_seen++;
				end 
				@(posedge dac_clk); 
			end
			periods_seen++;
		end
	endtask 

	task automatic send_dac_configs(input int delay_range[2], dac_id);
		@(posedge ps_clk);
		scale_factor_ins[dac_id] <= $urandom_range(1,15);
		if (delay_range[1] > 0) repeat($urandom_range(delay_range[0],delay_range[1])) @(posedge ps_clk); 
		dac_bs_ins[dac_id] <= $urandom_range(1,daq_params_pkg::MAX_DAC_BURST_SIZE);
		@(posedge ps_clk);
		while (~dac_intf_rdys[dac_id] && (dac_bs_ins[dac_id] != dac_bs_outs[dac_id]) || (scale_factor_ins[dac_id] != scale_factor_outs[dac_id])) @(posedge ps_clk); 
		{scale_factor_ins[dac_id], dac_bs_ins[dac_id]} <= 0;
		@(posedge ps_clk) 
		while (~dac_intf_rdys[dac_id] && (dac_bs_ins[dac_id] != dac_bs_outs[dac_id]) || (scale_factor_ins[dac_id] != scale_factor_outs[dac_id])) @(posedge ps_clk);
	endtask 

	task automatic scale_check(inout sim_util_pkg::debug debug, input int scale_factor, dac_id);
		int expc_wave_tmp [$] = expc_wave;
		halt_dac(dac_id);
		@(posedge ps_clk);
		scale_factor_ins[dac_id] <= scale_factor;
		for (int i = 0; i < expc_wave_tmp.size(); i++) expc_wave.push_front(expc_wave.pop_back()>>scale_factor);
		@(posedge ps_clk);
		while (scale_factor_ins[dac_id] != scale_factor_outs[dac_id]) @(posedge ps_clk); 
		check_pwl_wave(debug,1,dac_id);
		expc_wave = expc_wave_tmp;
		scale_factor_ins[dac_id] <= 0; 
		while (scale_factor_ins[dac_id] != scale_factor_outs[dac_id]) @(posedge ps_clk); 
	endtask

	task automatic burst_size_check(inout sim_util_pkg::debug debug, input int bs, test_part, dac_id);
		int batch_cntr;
		halt_dac(dac_id);
		dac_bs_ins[dac_id] <= bs;
		@(posedge ps_clk);
		while (dac_bs_ins[dac_id] != dac_bs_outs[dac_id]) @(posedge ps_clk); 
		notify_dac(mem_layout_pkg::RUN_PWL_IDS[dac_id], dac_id);
		@(posedge dac_clk);
		while (~valid_dac_batches[dac_id]) @(posedge dac_clk);
		while (valid_dac_batches[dac_id]) begin
			batch_cntr++;
			@(posedge dac_clk);
		end 
		debug.disp_test_part(test_part, batch_cntr == halt_counters[dac_id] && halt_counters[dac_id] == bs ,$sformatf("Expected to see %0d batches. TB counted %0d and dac_intf counted %0d",bs, batch_cntr, halt_counters[dac_id]));
	endtask

endmodule 

`default_nettype wire

