`default_nettype none
`timescale 1ns / 1ps
// import mem_layout_pkg::*;
`include "mem_layout.svh"

module slave_test();
	localparam TIMEOUT = 1000;
	localparam TEST_NUM = 9*2 + 3; 
	localparam int CLK_RATE_MHZ = 150;

    sim_util_pkg::debug debug = new(sim_util_pkg::DEBUG,TEST_NUM,"SLAVE"); 

    logic clk, rst; 
    logic clr_rd_out; 
    int curr_err, total_errors; 
    bit halt_osc = 0;
    logic[`MEM_SIZE-1:0] rtl_write_reqs, rtl_read_reqs, fresh_bits, rtl_rdy; 
    logic[`MEM_SIZE-1:0][`WD_DATA_WIDTH-1:0] rtl_wd_in, rtl_rd_out;
    logic[`WD_DATA_WIDTH-1:0] rdata, wdata;
    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   wa_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) wd_if (); 
    Recieve_Transmit_IF #(`A_BUS_WIDTH, `A_DATA_WIDTH)   ra_if (); 
    Recieve_Transmit_IF #(`WD_BUS_WIDTH, `WD_DATA_WIDTH) rd_if (); 
    Recieve_Transmit_IF #(2,2) wr_if (); 
    Recieve_Transmit_IF #(2,2) rr_if ();

    slave_tb #(.MEM_SIZE(`MEM_SIZE), .DATA_WIDTH(`WD_DATA_WIDTH), .ADDR_WIDTH(`A_DATA_WIDTH))
    tb_i(.clk(clk),
         .wa_if(wa_if), .wd_if(wd_if),
         .ra_if(ra_if), .rd_if(rd_if),
         .wr_if(wr_if), .rr_if(rr_if),
         .clr_rd_out(clr_rd_out),
         .rtl_write_reqs(rtl_write_reqs), .rtl_read_reqs(rtl_read_reqs), .rtl_rdy(rtl_rdy),
         .rtl_wd_in(rtl_wd_in),           .rtl_rd_out(rtl_rd_out), .fresh_bits(fresh_bits));

    axi_slave #(.A_BUS_WIDTH(`A_BUS_WIDTH), .A_DATA_WIDTH(`A_DATA_WIDTH), .WD_BUS_WIDTH(`WD_BUS_WIDTH), .WD_DATA_WIDTH(`WD_DATA_WIDTH))
    dut_i(.clk(clk), .rst(rst),
          .waddr_if(wa_if), .wdata_if(wd_if),
          .raddr_if(ra_if), .rdata_if(rd_if),
          .wresp_if(wr_if), .rresp_if(rr_if),
          .rtl_write_reqs(rtl_write_reqs), .rtl_read_reqs(rtl_read_reqs),
          .clr_rd_out(clr_rd_out),         .rtl_rdy(rtl_rdy),
          .rtl_wd_in(rtl_wd_in),           .rtl_rd_out(rtl_rd_out), .fresh_bits(fresh_bits));

        axi_receive #(.BUS_WIDTH(2), .DATA_WIDTH(2))
        ps_wresp_recieve(.clk(clk), .rst(rst),
                         .bus(wr_if.receive_bus),
                         .is_addr(1'b0)); 
        axi_receive #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
        ps_rdata_recieve(.clk(clk), .rst(rst),
                         .bus(rd_if.receive_bus),
                         .is_addr(1'b0));
        axi_transmit #(.BUS_WIDTH(`WD_BUS_WIDTH), .DATA_WIDTH(`WD_DATA_WIDTH))
        ps_wdata_transmit(.clk(clk), .rst(rst),
                          .bus(wd_if.transmit_bus)); 
        axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
        ps_waddr_transmit(.clk(clk), .rst(rst),
                          .bus(wa_if.transmit_bus));
        axi_transmit #(.BUS_WIDTH(`A_BUS_WIDTH), .DATA_WIDTH(`A_DATA_WIDTH))
        ps_raddr_transmit(.clk(clk), .rst(rst),
                          .bus(ra_if.transmit_bus)); 

    task automatic reset_errors();
        total_errors += debug.get_error_count();
        debug.clear_error_count(); 
    endtask 
	always #(0.5s/(CLK_RATE_MHZ*1_000_000)) clk = ~clk;
	initial begin
        $dumpfile("slave_test.vcd");
        $dumpvars(0,slave_test); 
        {clk,rst} = 0;
     	repeat (20) @(posedge clk);
        debug.displayc($sformatf("\n\n### TESTING %s ###\n\n",debug.get_test_name()));
     	debug.timeout_watcher(clk,TIMEOUT);
        repeat (5) @(posedge clk);
        flash_signal(rst,clk);        
        tb_i.init(); 
       	repeat (20) @(posedge clk);
        //Run tests first with constant ready
        run_tests();
        tb_i.oscillate_rdys(halt_osc);
        //Run same tests with oscillating ready
        run_tests("(ready signals oscillating)");
        halt_osc = 1;
        tb_i.init();

        // ######### The following are tests where order matters (so ready can't be oscillating randomly)  #########
        
        // TEST 19
        debug.displayc($sformatf("%0d: PS writes while rtl is writing (before, during, and after)", debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        //1. Both write at same time: rtl should read its own value since it wins, then should be overwritten by the ps since the ps's request should be buffered
        curr_err = debug.get_error_count();
        fork 
            wdata = $urandom();
            begin tb_i.ps_write(debug,`RST_ADDR, 250); end 
            begin 
                repeat (2) @(posedge clk); 
                tb_i.rtl_write(0,wdata); 
                tb_i.rtl_read(0,rdata,.clr(0)); 
            end 
        join
        debug.disp_test_part(1,rdata == wdata,"Error when writing at same time (1st rtl read wrong)");
        tb_i.ps_read(`RST_ADDR,rdata);
        debug.disp_test_part(2,rdata == 250,"Error when writing at same time (ps read wrong)");
        tb_i.rtl_read(0,rdata);
        debug.disp_test_part(3,rdata == 250,"Error when writing at same time (2nd rtl read wrong)");
        //2. rtl writes immediately after ps; no conflict, should read rtl value
        fork 
            wdata = $urandom();
            begin tb_i.ps_write(debug,`RST_ADDR, 350); end 
            begin 
                repeat (3) @(posedge clk); 
                tb_i.rtl_write(0,wdata); 
                tb_i.rtl_read(0,rdata,.clr(0)); 
            end 
        join
        debug.disp_test_part(4,rdata == wdata,"Error when rtl writes immediately after ps (rtl read wrong)");
        tb_i.ps_read(`RST_ADDR,rdata);
        debug.disp_test_part(5,rdata == wdata,"Error when rtl writes immediately after ps (ps read wrong)");
        //3. rtl writes immediately before ps; no conflict, should read ps value (rtl should read its own at first since the rtl read takes precedence over the ps write)
        fork 
            wdata = $urandom();
            begin tb_i.ps_write(debug,`RST_ADDR, 450); end 
            begin 
                repeat (1) @(posedge clk); 
                tb_i.rtl_write(0,wdata); 
                tb_i.rtl_read(0,rdata,.clr(0)); 
            end 
        join
        debug.disp_test_part(6,rdata == wdata,"Error when rtl writes immediately before ps (1st rtl read wrong)");
        tb_i.ps_read(`RST_ADDR,rdata);
        debug.disp_test_part(7,rdata == 450,"Error when rtl writes immediately before ps (ps read wrong)");
        tb_i.rtl_read(0,rdata); 
        debug.disp_test_part(8,rdata == 450,"Error when rtl writes immediately before ps (2nd rtl read wrong");
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

         // TEST 20
        debug.displayc($sformatf("%0d: RTL writes then reads (before, during, after) ", debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));
        // 1. write and read at same time
        curr_err = debug.get_error_count();
        wdata = $urandom();
        tb_i.rtl_write(`DAC1_ID, wdata);
        fork 
            begin tb_i.rtl_write(`DAC1_ID, 10); end
            begin tb_i.rtl_read(`DAC1_ID, rdata, .clr(0)); end 
        join 
        debug.disp_test_part(1,rdata == wdata,"1: 1st read wrong");
        tb_i.rtl_read(`DAC1_ID, rdata); 
        debug.disp_test_part(2,rdata == 10,"1: 2nd read wrong");
        // 2. Read before write
        wdata = $urandom();
        fork 
            begin tb_i.rtl_read(`DAC1_ID, rdata, .clr(0)); end 
            begin @(posedge clk); tb_i.rtl_write(`DAC1_ID, wdata); end
        join 
        debug.disp_test_part(3,rdata == 10,"2: 1st read wrong");
        tb_i.rtl_read(`DAC1_ID, rdata); 
        debug.disp_test_part(4,rdata == wdata,"2: 2nd read wrong");
        // 2. Write before read
        wdata = $urandom();
        fork 
            begin tb_i.rtl_write(`DAC1_ID, wdata); end
            begin @(posedge clk); tb_i.rtl_read(`DAC1_ID, rdata, .clr(0)); end 
        join 
        debug.disp_test_part(5,rdata == wdata,"3: 1st read wrong");
        tb_i.rtl_read(`DAC1_ID, rdata); 
        debug.disp_test_part(6,rdata == wdata,"3: 2nd read wrong");
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

         // TEST 21
        debug.displayc($sformatf("%0d: Test RTLPOLL address", debug.test_num), .msg_verbosity(sim_util_pkg::VERBOSE));        
        curr_err = debug.get_error_count();
        debug.disp_test_part(1,fresh_bits == 0,"Freshbits shouldn't be activated right now");
        fork 
            begin tb_i.ps_write(debug, `SCALE_DAC_OUT_ADDR, 5); end
            begin 
                rtl_rdy[`SCALE_DAC_OUT_ID] <= 0;
                while (1) begin
                    @ (posedge clk); 
                    if (fresh_bits != 0) break; 
                end
            end 
        join
        repeat (10) @(posedge clk); 
        debug.disp_test_part(2,fresh_bits[`SCALE_DAC_OUT_ID] == 1,"Freshbits should be high");
        rtl_rdy[`SCALE_DAC_OUT_ID] <= 1;
        repeat(2) @(posedge clk);
        debug.disp_test_part(3,fresh_bits[`SCALE_DAC_OUT_ID] == 0,"Freshbits should have fallen");
        debug.disp_test_part(4,rtl_rd_out[`SCALE_DAC_OUT_ID] == 5,"Correct value not polled");
        total_errors += debug.get_error_count();
        debug.set_error_count(total_errors); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));

        debug.fatalc("### SHOULD NOT BE HERE. CHECK TEST NUMBER ###");
    end 


    task automatic run_tests(input string osc_string = "");
        // TEST 1
        debug.displayc($sformatf("%0d: PS Write (addr delayed) %s",debug.test_num,osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));
        wdata = $urandom();
        tb_i.ps_write(debug,`RST_ADDR, wdata, .delay($urandom_range(3,20)), .addr_first(1));
        tb_i.rtl_read(0,rdata);
        debug.check_test(rdata == wdata, .has_parts(0));
        reset_errors();

        // TEST 2
        debug.displayc($sformatf("%0d: PS Write (data delayed) %s",debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));
        wdata = $urandom();
        tb_i.ps_write(debug,`RST_ADDR, wdata, .delay($urandom_range(3,20)), .addr_first(0));
        tb_i.rtl_read(0,rdata);
        debug.check_test(rdata == wdata, .has_parts(0));
        reset_errors();

       
        // TEST 3
        debug.displayc($sformatf("%0d: RTL holds a write while PS tries to write %s", debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));
        curr_err = debug.get_error_count();
        wdata = $urandom(); 
        for (int i = `PS_SEED_BASE_ID; i <= `PS_SEED_VALID_ID; i++) begin
            rtl_write_reqs[i] <= 1;
            rtl_wd_in[i] <= 16'hBEEF; 
        end
        @(posedge clk); 
        fork 
            tb_i.ps_write(debug,`PS_SEED_BASE_ADDR+4, wdata);
        join_none
        repeat(20) @(posedge clk);
        tb_i.rtl_read(`PS_SEED_BASE_ID+1,rdata); 
        debug.disp_test_part(1,rdata == 16'hBEEF,"Error while rtl holds write (rtl read wrong)");
        debug.disp_test_part(2,dut_i.ps_write_req == 1,"PS write req should not be complete yet");
        for (int i = `PS_SEED_BASE_ID; i <= `PS_SEED_VALID_ID; i++) begin
            rtl_wd_in[i] <= 16'hBEEF+(i-`PS_SEED_BASE_ID); 
            @(posedge clk); 
        end
        tb_i.rtl_read(`PS_SEED_BASE_ID+1,rdata); 
        debug.disp_test_part(3,rdata == (16'hBEEF+1),"Error while rtl holds write (rtl read wrong)");
        debug.disp_test_part(4,dut_i.ps_write_req == 1,"PS write req should not be complete yet");
        repeat(5) @(posedge clk);
        {rtl_wd_in,rtl_write_reqs} <= 0;
        while (~dut_i.wcomplete) @(posedge clk);
        debug.disp_test_part(5,dut_i.ps_write_req == 0,"PS write req should be done now");
        tb_i.ps_read(`PS_SEED_BASE_ADDR+4,rdata);
        debug.disp_test_part(6,rdata == wdata,"PS read wrong");
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 4
        debug.displayc($sformatf("%0d: RTL holds writes while PS tries to write to an unrelated address %s", debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));
        wdata = $urandom(); 
        for (int i = `PS_SEED_BASE_ID; i <= `PS_SEED_VALID_ID; i++) begin
            if (i != `PS_SEED_BASE_ID+3) begin
                rtl_write_reqs[i] <= 1;
                rtl_wd_in[i] <= 16'hBEEF+i; 
            end 
        end
        tb_i.ps_write(debug,`PS_SEED_BASE_ADDR+(4*3), wdata);
        tb_i.ps_read(`PS_SEED_BASE_ADDR+(4*3),rdata);
        {rtl_wd_in,rtl_write_reqs} <= 0;
        debug.check_test(rdata == wdata, .has_parts(0));
        reset_errors();

        // TEST 5
        debug.displayc($sformatf("%0d: Ensure read response is set %s", debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));
        fork 
            begin tb_i.ps_read(`RST_ADDR,wdata); end
            begin 
                while (1) begin
                    if (rr_if.valid_pack) begin
                        rdata = rr_if.packet;
                        break;
                    end
                    @ (posedge clk);
                end
            end
        join
        debug.check_test(rdata == `OKAY, .has_parts(0));
        reset_errors();

        // TEST 6
        debug.displayc($sformatf("%0d: Perform a PS memory test %s", debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));        
        curr_err = debug.get_error_count();
        tb_i.mem_test(debug); 
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 7
        debug.displayc($sformatf("%0d: Read/Write past memory space %s", debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));        
        curr_err = debug.get_error_count();
        tb_i.ps_read(`ABS_ADDR_CEILING,rdata); 
        debug.disp_test_part(1,$signed(rdata) == -2,$sformatf("MMap ceiling should contain -2. Read data is %0d", rdata));
        tb_i.ps_write(debug,`ABS_ADDR_CEILING, 500);
        tb_i.ps_read(`ABS_ADDR_CEILING,rdata); 
        debug.disp_test_part(2,$signed(rdata) == -2,"MMap ceiling should not be writable");
        tb_i.ps_read(`ABS_ADDR_CEILING+4*50,rdata);
        debug.disp_test_part(3,$signed(rdata) == -2,"Reading past ceiling should resolve to the ceiling");
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 8
        debug.displayc($sformatf("%0d: Reset memory map and check default values %s", debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));        
        curr_err = debug.get_error_count();
        flash_signal(rst,clk);
        tb_i.check_addr_space(debug);       
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();

        // TEST 9
        debug.displayc($sformatf("%0d: Write to entire mapped address space %s", debug.test_num, osc_string), .msg_verbosity(sim_util_pkg::VERBOSE));        
        curr_err = debug.get_error_count();
        tb_i.write_addr_space(debug);
        tb_i.check_addr_space(debug,.has_written(1));
        debug.check_test(curr_err == debug.get_error_count(), .has_parts(1));
        reset_errors();
    endtask
endmodule 

`default_nettype wire

