`default_nettype none
`timescale 1ns / 1ps

`ifndef MEM_LAYOUT_PKG_SV
`define MEM_LAYOUT_PKG_SV

    package mem_layout_pkg;
        import axi_params_pkg::A_DATA_WIDTH;
        localparam MEM_SIZE      = 256;              // Axi Memory map size
        localparam MEM_WIDTH     = $clog2(MEM_SIZE); // Memory size bit width
        // IDs for internal mem_map usages. Note:
        // RPOLL = RTL_POLL => address is a polling address => after ps writes, freshbits are cleared once the rtl is ready to poll
        // PS_BIGREG = Large registers the ps writes to and rtl reads from (valid addr handled appropriately)
        // RTL_BIGREG = Large registers the rtl writes to and ps reads from (valid addr handled appropriately and when needed)
        // READONLY = rtl and ps cannot write to this addr
        localparam  logic[MEM_WIDTH-1:0] RST_ID                = {MEM_WIDTH{1'b0}};                                  // (RPOLL)  Reset register
        localparam  logic[MEM_WIDTH-1:0] PS_SEED_BASE_ID       = RST_ID + 1;                                         // (RPOLLs, PS_BIGREG) Register for seeds that will be used by the random signal generator (This and next BATCH_SIZE addresses)
        localparam  logic[MEM_WIDTH-1:0] PS_SEED_VALID_ID      = PS_SEED_BASE_ID + (daq_params_pkg::BATCH_SIZE);  // (RPOLL)  Indicates to rtl that a batch of seeds have been stored. 
        localparam  logic[MEM_WIDTH-1:0] TRIG_WAVE_ID          = PS_SEED_VALID_ID + 1;                               // (RPOLL)  Triggers the triangle wave generation 
        localparam  logic[MEM_WIDTH-1:0] DAC_HLT_ID            = PS_SEED_VALID_ID + 2;                               // (RPOLL)  Halts the DAC output
        localparam  logic[MEM_WIDTH-1:0] DAC_BURST_SIZE_ID     = PS_SEED_VALID_ID + 3;                               // (RPOLL)  Write here to dictate the new number of batches burst from the DAC     
        localparam  logic[MEM_WIDTH-1:0] MAX_DAC_BURST_SIZE_ID = PS_SEED_VALID_ID + 4;                               // (READONLY)  stores the maximum number of batches capable of bursting from the DAC
        localparam  logic[MEM_WIDTH-1:0] SCALE_DAC_OUT_ID      = PS_SEED_VALID_ID + 5;                               // (RPOLL)  Write here to scale down the output of the DAC (by at most 15). 
        localparam  logic[MEM_WIDTH-1:0] DAC1_ID               = PS_SEED_VALID_ID + 6;                               // Traffic here is directed to the first DAC
        localparam  logic[MEM_WIDTH-1:0] DAC2_ID               = PS_SEED_VALID_ID + 7;                               // Traffic here is directed to the second DAC
        localparam  logic[MEM_WIDTH-1:0] RUN_PWL_ID            = PS_SEED_VALID_ID + 8;                               // (RPOLL)  Run whatever waveform was last saved to the pwl
        localparam  logic[MEM_WIDTH-1:0] PWL_PERIOD0_ID        = PS_SEED_VALID_ID + 9;                               // (RTL_BIGREG) stores the lower bits of the current pwl wave period 
        localparam  logic[MEM_WIDTH-1:0] PWL_PERIOD1_ID        = PS_SEED_VALID_ID + 10;                              // (RTL_BIGREG) stores the upper bits of the current pwl wave period 
        localparam  logic[MEM_WIDTH-1:0] BUFF_CONFIG_ID        = PS_SEED_VALID_ID + 11;                              // (RPOLL)  Buffer config register
        localparam  logic[MEM_WIDTH-1:0] BUFF_TIME_BASE_ID     = PS_SEED_VALID_ID + 12;                              // (RTL_BIGREG) Buffer timestamp base register (This and next BUFF_SAMPLES addresses).
        localparam  logic[MEM_WIDTH-1:0] BUFF_TIME_VALID_ID    = BUFF_TIME_BASE_ID + (daq_params_pkg::BUFF_SAMPLES); // Indicates to rtl that a full buffer timestamp value has been sent to the previous BUFF_SAMPLES address.
        localparam  logic[MEM_WIDTH-1:0] CHAN_MUX_BASE_ID      = BUFF_TIME_VALID_ID + 1;                             // (RPOLLs, PS_BIGREG) Channel mux base register (This and next CHAN_SAMPLES addresses) 
        localparam  logic[MEM_WIDTH-1:0] CHAN_MUX_VALID_ID     = CHAN_MUX_BASE_ID + (daq_params_pkg::CHAN_SAMPLES);  // (RPOLL)  Indicates to rtl that a full channel mux value has been sent to the previous CHAN_SAMPLES address.
        localparam  logic[MEM_WIDTH-1:0] SDC_BASE_ID           = CHAN_MUX_VALID_ID + 1;                              // (RPOLLs, PS_BIGREG) Sample discriminator base register (This and next SDC_SAMPLES addresses)
        localparam  logic[MEM_WIDTH-1:0] SDC_VALID_ID          = SDC_BASE_ID +  (daq_params_pkg::SDC_SAMPLES);       // (RPOLL)  Indicates to rtl that a full sdc value has been sent to the previous SDC_SAMPLES address.  
        localparam  logic[MEM_WIDTH-1:0] VERSION_ID            = SDC_VALID_ID + 1;                                   // (READONLY) Reports the firmware version
        localparam  logic[MEM_WIDTH-1:0] MEM_SIZE_ID           = SDC_VALID_ID + 2;                                   // (READONLY)  stores the memory size. 
        localparam  logic[MEM_WIDTH-1:0] MAPPED_ID_CEILING     = MEM_SIZE_ID + 1;                                    // Top of mapped memory IDs
        localparam  logic[MEM_WIDTH-1:0] MEM_TEST_BASE_ID      = MEM_SIZE - 55;                                      // The next 50 addresses are reserved for memory testing 
        localparam  logic[MEM_WIDTH-1:0] MEM_TEST_END_ID       = MEM_TEST_BASE_ID + 50;                              // (READONLY) End of Memory testing
        localparam  logic[MEM_WIDTH-1:0] ABS_ID_CEILING        = MEM_SIZE - 1;                                       // (READONLY)  The highest entry in the mem-map, contains -2
        
        // Addresses for external mem_map usages
        localparam logic[A_DATA_WIDTH-1:0] PS_BASE_ADDR            = 32'h9000_0000;
        localparam logic[A_DATA_WIDTH-1:0] RST_ADDR                = PS_BASE_ADDR;
        localparam logic[A_DATA_WIDTH-1:0] PS_SEED_BASE_ADDR       = RST_ADDR + 4;
        localparam logic[A_DATA_WIDTH-1:0] PS_SEED_VALID_ADDR      = PS_SEED_BASE_ADDR + 4 * (daq_params_pkg::BATCH_SIZE);
        localparam logic[A_DATA_WIDTH-1:0] TRIG_WAVE_ADDR          = PS_SEED_VALID_ADDR + 4;
        localparam logic[A_DATA_WIDTH-1:0] DAC_HLT_ADDR            = PS_SEED_VALID_ADDR + 4*2;
        localparam logic[A_DATA_WIDTH-1:0] DAC_BURST_SIZE_ADDR     = PS_SEED_VALID_ADDR + 4*3;
        localparam logic[A_DATA_WIDTH-1:0] MAX_DAC_BURST_SIZE_ADDR = PS_SEED_VALID_ADDR + 4*4;
        localparam logic[A_DATA_WIDTH-1:0] SCALE_DAC_OUT_ADDR      = PS_SEED_VALID_ADDR + 4*5;
        localparam logic[A_DATA_WIDTH-1:0] DAC1_ADDR               = PS_SEED_VALID_ADDR + 4*6;
        localparam logic[A_DATA_WIDTH-1:0] DAC2_ADDR               = PS_SEED_VALID_ADDR + 4*7;
        localparam logic[A_DATA_WIDTH-1:0] RUN_PWL_ADDR            = PS_SEED_VALID_ADDR + 4*8;
        localparam logic[A_DATA_WIDTH-1:0] PWL_PERIOD0_ADDR        = PS_SEED_VALID_ADDR + 4*9;
        localparam logic[A_DATA_WIDTH-1:0] PWL_PERIOD1_ADDR        = PS_SEED_VALID_ADDR + 4*10;
        localparam logic[A_DATA_WIDTH-1:0] BUFF_CONFIG_ADDR        = PS_SEED_VALID_ADDR + 4*11;
        localparam logic[A_DATA_WIDTH-1:0] BUFF_TIME_BASE_ADDR     = PS_SEED_VALID_ADDR + 4*12;
        localparam logic[A_DATA_WIDTH-1:0] BUFF_TIME_VALID_ADDR    = BUFF_TIME_BASE_ADDR + 4 * (daq_params_pkg::BUFF_SAMPLES);
        localparam logic[A_DATA_WIDTH-1:0] CHAN_MUX_BASE_ADDR      = BUFF_TIME_VALID_ADDR + 4;
        localparam logic[A_DATA_WIDTH-1:0] CHAN_MUX_VALID_ADDR     = CHAN_MUX_BASE_ADDR + 4 * (daq_params_pkg::CHAN_SAMPLES);
        localparam logic[A_DATA_WIDTH-1:0] SDC_BASE_ADDR           = CHAN_MUX_VALID_ADDR + 4;
        localparam logic[A_DATA_WIDTH-1:0] SDC_VALID_ADDR          = SDC_BASE_ADDR + 4 * (daq_params_pkg::SDC_SAMPLES);
        localparam logic[A_DATA_WIDTH-1:0] VERSION_ADDR            = SDC_VALID_ADDR + 4;
        localparam logic[A_DATA_WIDTH-1:0] MEM_SIZE_ADDR           = SDC_VALID_ADDR + 4*2;
        localparam logic[A_DATA_WIDTH-1:0] MAPPED_ADDR_CEILING     = MEM_SIZE_ADDR + 4;
        localparam logic[A_DATA_WIDTH-1:0] MEM_TEST_BASE_ADDR      = PS_BASE_ADDR + 4*(MEM_SIZE - 55);
        localparam logic[A_DATA_WIDTH-1:0] MEM_TEST_END_ADDR       = MEM_TEST_BASE_ADDR + 4*50;
        localparam logic[A_DATA_WIDTH-1:0] ABS_ADDR_CEILING        = PS_BASE_ADDR + 4*(MEM_SIZE-1);

        localparam ADDR_NUM = 22; 
        logic[ADDR_NUM-1:0][A_DATA_WIDTH-1:0] addrs = {MEM_SIZE_ADDR, VERSION_ADDR, SDC_VALID_ADDR, SDC_BASE_ADDR, CHAN_MUX_VALID_ADDR, CHAN_MUX_BASE_ADDR, BUFF_TIME_VALID_ADDR, BUFF_TIME_BASE_ADDR, BUFF_CONFIG_ADDR, PWL_PERIOD1_ADDR, PWL_PERIOD0_ADDR, RUN_PWL_ADDR, DAC2_ADDR, DAC1_ADDR, SCALE_DAC_OUT_ADDR, MAX_DAC_BURST_SIZE_ADDR, DAC_BURST_SIZE_ADDR, DAC_HLT_ADDR, TRIG_WAVE_ADDR, PS_SEED_VALID_ADDR, PS_SEED_BASE_ADDR, RST_ADDR};
        logic[ADDR_NUM-1:0][MEM_WIDTH-1:0] ids = {MEM_SIZE_ID, VERSION_ID, SDC_VALID_ID, SDC_BASE_ID, CHAN_MUX_VALID_ID, CHAN_MUX_BASE_ID, BUFF_TIME_VALID_ID, BUFF_TIME_BASE_ID, BUFF_CONFIG_ID, PWL_PERIOD1_ID, PWL_PERIOD0_ID, RUN_PWL_ID, DAC2_ID, DAC1_ID, SCALE_DAC_OUT_ID, MAX_DAC_BURST_SIZE_ID, DAC_BURST_SIZE_ID, DAC_HLT_ID, TRIG_WAVE_ID, PS_SEED_VALID_ID, PS_SEED_BASE_ID, RST_ID};

        // Useful functions
        function logic[MEM_WIDTH-1:0] ADDR2ID(logic[A_DATA_WIDTH-1:0] addr);
             return (addr - PS_BASE_ADDR) >> 2;
        endfunction  
        function logic[A_DATA_WIDTH-1:0] ID2ADDR(logic[MEM_WIDTH-1:0] index);
             return (index << 2) + PS_BASE_ADDR;
        endfunction  
        /*
        is_READONLY => regs the ps can only read from (rtl can write)
        is_RTLPOLL => regs where rtl only reads from and ps writes to. 
        is_PS_BIGREG => large regs the processor writes to and rtl reads from
        is_RTL_BIGREG => large regs the rtl writes to and ps reads from
        is_PS_VALID => the valid signal for large regs of type PS_BIGREG
        is_RTL_VALID => the valid signal for large regs of type RTL_BIGREG
        */
        function bit is_READONLY(logic[MEM_WIDTH-1:0] index);
             return index == MAX_DAC_BURST_SIZE_ID || index == VERSION_ID || index == MEM_SIZE_ID ||  (index >= MAPPED_ID_CEILING && index < MEM_TEST_BASE_ID) || (index >= MEM_TEST_END_ID && index < ABS_ID_CEILING) || index == ABS_ID_CEILING;
        endfunction
        function bit is_RTLPOLL(logic[MEM_WIDTH-1:0] index);
             return index == RST_ID || (index >= PS_SEED_BASE_ID && index <= PS_SEED_VALID_ID) || index == TRIG_WAVE_ID || index == DAC_HLT_ID ||index == RUN_PWL_ID || index == DAC_BURST_SIZE_ID || index == SCALE_DAC_OUT_ID || index == BUFF_CONFIG_ID || (index >= CHAN_MUX_BASE_ID && index <= CHAN_MUX_VALID_ID)  || (index >= SDC_BASE_ID && index <= SDC_VALID_ID);
        endfunction
        function bit is_PS_BIGREG(logic[MEM_WIDTH-1:0] index);
             return (index >= PS_SEED_BASE_ID && index <= PS_SEED_VALID_ID) || (index >= CHAN_MUX_BASE_ID && index <= CHAN_MUX_VALID_ID)  || (index >= SDC_BASE_ID && index <= SDC_VALID_ID);
        endfunction
        function bit is_RTL_BIGREG(logic[MEM_WIDTH-1:0] index);
             return (index >= BUFF_TIME_BASE_ID && index <= BUFF_TIME_VALID_ID) || index == PWL_PERIOD1_ID || index == PWL_PERIOD0_ID;
        endfunction
        function bit is_PS_VALID(logic[MEM_WIDTH-1:0] index);
             return index == PS_SEED_VALID_ID || index == CHAN_MUX_VALID_ID  || index == SDC_VALID_ID;
        endfunction
        function bit is_RTL_VALID(logic[MEM_WIDTH-1:0] index);
             return index == BUFF_TIME_VALID_ID;
        endfunction
        
    endpackage 

`endif

`default_nettype wire


/*
Processor MMIO Addresses:
rst                 <=> 0x90000000 
seed_base           <=> 0x90000004 
seed_valid          <=> 0x90000044 
triangle_wave       <=> 0x90000048 
hlt_dac             <=> 0x9000004c 
dac_burst_size      <=> 0x90000050 
max_dac_burst_size  <=> 0x90000054 
scale_dac_out       <=> 0x90000058 
dac1                <=> 0x9000005c 
dac2                <=> 0x90000060 
run_pwl             <=> 0x90000064 
pwl_period0         <=> 0x90000068 
pwl_period1         <=> 0x9000006c 
buff_config         <=> 0x90000070 
buff_time_base      <=> 0x90000074 
buff_time_valid     <=> 0x9000007c 
chan_mux_base       <=> 0x90000080 
chan_mux_valid      <=> 0x90000088 
sdc_base            <=> 0x9000008c 
sdc_valid           <=> 0x900000cc 
firmware_version    <=> 0x900000d0 
mem_size            <=> 0x900000d4 
mapped_addr_ceiling <=> 0x900000d8 
mem_test_base       <=> 0x90000324 
mem_test_end        <=> 0x900003ec 
abs_addr_ceiling    <=> 0x900003fc 

RTL MMIO Indices:
rst                 <=> 0 
seed_base           <=> 1 
seed_valid          <=> 17 
triangle_wave       <=> 18 
hlt_dac             <=> 19 
dac_burst_size      <=> 20 
max_dac_burst_size  <=> 21 
scale_dac_out       <=> 22 
dac1                <=> 23 
dac2                <=> 24 
run_pwl             <=> 25 
pwl_period0         <=> 26 
pwl_period1         <=> 27 
buff_config         <=> 28 
buff_time_base      <=> 29 
buff_time_valid     <=> 31 
chan_mux_base       <=> 32 
chan_mux_valid      <=> 34 
sdc_base            <=> 35 
sdc_valid           <=> 51 
firmware_version    <=> 52 
mem_size            <=> 53 
mapped_addr_ceiling <=> 54 
mem_test_base       <=> 201 
mem_test_end        <=> 251 
abs_addr_ceiling    <=> 255 
*/
