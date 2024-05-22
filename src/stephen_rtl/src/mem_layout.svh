`ifndef MEM_LAYOUT_PKG_SV
`define MEM_LAYOUT_PKG_SV

    package mem_layout_pkg;
        `define MEM_SIZE              256                                    // Axi Memory map size 
        `define A_BUS_WIDTH           32                                     // Bus width for axi addresses
        `define A_DATA_WIDTH          32                                     // Data width for axi addresses
        `define WD_BUS_WIDTH          32                                     // Bus width for axi data
        `define WD_DATA_WIDTH         16                                     // Data width for axi data
        `define SAMPLE_WIDTH          (`WD_DATA_WIDTH)                       // Bit width of samples (sent to DAC and recived from ADC)
        `define BATCH_WIDTH           (`SAMPLE_WIDTH*16)                     // Batch bits (A batch = the burst of samples sent out to the DAC or recieved from the ADC)
        `define BATCH_SAMPLES         (`BATCH_WIDTH/`SAMPLE_WIDTH)           // # Of samples in a batch
        `define MAX_DAC_BURST_SIZE    32767                                  // Max number of batches that can be burst from the DAC (2**15-1 corresponds to about 85 us)
        `define MAX_SCALE_FACTOR      15                                     // Maximum amount the DAC output can be scaled down by
        `define REQ_BUFFER_SZ         8                                      // Number of processor requests to remember that we would otherwise miss. 
        `define DMA_DATA_WIDTH        (3*`SAMPLE_WIDTH)                      // Bit width of transfers over DMA for the PWL. Each transfer is of the form {time (ns), DAC value, slope}, where slope is r.o.c. between the current point and the next one. The last sample always has a slope of 0 (48).  
        `define MAX_WAVELET_PERIOD    4                                      // Maximum allowable period of pwl wavelet (in microseconds) (should be 20us)
        `define SPARSE_BRAM_DEPTH     600                                    // Corresponding size of PWL wave sparse BRAM buffer, where each line is of size `DMA_DATA_WIDTH
        `define DENSE_BRAM_DEPTH      600                                    // Corresponding size of PWL wave dense BRAM buffer, where each line is of size `BATCH_SAMPLES    
        `define RFDC_CHANNELS         8                                      // Channels of sample discriminator config
        `define SDC_DATA_WIDTH        (2*`RFDC_CHANNELS*`SAMPLE_WIDTH)       // Bit width of sample discriminator config register (256)
        `define SDC_SAMPLES           (`SDC_DATA_WIDTH/`WD_DATA_WIDTH)       // Number of mem_map entries for one sdc value (8)    
        `define BUFF_CONFIG_WIDTH     (2+$clog2($clog2(`RFDC_CHANNELS)+1))   // Bit width of buffer config (4)
        `define FUNCTIONS_PER_CHANNEL 1                                      // Functions per channel, may be increased from 1 to 2 or 3 (1)
        `define CHANNEL_MUX_WIDTH     ($clog2((1+`FUNCTIONS_PER_CHANNEL)*`RFDC_CHANNELS)*`RFDC_CHANNELS) // Bit width for channel mux config register (32)
        `define CHAN_SAMPLES          (`CHANNEL_MUX_WIDTH/`WD_DATA_WIDTH)    // Number of mem_map entries for one channel mux register (2)
        `define BUFF_TIMESTAMP_WIDTH  32                                     // Bit width for buffer timestamp register (32) 
        `define BUFF_SAMPLES          (`BUFF_TIMESTAMP_WIDTH/`WD_DATA_WIDTH) // Number of mem_map entries for one buff_timestamp register (2)
        `define FIRMWARE_VERSION      16'h1_004_3                            // Data Acquisition System (DAS) Version Number: 
                                                                             // _0 => stephen_dev (main) 
                                                                             // _1 => pwl_software_dev 
                                                                             // _2 => pwl_hardware_dev 
                                                                             // _3 => daq_system_overhaul 
                                                                             // _4 => ui_dev
        
        // IDs for internal mem_map usages. Note:
        // RPOLL = RTL_POLL => address is a polling address => after ps writes, freshbits are cleared once the rtl is ready to poll
        // PS_BIGREG = Large registers the ps writes to and rtl reads from (valid addr handled appropriately)
        // RTL_BIGREG = Large registers the rtl writes to and ps reads from (valid addr handled appropriately)
        // READONLY = rtl and ps cannot write to this addr
        `define RST_ID                0                                  // (RPOLL)  Reset register
        `define PS_SEED_BASE_ID       ({$clog2(`MEM_SIZE){1'b0}} + 1)    // (RPOLLs, PS_BIGREG) Register for seeds that will be used by the random signal generator (This and next BATCH_SAMPLES addresses)
        `define PS_SEED_VALID_ID      (`PS_SEED_BASE_ID +`BATCH_SAMPLES) // (RPOLL)  Indicates to rtl that a batch of seeds have been stored. 
        `define TRIG_WAVE_ID          (`PS_SEED_VALID_ID + 1)            // (RPOLL)  Triggers the triangle wave generation 
        `define DAC_HLT_ID            (`PS_SEED_VALID_ID + 2)            // (RPOLL)  Halts the DAC output
        `define DAC_BURST_SIZE_ID     (`PS_SEED_VALID_ID + 3)            // (RPOLL)  Write here to dictate the new number of batches burst from the DAC     
        `define MAX_DAC_BURST_SIZE_ID (`PS_SEED_VALID_ID + 4)            // (READONLY)  stores the maximum number of batches capable of bursting from the DAC
        `define SCALE_DAC_OUT_ID      (`PS_SEED_VALID_ID + 5)            // (RPOLL)  Write here to scale down the output of the DAC (by at most 15). 
        `define DAC1_ID               (`PS_SEED_VALID_ID + 6)            // Traffic here is directed to the first DAC
        `define DAC2_ID               (`PS_SEED_VALID_ID + 7)            // Traffic here is directed to the second DAC
        `define RUN_PWL_ID            (`PS_SEED_VALID_ID + 8)            // (RPOLL)  Run whatever waveform was last saved to the pwl
        `define BUFF_CONFIG_ID        (`PS_SEED_VALID_ID + 9)            // (RPOLL)  Buffer config register
        `define BUFF_TIME_BASE_ID     (`PS_SEED_VALID_ID + 10)           // (RTL_BIGREG) Buffer timestamp base register (This and next BUFF_SAMPLES addresses).
        `define BUFF_TIME_VALID_ID    (`BUFF_TIME_BASE_ID+`BUFF_SAMPLES) // Indicates to rtl that a full buffer timestamp value has been sent to the previous BUFF_SAMPLES address.
        `define CHAN_MUX_BASE_ID      (`BUFF_TIME_VALID_ID + 1)          // (RPOLLs, PS_BIGREG) Channel mux base register (This and next CHAN_SAMPLES addresses) 
        `define CHAN_MUX_VALID_ID     (`CHAN_MUX_BASE_ID+`CHAN_SAMPLES)  // (RPOLL)  Indicates to rtl that a full channel mux value has been sent to the previous CHAN_SAMPLES address.
        `define SDC_BASE_ID           (`CHAN_MUX_VALID_ID + 1)           // (RPOLLs, PS_BIGREG) Sample discriminator base register (This and next SDC_SAMPLES addresses)
        `define SDC_VALID_ID          (`SDC_BASE_ID + `SDC_SAMPLES)      // (RPOLL)  Indicates to rtl that a full sdc value has been sent to the previous SDC_SAMPLES address.  
        `define VERSION_ID            (`SDC_VALID_ID + 1)                // (READONLY) Reports the firmware version
        `define MEM_SIZE_ID           (`SDC_VALID_ID + 2)                // (READONLY)  stores the memory size. 
        `define MAPPED_ID_CEILING     (`MEM_SIZE_ID + 1)                 // Top of mapped memory IDs
        `define MEM_TEST_BASE_ID      (`MEM_SIZE - 55)                   // The next 50 addresses are reserved for memory testing 
        `define MEM_TEST_END_ID       (`MEM_TEST_BASE_ID + 50)           // End of Memory testing
        `define ABS_ID_CEILING        (`MEM_SIZE - 1)                    // (READONLY)  The highest entry in the mem-map, contains -2

        // Addresses for external mem_map usages
        `define PS_BASE_ADDR            32'h9000_0000 
        `define RST_ADDR                (`PS_BASE_ADDR)
        `define PS_SEED_BASE_ADDR       (`RST_ADDR + 4)
        `define PS_SEED_VALID_ADDR      (`PS_SEED_BASE_ADDR + 4 * (`BATCH_SAMPLES))
        `define TRIG_WAVE_ADDR          (`PS_SEED_VALID_ADDR + 4)
        `define DAC_HLT_ADDR            (`PS_SEED_VALID_ADDR + 4*2)
        `define DAC_BURST_SIZE_ADDR     (`PS_SEED_VALID_ADDR + 4*3)
        `define MAX_DAC_BURST_SIZE_ADDR (`PS_SEED_VALID_ADDR + 4*4)
        `define SCALE_DAC_OUT_ADDR      (`PS_SEED_VALID_ADDR + 4*5)
        `define DAC1_ADDR               (`PS_SEED_VALID_ADDR + 4*6)
        `define DAC2_ADDR               (`PS_SEED_VALID_ADDR + 4*7)
        `define RUN_PWL_ADDR            (`PS_SEED_VALID_ADDR + 4*8)
        `define BUFF_CONFIG_ADDR        (`PS_SEED_VALID_ADDR + 4*9)
        `define BUFF_TIME_BASE_ADDR     (`PS_SEED_VALID_ADDR + 4*10)
        `define BUFF_TIME_VALID_ADDR    (`BUFF_TIME_BASE_ADDR + 4*(`BUFF_SAMPLES))
        `define CHAN_MUX_BASE_ADDR      (`BUFF_TIME_VALID_ADDR + 4)
        `define CHAN_MUX_VALID_ADDR     (`CHAN_MUX_BASE_ADDR + 4*(`CHAN_SAMPLES))
        `define SDC_BASE_ADDR           (`CHAN_MUX_VALID_ADDR + 4)
        `define SDC_VALID_ADDR          (`SDC_BASE_ADDR + 4*(`SDC_SAMPLES))
        `define VERSION_ADDR            (`SDC_VALID_ADDR + 4)
        `define MEM_SIZE_ADDR           (`SDC_VALID_ADDR + 4*2)
        `define MAPPED_ADDR_CEILING     (`MEM_SIZE_ADDR + 4)
        `define MEM_TEST_BASE_ADDR      (`PS_BASE_ADDR + 4*(`MEM_SIZE - 55))
        `define MEM_TEST_END_ADDR       (`MEM_TEST_BASE_ADDR + 4*50)
        `define ABS_ADDR_CEILING        (`PS_BASE_ADDR + 4*(`MEM_SIZE-1))

        `define ADDR_NUM                20

        // Codes for responses sent to processor 
        `define OKAY   2'b00 // General signal for a successful transaction (or that an exclusive access failed)
        `define EXOKAY 2'b01 // Either the write OR read was okay
        `define SLVERR 2'b10 // Transaction recieved but error in execution
        `define DECERR 2'b11 // No slave at transaction address

        logic[`ADDR_NUM-1:0][31:0] addrs = {32'(`MEM_SIZE_ADDR), 32'(`VERSION_ADDR), 32'(`SDC_VALID_ADDR), 32'(`SDC_BASE_ADDR), 32'(`CHAN_MUX_VALID_ADDR), 32'(`CHAN_MUX_BASE_ADDR), 32'(`BUFF_TIME_VALID_ADDR), 32'(`BUFF_TIME_BASE_ADDR), 32'(`BUFF_CONFIG_ADDR), 32'(`RUN_PWL_ADDR), 32'(`DAC2_ADDR), 32'(`DAC1_ADDR), 32'(`SCALE_DAC_OUT_ADDR), 32'(`MAX_DAC_BURST_SIZE_ADDR), 32'(`DAC_BURST_SIZE_ADDR), 32'(`DAC_HLT_ADDR), 32'(`TRIG_WAVE_ADDR), 32'(`PS_SEED_VALID_ADDR), 32'(`PS_SEED_BASE_ADDR), 32'(`RST_ADDR)};
        logic[`ADDR_NUM-1:0][31:0] ids   = {32'(`MEM_SIZE_ID), 32'(`VERSION_ID), 32'(`SDC_VALID_ID), 32'(`SDC_BASE_ID), 32'(`CHAN_MUX_VALID_ID), 32'(`CHAN_MUX_BASE_ID), 32'(`BUFF_TIME_VALID_ID), 32'(`BUFF_TIME_BASE_ID), 32'(`BUFF_CONFIG_ID), 32'(`RUN_PWL_ID), 32'(`DAC2_ID), 32'(`DAC1_ID), 32'(`SCALE_DAC_OUT_ID), 32'(`MAX_DAC_BURST_SIZE_ID), 32'(`DAC_BURST_SIZE_ID), 32'(`DAC_HLT_ID), 32'(`TRIG_WAVE_ID), 32'(`PS_SEED_VALID_ID), 32'(`PS_SEED_BASE_ID), 32'(`RST_ID)};

        `define flash_sig(sig) sig = 1; #10; sig = 0; #10;
        `define flash_signal(sig,clk) sig <= 1; @(posedge clk); sig <= 0; @(posedge clk);
        `define ADDR2ID(addr)        ((addr - `PS_BASE_ADDR) >> 2)
        `define ID2ADDR(index)       ((index << 2) + `PS_BASE_ADDR)
        /*
        is_RTLPOLL => regs where rtl only reads from and ps writes to. 
        is_PS_BIGREG => large regs the processor writes to and rtl reads from
        is_RTL_BIGREG => large regs the rtl writes to and ps reads from
        is_PS_VALID => the valid signal for large regs of type PS_BIGREG
        is_RTL_VALID => the valid signal for large regs of type RTL_BIGREG
        */
        `define is_READONLY(index)   (index == `MAX_DAC_BURST_SIZE_ID || index == `VERSION_ID || index == `MEM_SIZE_ID ||  (index >= `MAPPED_ID_CEILING && index < `MEM_TEST_BASE_ID) || (index >= `MEM_TEST_BASE_ID+50 && index < `ABS_ID_CEILING) || index == `ABS_ID_CEILING)
        `define is_RTLPOLL(index)    (index == `RST_ID || (index >= `PS_SEED_BASE_ID && index <= `PS_SEED_VALID_ID) || index == `TRIG_WAVE_ID || index == `DAC_HLT_ID ||index == `RUN_PWL_ID || index == `DAC_BURST_SIZE_ID || index == `SCALE_DAC_OUT_ID || index == `BUFF_CONFIG_ID || (index >= `CHAN_MUX_BASE_ID && index <= `CHAN_MUX_VALID_ID)  || (index >= `SDC_BASE_ID && index <= `SDC_VALID_ID))
        `define is_PS_BIGREG(index)  ((index >= `PS_SEED_BASE_ID && index <= `PS_SEED_VALID_ID) || (index >= `CHAN_MUX_BASE_ID && index <= `CHAN_MUX_VALID_ID)  || (index >= `SDC_BASE_ID && index <= `SDC_VALID_ID))
        `define is_RTL_BIGREG(index) (index >= `BUFF_TIME_BASE_ID && index <= `BUFF_TIME_VALID_ID) 
        `define is_PS_VALID(index)   (index == `PS_SEED_VALID_ID || index == `CHAN_MUX_VALID_ID  || index == `SDC_VALID_ID)
        `define is_RTL_VALID(index)  (index == `BUFF_TIME_VALID_ID)
        
    endpackage 


`endif


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
buff_config         <=> 0x90000068 
buff_time_base      <=> 0x9000006c 
buff_time_valid     <=> 0x90000074 
chan_mux_base       <=> 0x90000078 
chan_mux_valid      <=> 0x90000080 
sdc_base            <=> 0x90000084 
sdc_valid           <=> 0x900000c4 
firmware_version    <=> 0x900000c8 
mem_size            <=> 0x900000cc 
mapped_addr_ceiling <=> 0x900000d0 
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
buff_config         <=> 26 
buff_time_base      <=> 27 
buff_time_valid     <=> 29 
chan_mux_base       <=> 30 
chan_mux_valid      <=> 32 
sdc_base            <=> 33 
sdc_valid           <=> 49 
firmware_version    <=> 50 
mem_size            <=> 51 
mapped_addr_ceiling <=> 52 
mem_test_base       <=> 201 
mem_test_end        <=> 251 
abs_addr_ceiling    <=> 255 
*/
