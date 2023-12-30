`ifndef MEM_LAYOUT_PKG_SV
`define MEM_LAYOUT_PKG_SV

    package mem_layout_pkg;
        `define MEM_SIZE            256                                  // Axi Memory map size 
        `define A_BUS_WIDTH         32                                   // Bus width for axi addresses
        `define A_DATA_WIDTH        32                                   // Data width for axi addresses
        `define WD_BUS_WIDTH        32                                   // Bus width for axi data
        `define WD_DATA_WIDTH       16                                   // Data width for axi data
        `define SAMPLE_WIDTH        16                                   // Bit width of samples (sent to DAC and recived from ADC)
        `define BATCH_WIDTH         4 * `SAMPLE_WIDTH * `WD_DATA_WIDTH   // Batch bits (A batch = the burst of samples sent out to the DAC or recieved from the ADC)
        `define BATCH_SAMPLES       `BATCH_WIDTH / `SAMPLE_WIDTH         // # Of samples in a batch
        `define MAX_ILA_BURST_SIZE  20                                   // Dictates the max number of batches we save on the ila (375 lenght gives 25,000 samples)
        `define REQ_BUFFER_SZ       8                                    // Dictates the number of processor requests to remember that we would otherwise miss. 
        `define DMA_DATA_WIDTH      3*`SAMPLE_WIDTH                      // Dicates the bit width of transfers over DMA for the PWL. Each transfer is of the form {time (ns), DAC value, slope}, where slope is r.o.c. between the current point and the next one. The last sample always has a slope of 0. 
        `define MAX_WAVELET_PERIOD  4                                    // Maximum allowable period of pwl wavelet (in microseconds) (should be 20us)
        `define PWL_BRAM_DEPTH      600                                  // Corresponding size of PWL wave BRAM buffer, where each line is of size BATCH_WIDTH (should be 3000 for 20us)    

        // IDs for internal mem_map usages
        `define RST_ID                0                                  // Writing here signals the system to reset
        `define PS_SEED_BASE_ID       {$clog2(`MEM_SIZE){1'b0}} + 1      // Write here and the next x number of addresses (where x = the number of samples in one batch) to store the seeds that will be used by the random signal generator 
        `define PS_SEED_VALID_ID      `PS_SEED_BASE_ID + `BATCH_SAMPLES  // Write here to indicate to the rtl that a batch of seeds have been stored. 
        `define TRIG_WAVE_ID          `PS_SEED_VALID_ID + 1              // Write here to trigger the triangle wave generation 
        `define DAC_HLT_ID            `PS_SEED_VALID_ID + 2              // Write here to halt the DAC output
        `define DAC_ILA_TRIG_ID       `PS_SEED_VALID_ID + 3              // Write here to trigger the ila that tracks at most MAX_ILA_BURST_SIZE batches coming out of the dac. 
        `define DAC_ILA_RESP_ID       `PS_SEED_VALID_ID + 4              // PS reads from here to grab samples stored by the dac_ila. 
        `define DAC_ILA_RESP_VALID_ID `PS_SEED_VALID_ID + 5              // PS reads from here to see if a new sample was stored. 
        `define ILA_BURST_SIZE_ID     `PS_SEED_VALID_ID + 6              // Write here to dictate the new number of batches saved bythe dac_ila     
        `define MAX_BURST_SIZE_ID     `PS_SEED_VALID_ID + 7              // READONLY: stores the maximum number of lines the ILA is capable of saving.   
        `define SCALE_DAC_OUT_ID      `PS_SEED_VALID_ID + 8              // Write here to scale down the output of the DAC (by at most 15). 
        `define DAC1_ID               `PS_SEED_VALID_ID + 9              // Traffic here is directed to the first DAC
        `define DAC2_ID               `PS_SEED_VALID_ID + 10             // Traffic here is directed to the second DAC
        `define PWL_PREP_ID           `PS_SEED_VALID_ID + 11             // Signals to the PWL generator to expect a burst of tuples upon which a waveform should be constructed. 
        `define RUN_PWL_ID            `PS_SEED_VALID_ID + 12             // Run whatever waveform was last saved to the pwl
        `define MEM_SIZE_ID           `PS_SEED_VALID_ID + 13             // READONLY: stores the memory size. 
        `define MAPPED_ID_CEILING     `MEM_SIZE_ID + 1                   // Top of mapped memory IDs
        `define MEM_TEST_BASE_ID      `MEM_SIZE - 55                     // The top 50 addresses are reserved for memory testing 
        `define ABS_ID_CEILING        `MEM_SIZE - 1                      // READONLY: The highest entry in the mem-map, contains -1

        // Addresses for external mem_map usages
        `define PS_BASE_ADDR            32'h9000_0000 
        `define RST_ADDR                `PS_BASE_ADDR 
        `define PS_SEED_BASE_ADDR       `RST_ADDR + 4                                   
        `define PS_SEED_VALID_ADDR      `PS_SEED_BASE_ADDR + 4 * (`BATCH_WIDTH/`SAMPLE_WIDTH)  
        `define TRIG_WAVE_ADDR          `PS_SEED_VALID_ADDR + 4 
        `define DAC_HLT_ADDR            `PS_SEED_VALID_ADDR + 4*2 
        `define DAC_ILA_TRIG_ADDR       `PS_SEED_VALID_ADDR + 4*3 
        `define DAC_ILA_RESP_ADDR       `PS_SEED_VALID_ADDR + 4*4
        `define DAC_ILA_RESP_VALID_ADDR `PS_SEED_VALID_ADDR + 4*5
        `define ILA_BURST_SIZE_ADDR     `PS_SEED_VALID_ADDR + 4*6
        `define MAX_BURST_SIZE_ADDR     `PS_SEED_VALID_ADDR + 4*7
        `define SCALE_DAC_OUT_ADDR      `PS_SEED_VALID_ADDR + 4*8
        `define DAC1_ADDR               `PS_SEED_VALID_ADDR + 4*9
        `define DAC2_ADDR               `PS_SEED_VALID_ADDR + 4*10
        `define PWL_PREP_ADDR           `PS_SEED_VALID_ADDR + 4*11
        `define RUN_PWL_ADDR            `PS_SEED_VALID_ADDR + 4*12
        `define MEM_SIZE_ADDR           `PS_SEED_VALID_ADDR + 4*13
        `define MAPPED_ADDR_CEILING     `MEM_SIZE_ADDR + 4                      
        `define MEM_TEST_BASE_ADDR      `PS_BASE_ADDR + 4*(`MEM_SIZE - 55)  
        `define ABS_ADDR_CEILING        `PS_BASE_ADDR + 4*(`MEM_SIZE-1)

        `define ADDR_NUM                16

        // Codes for responses sent to processor 
        `define OKAY   2'b00 // General signal for a successful transaction (or that an exclusive access failed)
        `define EXOKAY 2'b01 // Either the write OR read was okay
        `define SLVERR 2'b10 // Transaction recieved but error in execution
        `define DECERR 2'b11 // No slave at transaction address

        logic[`ADDR_NUM-1:0][31:0] addrs = {32'(`MEM_SIZE_ADDR), 32'(`RUN_PWL_ADDR), 32'(`PWL_PREP_ADDR), 32'(`DAC2_ADDR), 32'(`DAC1_ADDR), 32'(`SCALE_DAC_OUT_ADDR), 32'(`MAX_BURST_SIZE_ADDR), 32'(`ILA_BURST_SIZE_ADDR), 32'(`DAC_ILA_RESP_VALID_ADDR), 32'(`DAC_ILA_RESP_ADDR), 32'(`DAC_ILA_TRIG_ADDR), 32'(`DAC_HLT_ADDR), 32'(`TRIG_WAVE_ADDR), 32'(`PS_SEED_VALID_ADDR), 32'(`PS_SEED_BASE_ADDR), 32'(`RST_ADDR)};
        logic[`ADDR_NUM-1:0][31:0] ids = {32'(`MEM_SIZE_ID), 32'(`RUN_PWL_ID), 32'(`PWL_PREP_ID), 32'(`DAC2_ID), 32'(`DAC1_ID), 32'(`SCALE_DAC_OUT_ID), 32'(`MAX_BURST_SIZE_ID), 32'(`ILA_BURST_SIZE_ID), 32'(`DAC_ILA_RESP_VALID_ID), 32'(`DAC_ILA_RESP_ID), 32'(`DAC_ILA_TRIG_ID), 32'(`DAC_HLT_ID), 32'(`TRIG_WAVE_ID), 32'(`PS_SEED_VALID_ID), 32'(`PS_SEED_BASE_ID), 32'(`RST_ID)};
        `define flash_sig(sig) sig = 1; #10; sig = 0; #10;
    endpackage 

`endif


/*
Processor MMIO Addresses:
rst                 => 0x90000000 
seed_base           => 0x90000004 
seed_valid          => 0x90000104 
triangle_wave       => 0x90000108 
hlt_dac             => 0x9000010c 
set_trigger         => 0x90000110 
ila_resp            => 0x90000114 
ila_resp_valid      => 0x90000118 
ila_burst_size      => 0x9000011c 
max_burst_size      => 0x90000120 
scale_dac_out       => 0x90000124 
dac1                => 0x90000128 
dac2                => 0x9000012c 
pwl_prep            => 0x90000130 
run_pwl             => 0x90000134 
mem_size            => 0x90000138 
mapped_addr_ceiling => 0x9000013c 
mem_test_base       => 0x90000324 
abs_addr_ceiling    => 0x900003fc 
                      

RTL MMIO Indiceis:
rst                 => 0 
seed_base           => 1 
seed_valid          => 65 
triangle_wave       => 66 
hlt_dac             => 67 
set_trigger         => 68 
ila_resp            => 69 
ila_resp_valid      => 70 
ila_burst_size      => 71 
max_burst_size      => 72 
scale_dac_out       => 73 
dac1                => 74 
dac2                => 75 
pwl_prep            => 76 
run_pwl             => 77 
mem_size            => 78 
mapped_addr_ceiling => 79 
mem_test_base       => 201 
abs_addr_ceiling    => 255 
*/
