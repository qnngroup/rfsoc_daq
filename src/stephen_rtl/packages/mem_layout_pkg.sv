`default_nettype none
`timescale 1ns / 1ps

`ifndef MEM_LAYOUT_PKG_SV
`define MEM_LAYOUT_PKG_SV

    package mem_layout_pkg;
        import axi_params_pkg::ADDRW;
        import daq_params_pkg::DAC_NUM;
        import daq_params_pkg::BATCH_SIZE;
        import daq_params_pkg::PWL_PERIOD_SIZE; 
        localparam MEM_SIZE      = 512;              // Axi Memory map size
        localparam MEM_WIDTH     = $clog2(MEM_SIZE); // Memory size bit width
        // IDs for internal mem_map usages. Note:
        // RPOLL = RTL_POLL => address is a polling address => after ps writes, freshbits are cleared once the rtl is ready to poll
        // PS_BIGREG = Large registers the ps writes to and rtl reads from (valid addr handled appropriately)
        // RTL_BIGREG = Large registers the rtl writes to and ps reads from (valid addr handled appropriately and when needed)
        // READONLY = rtl and ps cannot write to this addr
        localparam logic[MEM_WIDTH-1:0] RST_ID                            = {MEM_WIDTH{1'b0}};                                         // (RPOLL)  Reset register
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] PS_SEED_BASE_IDS     = gen_dac_ids(RST_ID+1, BATCH_SIZE+1);                       // (RPOLLs, PS_BIGREG) Register for seeds that will be used by the random signal generator (This and next BATCH_SIZE addresses)
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] PS_SEED_VALID_IDS    = gen_dac_ids(PS_SEED_BASE_IDS[0]+BATCH_SIZE, BATCH_SIZE+1); // (RPOLL)  Indicates to rtl that a batch of seeds have been stored. 
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] TRIG_WAVE_IDS        = gen_dac_ids(PS_SEED_VALID_IDS[DAC_NUM-1]+1, 1);              // (RPOLL)  Triggers the triangle wave generation 
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] DAC_HLT_IDS          = gen_dac_ids(TRIG_WAVE_IDS[DAC_NUM-1]+1, 1);                               // (RPOLL)  Halts the DAC output
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] DAC_BURST_SIZE_IDS   = gen_dac_ids(DAC_HLT_IDS[DAC_NUM-1]+1, 1);                               // (RPOLL)  Write here to dictate the new number of batches burst from the DAC     
        localparam logic[MEM_WIDTH-1:0] MAX_DAC_BURST_SIZE_ID             = DAC_BURST_SIZE_IDS[DAC_NUM-1] + 1;                               // (READONLY)  stores the maximum number of batches capable of bursting from the DAC
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] DAC_SCALE_IDS        = gen_dac_ids(MAX_DAC_BURST_SIZE_ID+1, 1);                               // (RPOLL)  Write here to scale down the output of the DAC (by at most 15). 
        localparam logic[MEM_WIDTH-1:0] DAC1_ID                           = DAC_SCALE_IDS[DAC_NUM-1] + 1;                               // Traffic here is directed to the first DAC
        localparam logic[MEM_WIDTH-1:0] DAC2_ID                           = DAC_SCALE_IDS[DAC_NUM-1] + 2;                               // Traffic here is directed to the second DAC
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] RUN_PWL_IDS          = gen_dac_ids(DAC2_ID+1, 1);                               // (RPOLL)  Run whatever waveform was last saved to the pwl
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] PWL_PERIOD_IDS       = gen_dac_ids(RUN_PWL_IDS[DAC_NUM-1]+1, PWL_PERIOD_SIZE+1);                               // (RTL_BIGREG) stores the pwl wave period for a given dac channel
        localparam logic[DAC_NUM-1:0][MEM_WIDTH-1:0] PWL_PERIOD_VALID_IDS = gen_dac_ids(PWL_PERIOD_IDS[0]+PWL_PERIOD_SIZE, PWL_PERIOD_SIZE+1);                               // (RTL_BIGREG) stores the pwl wave period for a given dac channel
        localparam logic[MEM_WIDTH-1:0] BUFF_CONFIG_ID                    = PWL_PERIOD_VALID_IDS[DAC_NUM-1] + 1;                          // (RPOLL)  Buffer config register
        localparam logic[MEM_WIDTH-1:0] BUFF_TIME_BASE_ID                 = PWL_PERIOD_VALID_IDS[DAC_NUM-1] + 2;                                  // (RTL_BIGREG) Buffer timestamp base register (This and next BUFF_SIZE addresses).
        localparam logic[MEM_WIDTH-1:0] BUFF_TIME_VALID_ID                = BUFF_TIME_BASE_ID + (daq_params_pkg::BUFF_SIZE);    // Indicates to rtl that a full buffer timestamp value has been sent to the previous BUFF_SIZE address.
        localparam logic[MEM_WIDTH-1:0] CHAN_MUX_BASE_ID                  = BUFF_TIME_VALID_ID + 1;                             // (RPOLLs, PS_BIGREG) Channel mux base register (This and next CHAN_SIZE addresses) 
        localparam logic[MEM_WIDTH-1:0] CHAN_MUX_VALID_ID                 = CHAN_MUX_BASE_ID + (daq_params_pkg::CHAN_SIZE);     // (RPOLL)  Indicates to rtl that a full channel mux value has been sent to the previous CHAN_SIZE address.
        localparam logic[MEM_WIDTH-1:0] SDC_BASE_ID                       = CHAN_MUX_VALID_ID + 1;                              // (RPOLLs, PS_BIGREG) Sample discriminator base register (This and next SDC_SIZE addresses)
        localparam logic[MEM_WIDTH-1:0] SDC_VALID_ID                      = SDC_BASE_ID +  (daq_params_pkg::SDC_SIZE);          // (RPOLL)  Indicates to rtl that a full sdc value has been sent to the previous SDC_SIZE address.  
        localparam logic[MEM_WIDTH-1:0] VERSION_ID                        = SDC_VALID_ID + 1;                                   // (READONLY) Reports the firmware version
        localparam logic[MEM_WIDTH-1:0] MEM_SIZE_ID                       = SDC_VALID_ID + 2;                                   // (READONLY)  stores the memory size. 
        localparam logic[MEM_WIDTH-1:0] MAPPED_ID_CEILING                 = MEM_SIZE_ID + 1;                                    // Top of mapped memory IDs
        localparam logic[MEM_WIDTH-1:0] MEM_TEST_BASE_ID                  = MEM_SIZE - 55;                                      // The next 50 addresses are reserved for memory testing 
        localparam logic[MEM_WIDTH-1:0] MEM_TEST_END_ID                   = MEM_TEST_BASE_ID + 50;                              // (READONLY) End of Memory testing
        localparam logic[MEM_WIDTH-1:0] ABS_ID_CEILING                    = MEM_SIZE - 1;                                       // (READONLY)  The highest entry in the mem-map, contains -2
        
        // Addresses for external mem_map usages
        localparam logic[ADDRW-1:0] PS_BASE_ADDR                        = 32'h9000_0000;
        localparam logic[ADDRW-1:0] RST_ADDR                            = PS_BASE_ADDR;
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] PS_SEED_BASE_ADDRS     = gen_dac_addrs(RST_ADDR+4, daq_params_pkg::BATCH_SIZE+1);
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] PS_SEED_VALID_ADDRS    = gen_dac_addrs(PS_SEED_BASE_ADDRS[0]+(4*daq_params_pkg::BATCH_SIZE), daq_params_pkg::BATCH_SIZE+1);
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] TRIG_WAVE_ADDRS        = gen_dac_addrs(PS_SEED_VALID_ADDRS[DAC_NUM-1]+4, 1);         
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] DAC_HLT_ADDRS          = gen_dac_addrs(TRIG_WAVE_ADDRS[DAC_NUM-1]+4, 1);             
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] DAC_BURST_SIZE_ADDRS   = gen_dac_addrs(DAC_HLT_ADDRS[DAC_NUM-1]+4, 1);               
        localparam logic[ADDRW-1:0] MAX_DAC_BURST_SIZE_ADDR             = DAC_BURST_SIZE_ADDRS[DAC_NUM-1] + 4;                      
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] DAC_SCALE_ADDRS        = gen_dac_addrs(MAX_DAC_BURST_SIZE_ADDR+4, 1);                
        localparam logic[ADDRW-1:0] DAC1_ADDR                           = DAC_SCALE_ADDRS[DAC_NUM-1] + 4;                           
        localparam logic[ADDRW-1:0] DAC2_ADDR                           = DAC_SCALE_ADDRS[DAC_NUM-1] + 4*2;                           
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] RUN_PWL_ADDRS          = gen_dac_addrs(DAC2_ADDR+4, 1);                              
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] PWL_PERIOD_ADDRS       = gen_dac_addrs(RUN_PWL_ADDRS[DAC_NUM-1]+4, PWL_PERIOD_SIZE+1);        
        localparam logic[DAC_NUM-1:0][ADDRW-1:0] PWL_PERIOD_VALID_ADDRS = gen_dac_addrs(PWL_PERIOD_ADDRS[0]+(4*PWL_PERIOD_SIZE), PWL_PERIOD_SIZE+1);
        localparam logic[ADDRW-1:0] BUFF_CONFIG_ADDR                    = PWL_PERIOD_VALID_ADDRS[DAC_NUM-1] + 4;               
        localparam logic[ADDRW-1:0] BUFF_TIME_BASE_ADDR                 = PWL_PERIOD_VALID_ADDRS[DAC_NUM-1] + 4*2;               
        localparam logic[ADDRW-1:0] BUFF_TIME_VALID_ADDR                = BUFF_TIME_BASE_ADDR + 4 *(daq_params_pkg::BUFF_SIZE);   
        localparam logic[ADDRW-1:0] CHAN_MUX_BASE_ADDR                  = BUFF_TIME_VALID_ADDR + 4;
        localparam logic[ADDRW-1:0] CHAN_MUX_VALID_ADDR                 = CHAN_MUX_BASE_ADDR + 4 * (daq_params_pkg::CHAN_SIZE);
        localparam logic[ADDRW-1:0] SDC_BASE_ADDR                       = CHAN_MUX_VALID_ADDR + 4;
        localparam logic[ADDRW-1:0] SDC_VALID_ADDR                      = SDC_BASE_ADDR + 4 * (daq_params_pkg::SDC_SIZE);
        localparam logic[ADDRW-1:0] VERSION_ADDR                        = SDC_VALID_ADDR + 4;
        localparam logic[ADDRW-1:0] MEM_SIZE_ADDR                       = SDC_VALID_ADDR + 4*2;
        localparam logic[ADDRW-1:0] MAPPED_ADDR_CEILING                 = MEM_SIZE_ADDR + 4;
        localparam logic[ADDRW-1:0] MEM_TEST_BASE_ADDR                  = PS_BASE_ADDR + 4*(MEM_SIZE - 55);
        localparam logic[ADDRW-1:0] MEM_TEST_END_ADDR                   = MEM_TEST_BASE_ADDR + 4*50;
        localparam logic[ADDRW-1:0] ABS_ADDR_CEILING                    = PS_BASE_ADDR + 4*(MEM_SIZE-1);

        localparam ADDR_NUM = 89;
        logic[ADDR_NUM-1:0][ADDRW-1:0] addrs = {ABS_ADDR_CEILING, MEM_TEST_END_ADDR, MEM_TEST_BASE_ADDR, MAPPED_ADDR_CEILING, MEM_SIZE_ADDR, VERSION_ADDR, SDC_VALID_ADDR, SDC_BASE_ADDR, CHAN_MUX_VALID_ADDR, CHAN_MUX_BASE_ADDR, BUFF_TIME_VALID_ADDR, BUFF_TIME_BASE_ADDR, BUFF_CONFIG_ADDR, PWL_PERIOD_VALID_ADDRS[7], PWL_PERIOD_VALID_ADDRS[6], PWL_PERIOD_VALID_ADDRS[5], PWL_PERIOD_VALID_ADDRS[4], PWL_PERIOD_VALID_ADDRS[3], PWL_PERIOD_VALID_ADDRS[2], PWL_PERIOD_VALID_ADDRS[1], PWL_PERIOD_VALID_ADDRS[0], PWL_PERIOD_ADDRS[7], PWL_PERIOD_ADDRS[6], PWL_PERIOD_ADDRS[5], PWL_PERIOD_ADDRS[4], PWL_PERIOD_ADDRS[3], PWL_PERIOD_ADDRS[2], PWL_PERIOD_ADDRS[1], PWL_PERIOD_ADDRS[0], RUN_PWL_ADDRS[7], RUN_PWL_ADDRS[6], RUN_PWL_ADDRS[5], RUN_PWL_ADDRS[4], RUN_PWL_ADDRS[3], RUN_PWL_ADDRS[2], RUN_PWL_ADDRS[1], RUN_PWL_ADDRS[0], DAC2_ADDR, DAC1_ADDR, DAC_SCALE_ADDRS[7], DAC_SCALE_ADDRS[6], DAC_SCALE_ADDRS[5], DAC_SCALE_ADDRS[4], DAC_SCALE_ADDRS[3], DAC_SCALE_ADDRS[2], DAC_SCALE_ADDRS[1], DAC_SCALE_ADDRS[0], MAX_DAC_BURST_SIZE_ADDR, DAC_BURST_SIZE_ADDRS[7], DAC_BURST_SIZE_ADDRS[6], DAC_BURST_SIZE_ADDRS[5], DAC_BURST_SIZE_ADDRS[4], DAC_BURST_SIZE_ADDRS[3], DAC_BURST_SIZE_ADDRS[2], DAC_BURST_SIZE_ADDRS[1], DAC_BURST_SIZE_ADDRS[0], DAC_HLT_ADDRS[7], DAC_HLT_ADDRS[6], DAC_HLT_ADDRS[5], DAC_HLT_ADDRS[4], DAC_HLT_ADDRS[3], DAC_HLT_ADDRS[2], DAC_HLT_ADDRS[1], DAC_HLT_ADDRS[0], TRIG_WAVE_ADDRS[7], TRIG_WAVE_ADDRS[6], TRIG_WAVE_ADDRS[5], TRIG_WAVE_ADDRS[4], TRIG_WAVE_ADDRS[3], TRIG_WAVE_ADDRS[2], TRIG_WAVE_ADDRS[1], TRIG_WAVE_ADDRS[0], PS_SEED_VALID_ADDRS[7], PS_SEED_VALID_ADDRS[6], PS_SEED_VALID_ADDRS[5], PS_SEED_VALID_ADDRS[4], PS_SEED_VALID_ADDRS[3], PS_SEED_VALID_ADDRS[2], PS_SEED_VALID_ADDRS[1], PS_SEED_VALID_ADDRS[0], PS_SEED_BASE_ADDRS[7], PS_SEED_BASE_ADDRS[6], PS_SEED_BASE_ADDRS[5], PS_SEED_BASE_ADDRS[4], PS_SEED_BASE_ADDRS[3], PS_SEED_BASE_ADDRS[2], PS_SEED_BASE_ADDRS[1], PS_SEED_BASE_ADDRS[0], RST_ADDR};
        logic[ADDR_NUM-1:0][MEM_WIDTH-1:0] ids = {ABS_ID_CEILING, MEM_TEST_END_ID, MEM_TEST_BASE_ID, MAPPED_ID_CEILING, MEM_SIZE_ID, VERSION_ID, SDC_VALID_ID, SDC_BASE_ID, CHAN_MUX_VALID_ID, CHAN_MUX_BASE_ID, BUFF_TIME_VALID_ID, BUFF_TIME_BASE_ID, BUFF_CONFIG_ID, PWL_PERIOD_VALID_IDS[7], PWL_PERIOD_VALID_IDS[6], PWL_PERIOD_VALID_IDS[5], PWL_PERIOD_VALID_IDS[4], PWL_PERIOD_VALID_IDS[3], PWL_PERIOD_VALID_IDS[2], PWL_PERIOD_VALID_IDS[1], PWL_PERIOD_VALID_IDS[0], PWL_PERIOD_IDS[7], PWL_PERIOD_IDS[6], PWL_PERIOD_IDS[5], PWL_PERIOD_IDS[4], PWL_PERIOD_IDS[3], PWL_PERIOD_IDS[2], PWL_PERIOD_IDS[1], PWL_PERIOD_IDS[0], RUN_PWL_IDS[7], RUN_PWL_IDS[6], RUN_PWL_IDS[5], RUN_PWL_IDS[4], RUN_PWL_IDS[3], RUN_PWL_IDS[2], RUN_PWL_IDS[1], RUN_PWL_IDS[0], DAC2_ID, DAC1_ID, DAC_SCALE_IDS[7], DAC_SCALE_IDS[6], DAC_SCALE_IDS[5], DAC_SCALE_IDS[4], DAC_SCALE_IDS[3], DAC_SCALE_IDS[2], DAC_SCALE_IDS[1], DAC_SCALE_IDS[0], MAX_DAC_BURST_SIZE_ID, DAC_BURST_SIZE_IDS[7], DAC_BURST_SIZE_IDS[6], DAC_BURST_SIZE_IDS[5], DAC_BURST_SIZE_IDS[4], DAC_BURST_SIZE_IDS[3], DAC_BURST_SIZE_IDS[2], DAC_BURST_SIZE_IDS[1], DAC_BURST_SIZE_IDS[0], DAC_HLT_IDS[7], DAC_HLT_IDS[6], DAC_HLT_IDS[5], DAC_HLT_IDS[4], DAC_HLT_IDS[3], DAC_HLT_IDS[2], DAC_HLT_IDS[1], DAC_HLT_IDS[0], TRIG_WAVE_IDS[7], TRIG_WAVE_IDS[6], TRIG_WAVE_IDS[5], TRIG_WAVE_IDS[4], TRIG_WAVE_IDS[3], TRIG_WAVE_IDS[2], TRIG_WAVE_IDS[1], TRIG_WAVE_IDS[0], PS_SEED_VALID_IDS[7], PS_SEED_VALID_IDS[6], PS_SEED_VALID_IDS[5], PS_SEED_VALID_IDS[4], PS_SEED_VALID_IDS[3], PS_SEED_VALID_IDS[2], PS_SEED_VALID_IDS[1], PS_SEED_VALID_IDS[0], PS_SEED_BASE_IDS[7], PS_SEED_BASE_IDS[6], PS_SEED_BASE_IDS[5], PS_SEED_BASE_IDS[4], PS_SEED_BASE_IDS[3], PS_SEED_BASE_IDS[2], PS_SEED_BASE_IDS[1], PS_SEED_BASE_IDS[0], RST_ID};

        // Useful functions
        function automatic logic[MEM_WIDTH-1:0] ADDR2ID(logic[ADDRW-1:0] addr);
            return (addr - PS_BASE_ADDR) >> 2;
        endfunction  
        function automatic logic[ADDRW-1:0] ID2ADDR(logic[MEM_WIDTH-1:0] index);
            return (index << 2) + PS_BASE_ADDR;
        endfunction 
        function automatic logic[DAC_NUM-1:0][ADDRW-1:0] gen_dac_addrs(logic[ADDRW-1:0] base_addr, int reg_width);
          logic[DAC_NUM-1:0][ADDRW-1:0] dac_addr_bases; 
          for (int i = 0; i < DAC_NUM; i++) dac_addr_bases[i] = base_addr + reg_width*(4*i); 
          return dac_addr_bases; 
        endfunction 
        function automatic logic[DAC_NUM-1:0][MEM_WIDTH-1:0] gen_dac_ids(logic[MEM_WIDTH-1:0] base_id, int reg_width);
          logic[DAC_NUM-1:0][MEM_WIDTH-1:0] dac_id_bases; 
          logic[DAC_NUM-1:0][ADDRW-1:0] dac_addr_bases = gen_dac_addrs(ID2ADDR(base_id), reg_width);; 
          for (int i = 0; i < DAC_NUM; i++) dac_id_bases[i] = ADDR2ID(dac_addr_bases[i]);
          return dac_id_bases; 
        endfunction  
        /*
        is_DAC_REG => regs relevant to the DACs on the board (ie they are able to be referenced in a vector of length DAC_NUM)
        is_READONLY => regs the ps can only read from (rtl can write)
        is_RTLPOLL => regs where rtl only reads from and ps writes to. 
        is_PS_BIGREG => large regs the processor writes to and rtl reads from
        is_RTL_BIGREG => large regs the rtl writes to and ps reads from
        is_PS_VALID => the valid signal for large regs of type PS_BIGREG
        is_RTL_VALID => the valid signal for large regs of type RTL_BIGREG
        */
        function automatic bit is_READONLY(logic[MEM_WIDTH-1:0] index);
            return index == MAX_DAC_BURST_SIZE_ID || index == VERSION_ID || index == MEM_SIZE_ID ||  (index >= MAPPED_ID_CEILING && index < MEM_TEST_BASE_ID) || (index >= MEM_TEST_END_ID && index <= ABS_ID_CEILING);
        endfunction
        function automatic bit is_RTLPOLL(logic[MEM_WIDTH-1:0] index);
            return index == RST_ID || (index >= PS_SEED_BASE_IDS[0] && index <= PS_SEED_VALID_IDS[DAC_NUM-1]) || (index >= TRIG_WAVE_IDS[0] && index <= TRIG_WAVE_IDS[DAC_NUM-1]) || (index >= DAC_HLT_IDS[0] && index <= DAC_HLT_IDS[DAC_NUM-1]) || (index >= RUN_PWL_IDS[0] && index <= RUN_PWL_IDS[DAC_NUM-1]) || (index >= DAC_BURST_SIZE_IDS[0] && index <= DAC_BURST_SIZE_IDS[DAC_NUM-1]) || (index >= DAC_SCALE_IDS[0] && index <= DAC_SCALE_IDS[DAC_NUM-1]) || index == BUFF_CONFIG_ID || (index >= CHAN_MUX_BASE_ID && index <= CHAN_MUX_VALID_ID)  || (index >= SDC_BASE_ID && index <= SDC_VALID_ID);
        endfunction
        function automatic bit is_PS_BIGREG(logic[MEM_WIDTH-1:0] index);
            return (index >= PS_SEED_BASE_IDS[0] && index <= PS_SEED_VALID_IDS[DAC_NUM-1]) || (index >= CHAN_MUX_BASE_ID && index <= CHAN_MUX_VALID_ID)  || (index >= SDC_BASE_ID && index <= SDC_VALID_ID);
        endfunction
        function automatic bit is_RTL_BIGREG(logic[MEM_WIDTH-1:0] index);
            return (index >= BUFF_TIME_BASE_ID && index <= BUFF_TIME_VALID_ID) || (index >= PWL_PERIOD_IDS[0] && index <= PWL_PERIOD_VALID_IDS[DAC_NUM-1]);
        endfunction
        function automatic bit is_PS_VALID(logic[MEM_WIDTH-1:0] index);
            bit is_valid = 0;
            for (int i = 0; i < DAC_NUM; i++) begin
                if (index == PS_SEED_VALID_IDS[i]) begin 
                    is_valid = 1;
                    break;
                end 
            end
            return is_valid || index == CHAN_MUX_VALID_ID  || index == SDC_VALID_ID;
        endfunction
        function automatic bit is_RTL_VALID(logic[MEM_WIDTH-1:0] index);
            bit is_valid = 0;
            for (int i = 0; i < DAC_NUM; i++) begin
                if (index == PWL_PERIOD_VALID_IDS[i]) begin  
                    is_valid = 1;
                    break;
                end 
            end
            return is_valid || index == BUFF_TIME_VALID_ID;
        endfunction
        function automatic bit is_DAC_REG(logic[MEM_WIDTH-1:0] index);
            return (index >= PS_SEED_BASE_IDS[0] && index <= PS_SEED_VALID_IDS[DAC_NUM-1]) || (index >= TRIG_WAVE_IDS[0] && index <= TRIG_WAVE_IDS[DAC_NUM-1]) || (index >= DAC_HLT_IDS[0] && index <= DAC_HLT_IDS[DAC_NUM-1]) || (index >= RUN_PWL_IDS[0] && index <= RUN_PWL_IDS[DAC_NUM-1]) || (index >= DAC_BURST_SIZE_IDS[0] && index <= DAC_BURST_SIZE_IDS[DAC_NUM-1]) || (index >= DAC_SCALE_IDS[0] && index <= DAC_SCALE_IDS[DAC_NUM-1]) || (index >= PWL_PERIOD_IDS[0] && index <= PWL_PERIOD_VALID_IDS[DAC_NUM-1]);
        endfunction
        function automatic bit is_DACBS_REG(logic[MEM_WIDTH-1:0] index);
            return (index >= DAC_BURST_SIZE_IDS[0] && index <= DAC_BURST_SIZE_IDS[DAC_NUM-1]);
        endfunction
        function automatic bit is_DACSCALE_REG(logic[MEM_WIDTH-1:0] index);
            return (index >= DAC_SCALE_IDS[0] && index <= DAC_SCALE_IDS[DAC_NUM-1]);
        endfunction
    endpackage 

`endif

`default_nettype wire


/*
(Numbers in parenthesis indicate DAC number)

Processor MMIO Addresses
################################################
rst                 <=> 0x90000000
seeds               <=> (0): 0x90000004, (1): 0x90000048, (2): 0x9000008C, (3): 0x900000D0, (4): 0x90000114, (5): 0x90000158, (6): 0x9000019C, (7): 0x900001E0
seed_valids         <=> (0): 0x90000044, (1): 0x90000088, (2): 0x900000CC, (3): 0x90000110, (4): 0x90000154, (5): 0x90000198, (6): 0x900001DC, (7): 0x90000220
triangle_waves      <=> (0): 0x90000224, (1): 0x90000228, (2): 0x9000022C, (3): 0x90000230, (4): 0x90000234, (5): 0x90000238, (6): 0x9000023C, (7): 0x90000240
hlt_dacs            <=> (0): 0x90000244, (1): 0x90000248, (2): 0x9000024C, (3): 0x90000250, (4): 0x90000254, (5): 0x90000258, (6): 0x9000025C, (7): 0x90000260
dac_burst_sizes     <=> (0): 0x90000264, (1): 0x90000268, (2): 0x9000026C, (3): 0x90000270, (4): 0x90000274, (5): 0x90000278, (6): 0x9000027C, (7): 0x90000280
max_dac_burst_size  <=> 0x90000284
dac_scales          <=> (0): 0x90000288, (1): 0x9000028C, (2): 0x90000290, (3): 0x90000294, (4): 0x90000298, (5): 0x9000029C, (6): 0x900002A0, (7): 0x900002A4
dac1                <=> 0x900002A8
dac2                <=> 0x900002AC
run_pwls            <=> (0): 0x900002B0, (1): 0x900002B4, (2): 0x900002B8, (3): 0x900002BC, (4): 0x900002C0, (5): 0x900002C4, (6): 0x900002C8, (7): 0x900002CC
pwl_periods         <=> (0): 0x900002D0, (1): 0x900002DC, (2): 0x900002E8, (3): 0x900002F4, (4): 0x90000300, (5): 0x9000030C, (6): 0x90000318, (7): 0x90000324
pwl_period_valids   <=> (0): 0x900002D8, (1): 0x900002E4, (2): 0x900002F0, (3): 0x900002FC, (4): 0x90000308, (5): 0x90000314, (6): 0x90000320, (7): 0x9000032C
buff_config         <=> 0x90000330
buff_time_base      <=> 0x90000334
buff_time_valid     <=> 0x9000033C
chan_mux_base       <=> 0x90000340
chan_mux_valid      <=> 0x90000348
sdc_base            <=> 0x9000034C
sdc_valid           <=> 0x9000038C
firmware_version    <=> 0x90000390
mem_size            <=> 0x90000394
mapped_addr_ceiling <=> 0x90000398
mem_test_base       <=> 0x90000724
mem_test_end        <=> 0x900007EC
abs_addr_ceiling    <=> 0x900007FC
################################################

RTL MMIO Indices
################################################
rst                 <=> 0
seeds               <=> (0): 1, (1): 18, (2): 35, (3): 52, (4): 69, (5): 86, (6): 103, (7): 120
seed_valids         <=> (0): 17, (1): 34, (2): 51, (3): 68, (4): 85, (5): 102, (6): 119, (7): 136
triangle_waves      <=> (0): 137, (1): 138, (2): 139, (3): 140, (4): 141, (5): 142, (6): 143, (7): 144
hlt_dacs            <=> (0): 145, (1): 146, (2): 147, (3): 148, (4): 149, (5): 150, (6): 151, (7): 152
dac_burst_sizes     <=> (0): 153, (1): 154, (2): 155, (3): 156, (4): 157, (5): 158, (6): 159, (7): 160
max_dac_burst_size  <=> 161
dac_scales          <=> (0): 162, (1): 163, (2): 164, (3): 165, (4): 166, (5): 167, (6): 168, (7): 169
dac1                <=> 170
dac2                <=> 171
run_pwls            <=> (0): 172, (1): 173, (2): 174, (3): 175, (4): 176, (5): 177, (6): 178, (7): 179
pwl_periods         <=> (0): 180, (1): 183, (2): 186, (3): 189, (4): 192, (5): 195, (6): 198, (7): 201
pwl_period_valids   <=> (0): 182, (1): 185, (2): 188, (3): 191, (4): 194, (5): 197, (6): 200, (7): 203
buff_config         <=> 204
buff_time_base      <=> 205
buff_time_valid     <=> 207
chan_mux_base       <=> 208
chan_mux_valid      <=> 210
sdc_base            <=> 211
sdc_valid           <=> 227
firmware_version    <=> 228
mem_size            <=> 229
mapped_addr_ceiling <=> 230
mem_test_base       <=> 457
mem_test_end        <=> 507
abs_addr_ceiling    <=> 511
################################################

 Full Memory Map
################################################
0X90000000, 0   : rst
0X90000004, 1   : seeds.0 + 0
0X90000008, 2   : seeds.0 + 1
0X9000000C, 3   : seeds.0 + 2
0X90000010, 4   : seeds.0 + 3
0X90000014, 5   : seeds.0 + 4
0X90000018, 6   : seeds.0 + 5
0X9000001C, 7   : seeds.0 + 6
0X90000020, 8   : seeds.0 + 7
0X90000024, 9   : seeds.0 + 8
0X90000028, 10  : seeds.0 + 9
0X9000002C, 11  : seeds.0 + 10
0X90000030, 12  : seeds.0 + 11
0X90000034, 13  : seeds.0 + 12
0X90000038, 14  : seeds.0 + 13
0X9000003C, 15  : seeds.0 + 14
0X90000040, 16  : seeds.0 + 15
0X90000044, 17  : seed_valids.0
0X90000048, 18  : seeds.1 + 0
0X9000004C, 19  : seeds.1 + 1
0X90000050, 20  : seeds.1 + 2
0X90000054, 21  : seeds.1 + 3
0X90000058, 22  : seeds.1 + 4
0X9000005C, 23  : seeds.1 + 5
0X90000060, 24  : seeds.1 + 6
0X90000064, 25  : seeds.1 + 7
0X90000068, 26  : seeds.1 + 8
0X9000006C, 27  : seeds.1 + 9
0X90000070, 28  : seeds.1 + 10
0X90000074, 29  : seeds.1 + 11
0X90000078, 30  : seeds.1 + 12
0X9000007C, 31  : seeds.1 + 13
0X90000080, 32  : seeds.1 + 14
0X90000084, 33  : seeds.1 + 15
0X90000088, 34  : seed_valids.1
0X9000008C, 35  : seeds.2 + 0
0X90000090, 36  : seeds.2 + 1
0X90000094, 37  : seeds.2 + 2
0X90000098, 38  : seeds.2 + 3
0X9000009C, 39  : seeds.2 + 4
0X900000A0, 40  : seeds.2 + 5
0X900000A4, 41  : seeds.2 + 6
0X900000A8, 42  : seeds.2 + 7
0X900000AC, 43  : seeds.2 + 8
0X900000B0, 44  : seeds.2 + 9
0X900000B4, 45  : seeds.2 + 10
0X900000B8, 46  : seeds.2 + 11
0X900000BC, 47  : seeds.2 + 12
0X900000C0, 48  : seeds.2 + 13
0X900000C4, 49  : seeds.2 + 14
0X900000C8, 50  : seeds.2 + 15
0X900000CC, 51  : seed_valids.2
0X900000D0, 52  : seeds.3 + 0
0X900000D4, 53  : seeds.3 + 1
0X900000D8, 54  : seeds.3 + 2
0X900000DC, 55  : seeds.3 + 3
0X900000E0, 56  : seeds.3 + 4
0X900000E4, 57  : seeds.3 + 5
0X900000E8, 58  : seeds.3 + 6
0X900000EC, 59  : seeds.3 + 7
0X900000F0, 60  : seeds.3 + 8
0X900000F4, 61  : seeds.3 + 9
0X900000F8, 62  : seeds.3 + 10
0X900000FC, 63  : seeds.3 + 11
0X90000100, 64  : seeds.3 + 12
0X90000104, 65  : seeds.3 + 13
0X90000108, 66  : seeds.3 + 14
0X9000010C, 67  : seeds.3 + 15
0X90000110, 68  : seed_valids.3
0X90000114, 69  : seeds.4 + 0
0X90000118, 70  : seeds.4 + 1
0X9000011C, 71  : seeds.4 + 2
0X90000120, 72  : seeds.4 + 3
0X90000124, 73  : seeds.4 + 4
0X90000128, 74  : seeds.4 + 5
0X9000012C, 75  : seeds.4 + 6
0X90000130, 76  : seeds.4 + 7
0X90000134, 77  : seeds.4 + 8
0X90000138, 78  : seeds.4 + 9
0X9000013C, 79  : seeds.4 + 10
0X90000140, 80  : seeds.4 + 11
0X90000144, 81  : seeds.4 + 12
0X90000148, 82  : seeds.4 + 13
0X9000014C, 83  : seeds.4 + 14
0X90000150, 84  : seeds.4 + 15
0X90000154, 85  : seed_valids.4
0X90000158, 86  : seeds.5 + 0
0X9000015C, 87  : seeds.5 + 1
0X90000160, 88  : seeds.5 + 2
0X90000164, 89  : seeds.5 + 3
0X90000168, 90  : seeds.5 + 4
0X9000016C, 91  : seeds.5 + 5
0X90000170, 92  : seeds.5 + 6
0X90000174, 93  : seeds.5 + 7
0X90000178, 94  : seeds.5 + 8
0X9000017C, 95  : seeds.5 + 9
0X90000180, 96  : seeds.5 + 10
0X90000184, 97  : seeds.5 + 11
0X90000188, 98  : seeds.5 + 12
0X9000018C, 99  : seeds.5 + 13
0X90000190, 100 : seeds.5 + 14
0X90000194, 101 : seeds.5 + 15
0X90000198, 102 : seed_valids.5
0X9000019C, 103 : seeds.6 + 0
0X900001A0, 104 : seeds.6 + 1
0X900001A4, 105 : seeds.6 + 2
0X900001A8, 106 : seeds.6 + 3
0X900001AC, 107 : seeds.6 + 4
0X900001B0, 108 : seeds.6 + 5
0X900001B4, 109 : seeds.6 + 6
0X900001B8, 110 : seeds.6 + 7
0X900001BC, 111 : seeds.6 + 8
0X900001C0, 112 : seeds.6 + 9
0X900001C4, 113 : seeds.6 + 10
0X900001C8, 114 : seeds.6 + 11
0X900001CC, 115 : seeds.6 + 12
0X900001D0, 116 : seeds.6 + 13
0X900001D4, 117 : seeds.6 + 14
0X900001D8, 118 : seeds.6 + 15
0X900001DC, 119 : seed_valids.6
0X900001E0, 120 : seeds.7 + 0
0X900001E4, 121 : seeds.7 + 1
0X900001E8, 122 : seeds.7 + 2
0X900001EC, 123 : seeds.7 + 3
0X900001F0, 124 : seeds.7 + 4
0X900001F4, 125 : seeds.7 + 5
0X900001F8, 126 : seeds.7 + 6
0X900001FC, 127 : seeds.7 + 7
0X90000200, 128 : seeds.7 + 8
0X90000204, 129 : seeds.7 + 9
0X90000208, 130 : seeds.7 + 10
0X9000020C, 131 : seeds.7 + 11
0X90000210, 132 : seeds.7 + 12
0X90000214, 133 : seeds.7 + 13
0X90000218, 134 : seeds.7 + 14
0X9000021C, 135 : seeds.7 + 15
0X90000220, 136 : seed_valids.7
0X90000224, 137 : triangle_waves.0
0X90000228, 138 : triangle_waves.1
0X9000022C, 139 : triangle_waves.2
0X90000230, 140 : triangle_waves.3
0X90000234, 141 : triangle_waves.4
0X90000238, 142 : triangle_waves.5
0X9000023C, 143 : triangle_waves.6
0X90000240, 144 : triangle_waves.7
0X90000244, 145 : hlt_dacs.0
0X90000248, 146 : hlt_dacs.1
0X9000024C, 147 : hlt_dacs.2
0X90000250, 148 : hlt_dacs.3
0X90000254, 149 : hlt_dacs.4
0X90000258, 150 : hlt_dacs.5
0X9000025C, 151 : hlt_dacs.6
0X90000260, 152 : hlt_dacs.7
0X90000264, 153 : dac_burst_sizes.0
0X90000268, 154 : dac_burst_sizes.1
0X9000026C, 155 : dac_burst_sizes.2
0X90000270, 156 : dac_burst_sizes.3
0X90000274, 157 : dac_burst_sizes.4
0X90000278, 158 : dac_burst_sizes.5
0X9000027C, 159 : dac_burst_sizes.6
0X90000280, 160 : dac_burst_sizes.7
0X90000284, 161 : max_dac_burst_size
0X90000288, 162 : dac_scales.0
0X9000028C, 163 : dac_scales.1
0X90000290, 164 : dac_scales.2
0X90000294, 165 : dac_scales.3
0X90000298, 166 : dac_scales.4
0X9000029C, 167 : dac_scales.5
0X900002A0, 168 : dac_scales.6
0X900002A4, 169 : dac_scales.7
0X900002A8, 170 : dac1
0X900002AC, 171 : dac2
0X900002B0, 172 : run_pwls.0
0X900002B4, 173 : run_pwls.1
0X900002B8, 174 : run_pwls.2
0X900002BC, 175 : run_pwls.3
0X900002C0, 176 : run_pwls.4
0X900002C4, 177 : run_pwls.5
0X900002C8, 178 : run_pwls.6
0X900002CC, 179 : run_pwls.7
0X900002D0, 180 : pwl_periods.0 + 0
0X900002D4, 181 : pwl_periods.0 + 1
0X900002D8, 182 : pwl_period_valids.0
0X900002DC, 183 : pwl_periods.1 + 0
0X900002E0, 184 : pwl_periods.1 + 1
0X900002E4, 185 : pwl_period_valids.1
0X900002E8, 186 : pwl_periods.2 + 0
0X900002EC, 187 : pwl_periods.2 + 1
0X900002F0, 188 : pwl_period_valids.2
0X900002F4, 189 : pwl_periods.3 + 0
0X900002F8, 190 : pwl_periods.3 + 1
0X900002FC, 191 : pwl_period_valids.3
0X90000300, 192 : pwl_periods.4 + 0
0X90000304, 193 : pwl_periods.4 + 1
0X90000308, 194 : pwl_period_valids.4
0X9000030C, 195 : pwl_periods.5 + 0
0X90000310, 196 : pwl_periods.5 + 1
0X90000314, 197 : pwl_period_valids.5
0X90000318, 198 : pwl_periods.6 + 0
0X9000031C, 199 : pwl_periods.6 + 1
0X90000320, 200 : pwl_period_valids.6
0X90000324, 201 : pwl_periods.7 + 0
0X90000328, 202 : pwl_periods.7 + 1
0X9000032C, 203 : pwl_period_valids.7
0X90000330, 204 : buff_config
0X90000334, 205 : buff_time_base + 0
0X90000338, 206 : buff_time_base + 1
0X9000033C, 207 : buff_time_valid
0X90000340, 208 : chan_mux_base + 0
0X90000344, 209 : chan_mux_base + 1
0X90000348, 210 : chan_mux_valid
0X9000034C, 211 : sdc_base + 0
0X90000350, 212 : sdc_base + 1
0X90000354, 213 : sdc_base + 2
0X90000358, 214 : sdc_base + 3
0X9000035C, 215 : sdc_base + 4
0X90000360, 216 : sdc_base + 5
0X90000364, 217 : sdc_base + 6
0X90000368, 218 : sdc_base + 7
0X9000036C, 219 : sdc_base + 8
0X90000370, 220 : sdc_base + 9
0X90000374, 221 : sdc_base + 10
0X90000378, 222 : sdc_base + 11
0X9000037C, 223 : sdc_base + 12
0X90000380, 224 : sdc_base + 13
0X90000384, 225 : sdc_base + 14
0X90000388, 226 : sdc_base + 15
0X9000038C, 227 : sdc_valid
0X90000390, 228 : firmware_version
0X90000394, 229 : mem_size
0X90000398, 230 : mapped_addr_ceiling
0X9000039C, 231 : XXX_1
0X900003A0, 232 : XXX_2
0X900003A4, 233 : XXX_3
0X900003A8, 234 : XXX_4
0X900003AC, 235 : XXX_5
0X900003B0, 236 : XXX_6
0X900003B4, 237 : XXX_7
0X900003B8, 238 : XXX_8
0X900003BC, 239 : XXX_9
0X900003C0, 240 : XXX_10
0X900003C4, 241 : XXX_11
0X900003C8, 242 : XXX_12
0X900003CC, 243 : XXX_13
0X900003D0, 244 : XXX_14
0X900003D4, 245 : XXX_15
0X900003D8, 246 : XXX_16
0X900003DC, 247 : XXX_17
0X900003E0, 248 : XXX_18
0X900003E4, 249 : XXX_19
0X900003E8, 250 : XXX_20
0X900003EC, 251 : XXX_21
0X900003F0, 252 : XXX_22
0X900003F4, 253 : XXX_23
0X900003F8, 254 : XXX_24
0X900003FC, 255 : XXX_25
0X90000400, 256 : XXX_26
0X90000404, 257 : XXX_27
0X90000408, 258 : XXX_28
0X9000040C, 259 : XXX_29
0X90000410, 260 : XXX_30
0X90000414, 261 : XXX_31
0X90000418, 262 : XXX_32
0X9000041C, 263 : XXX_33
0X90000420, 264 : XXX_34
0X90000424, 265 : XXX_35
0X90000428, 266 : XXX_36
0X9000042C, 267 : XXX_37
0X90000430, 268 : XXX_38
0X90000434, 269 : XXX_39
0X90000438, 270 : XXX_40
0X9000043C, 271 : XXX_41
0X90000440, 272 : XXX_42
0X90000444, 273 : XXX_43
0X90000448, 274 : XXX_44
0X9000044C, 275 : XXX_45
0X90000450, 276 : XXX_46
0X90000454, 277 : XXX_47
0X90000458, 278 : XXX_48
0X9000045C, 279 : XXX_49
0X90000460, 280 : XXX_50
0X90000464, 281 : XXX_51
0X90000468, 282 : XXX_52
0X9000046C, 283 : XXX_53
0X90000470, 284 : XXX_54
0X90000474, 285 : XXX_55
0X90000478, 286 : XXX_56
0X9000047C, 287 : XXX_57
0X90000480, 288 : XXX_58
0X90000484, 289 : XXX_59
0X90000488, 290 : XXX_60
0X9000048C, 291 : XXX_61
0X90000490, 292 : XXX_62
0X90000494, 293 : XXX_63
0X90000498, 294 : XXX_64
0X9000049C, 295 : XXX_65
0X900004A0, 296 : XXX_66
0X900004A4, 297 : XXX_67
0X900004A8, 298 : XXX_68
0X900004AC, 299 : XXX_69
0X900004B0, 300 : XXX_70
0X900004B4, 301 : XXX_71
0X900004B8, 302 : XXX_72
0X900004BC, 303 : XXX_73
0X900004C0, 304 : XXX_74
0X900004C4, 305 : XXX_75
0X900004C8, 306 : XXX_76
0X900004CC, 307 : XXX_77
0X900004D0, 308 : XXX_78
0X900004D4, 309 : XXX_79
0X900004D8, 310 : XXX_80
0X900004DC, 311 : XXX_81
0X900004E0, 312 : XXX_82
0X900004E4, 313 : XXX_83
0X900004E8, 314 : XXX_84
0X900004EC, 315 : XXX_85
0X900004F0, 316 : XXX_86
0X900004F4, 317 : XXX_87
0X900004F8, 318 : XXX_88
0X900004FC, 319 : XXX_89
0X90000500, 320 : XXX_90
0X90000504, 321 : XXX_91
0X90000508, 322 : XXX_92
0X9000050C, 323 : XXX_93
0X90000510, 324 : XXX_94
0X90000514, 325 : XXX_95
0X90000518, 326 : XXX_96
0X9000051C, 327 : XXX_97
0X90000520, 328 : XXX_98
0X90000524, 329 : XXX_99
0X90000528, 330 : XXX_100
0X9000052C, 331 : XXX_101
0X90000530, 332 : XXX_102
0X90000534, 333 : XXX_103
0X90000538, 334 : XXX_104
0X9000053C, 335 : XXX_105
0X90000540, 336 : XXX_106
0X90000544, 337 : XXX_107
0X90000548, 338 : XXX_108
0X9000054C, 339 : XXX_109
0X90000550, 340 : XXX_110
0X90000554, 341 : XXX_111
0X90000558, 342 : XXX_112
0X9000055C, 343 : XXX_113
0X90000560, 344 : XXX_114
0X90000564, 345 : XXX_115
0X90000568, 346 : XXX_116
0X9000056C, 347 : XXX_117
0X90000570, 348 : XXX_118
0X90000574, 349 : XXX_119
0X90000578, 350 : XXX_120
0X9000057C, 351 : XXX_121
0X90000580, 352 : XXX_122
0X90000584, 353 : XXX_123
0X90000588, 354 : XXX_124
0X9000058C, 355 : XXX_125
0X90000590, 356 : XXX_126
0X90000594, 357 : XXX_127
0X90000598, 358 : XXX_128
0X9000059C, 359 : XXX_129
0X900005A0, 360 : XXX_130
0X900005A4, 361 : XXX_131
0X900005A8, 362 : XXX_132
0X900005AC, 363 : XXX_133
0X900005B0, 364 : XXX_134
0X900005B4, 365 : XXX_135
0X900005B8, 366 : XXX_136
0X900005BC, 367 : XXX_137
0X900005C0, 368 : XXX_138
0X900005C4, 369 : XXX_139
0X900005C8, 370 : XXX_140
0X900005CC, 371 : XXX_141
0X900005D0, 372 : XXX_142
0X900005D4, 373 : XXX_143
0X900005D8, 374 : XXX_144
0X900005DC, 375 : XXX_145
0X900005E0, 376 : XXX_146
0X900005E4, 377 : XXX_147
0X900005E8, 378 : XXX_148
0X900005EC, 379 : XXX_149
0X900005F0, 380 : XXX_150
0X900005F4, 381 : XXX_151
0X900005F8, 382 : XXX_152
0X900005FC, 383 : XXX_153
0X90000600, 384 : XXX_154
0X90000604, 385 : XXX_155
0X90000608, 386 : XXX_156
0X9000060C, 387 : XXX_157
0X90000610, 388 : XXX_158
0X90000614, 389 : XXX_159
0X90000618, 390 : XXX_160
0X9000061C, 391 : XXX_161
0X90000620, 392 : XXX_162
0X90000624, 393 : XXX_163
0X90000628, 394 : XXX_164
0X9000062C, 395 : XXX_165
0X90000630, 396 : XXX_166
0X90000634, 397 : XXX_167
0X90000638, 398 : XXX_168
0X9000063C, 399 : XXX_169
0X90000640, 400 : XXX_170
0X90000644, 401 : XXX_171
0X90000648, 402 : XXX_172
0X9000064C, 403 : XXX_173
0X90000650, 404 : XXX_174
0X90000654, 405 : XXX_175
0X90000658, 406 : XXX_176
0X9000065C, 407 : XXX_177
0X90000660, 408 : XXX_178
0X90000664, 409 : XXX_179
0X90000668, 410 : XXX_180
0X9000066C, 411 : XXX_181
0X90000670, 412 : XXX_182
0X90000674, 413 : XXX_183
0X90000678, 414 : XXX_184
0X9000067C, 415 : XXX_185
0X90000680, 416 : XXX_186
0X90000684, 417 : XXX_187
0X90000688, 418 : XXX_188
0X9000068C, 419 : XXX_189
0X90000690, 420 : XXX_190
0X90000694, 421 : XXX_191
0X90000698, 422 : XXX_192
0X9000069C, 423 : XXX_193
0X900006A0, 424 : XXX_194
0X900006A4, 425 : XXX_195
0X900006A8, 426 : XXX_196
0X900006AC, 427 : XXX_197
0X900006B0, 428 : XXX_198
0X900006B4, 429 : XXX_199
0X900006B8, 430 : XXX_200
0X900006BC, 431 : XXX_201
0X900006C0, 432 : XXX_202
0X900006C4, 433 : XXX_203
0X900006C8, 434 : XXX_204
0X900006CC, 435 : XXX_205
0X900006D0, 436 : XXX_206
0X900006D4, 437 : XXX_207
0X900006D8, 438 : XXX_208
0X900006DC, 439 : XXX_209
0X900006E0, 440 : XXX_210
0X900006E4, 441 : XXX_211
0X900006E8, 442 : XXX_212
0X900006EC, 443 : XXX_213
0X900006F0, 444 : XXX_214
0X900006F4, 445 : XXX_215
0X900006F8, 446 : XXX_216
0X900006FC, 447 : XXX_217
0X90000700, 448 : XXX_218
0X90000704, 449 : XXX_219
0X90000708, 450 : XXX_220
0X9000070C, 451 : XXX_221
0X90000710, 452 : XXX_222
0X90000714, 453 : XXX_223
0X90000718, 454 : XXX_224
0X9000071C, 455 : XXX_225
0X90000720, 456 : XXX_226
0X90000724, 457 : mem_test_base
0X90000728, 458 : mem_test_base + 1
0X9000072C, 459 : mem_test_base + 2
0X90000730, 460 : mem_test_base + 3
0X90000734, 461 : mem_test_base + 4
0X90000738, 462 : mem_test_base + 5
0X9000073C, 463 : mem_test_base + 6
0X90000740, 464 : mem_test_base + 7
0X90000744, 465 : mem_test_base + 8
0X90000748, 466 : mem_test_base + 9
0X9000074C, 467 : mem_test_base + 10
0X90000750, 468 : mem_test_base + 11
0X90000754, 469 : mem_test_base + 12
0X90000758, 470 : mem_test_base + 13
0X9000075C, 471 : mem_test_base + 14
0X90000760, 472 : mem_test_base + 15
0X90000764, 473 : mem_test_base + 16
0X90000768, 474 : mem_test_base + 17
0X9000076C, 475 : mem_test_base + 18
0X90000770, 476 : mem_test_base + 19
0X90000774, 477 : mem_test_base + 20
0X90000778, 478 : mem_test_base + 21
0X9000077C, 479 : mem_test_base + 22
0X90000780, 480 : mem_test_base + 23
0X90000784, 481 : mem_test_base + 24
0X90000788, 482 : mem_test_base + 25
0X9000078C, 483 : mem_test_base + 26
0X90000790, 484 : mem_test_base + 27
0X90000794, 485 : mem_test_base + 28
0X90000798, 486 : mem_test_base + 29
0X9000079C, 487 : mem_test_base + 30
0X900007A0, 488 : mem_test_base + 31
0X900007A4, 489 : mem_test_base + 32
0X900007A8, 490 : mem_test_base + 33
0X900007AC, 491 : mem_test_base + 34
0X900007B0, 492 : mem_test_base + 35
0X900007B4, 493 : mem_test_base + 36
0X900007B8, 494 : mem_test_base + 37
0X900007BC, 495 : mem_test_base + 38
0X900007C0, 496 : mem_test_base + 39
0X900007C4, 497 : mem_test_base + 40
0X900007C8, 498 : mem_test_base + 41
0X900007CC, 499 : mem_test_base + 42
0X900007D0, 500 : mem_test_base + 43
0X900007D4, 501 : mem_test_base + 44
0X900007D8, 502 : mem_test_base + 45
0X900007DC, 503 : mem_test_base + 46
0X900007E0, 504 : mem_test_base + 47
0X900007E4, 505 : mem_test_base + 48
0X900007E8, 506 : mem_test_base + 49
0X900007EC, 507 : mem_test_end
0X900007F0, 508 : XXX_1
0X900007F4, 509 : XXX_2
0X900007F8, 510 : XXX_3
0X900007FC, 511 : abs_addr_ceiling
*/
