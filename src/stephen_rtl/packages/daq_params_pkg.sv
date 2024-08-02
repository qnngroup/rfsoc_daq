`ifndef DAQ_PARAMS_PKG_SV
`define DAQ_PARAMS_PKG_SV

    package daq_params_pkg;
        localparam SAMPLE_WIDTH          = axi_params_pkg::WD_DATA_WIDTH;                                   // Bit width of samples (sent to DAC and recived from ADC)
        localparam BATCH_WIDTH           = SAMPLE_WIDTH*16;                                                 // Batch bits (A batch = the burst of samples sent out to the DAC or recieved from the ADC)
        localparam BATCH_SIZE            = BATCH_WIDTH/SAMPLE_WIDTH;                                        // # Of samples in a batch
        localparam MAX_DAC_BURST_SIZE    = 32767;                                                           // Max number of batches that can be burst from the DAC (2**15-1 corresponds to about 85 us)
        localparam BS_WIDTH              = $clog2(MAX_DAC_BURST_SIZE)+1;                                    // Width of BS register
        localparam MAX_SCALE_FACTOR      = 15;                                                              // Maximum amount the DAC output can be scaled down by
        localparam REQ_BUFFER_SZ         = 8;                                                               // Number of processor requests to remember that we would otherwise miss. 
        localparam DMA_DATA_WIDTH        = 64;                                                              // Bit width of transfers over DMA for the PWL. Each transfer is of the form {x (16), slope (32), dt(15) sb(1)}. sb = sparse_bit
        localparam MAX_WAVELET_PERIOD    = 4;                                                               // Maximum allowable period of pwl wavelet (in microseconds) (should be 20us)
        localparam SPARSE_BRAM_DEPTH     = 600;                                                             // Corresponding size of PWL wave sparse BRAM buffer, where each line is of size DMA_DATA_WIDTH
        localparam DENSE_BRAM_DEPTH      = 600;                                                             // Corresponding size of PWL wave dense BRAM buffer, where each line is of size BATCH_SIZE    
        localparam RFDC_CHANNELS         = 8;                                                               // Channels of sample discriminator config
        localparam SDC_DATA_WIDTH        = (2*RFDC_CHANNELS*SAMPLE_WIDTH);                                  // Bit width of sample discriminator config register (256)
        localparam SDC_SAMPLES           = (SDC_DATA_WIDTH/(axi_params_pkg::WD_DATA_WIDTH));                // Number of mem_map entries for one sdc value (8)    
        localparam BUFF_CONFIG_WIDTH     = (2+$clog2($clog2(RFDC_CHANNELS)+1));                             // Bit width of buffer config (4)
        localparam FUNCTIONS_PER_CHANNEL = 1;                                                               // Functions per channel, may be increased from 1 to 2 or 3 (1)
        localparam CHANNEL_MUX_WIDTH     = ($clog2((1+FUNCTIONS_PER_CHANNEL)*RFDC_CHANNELS)*RFDC_CHANNELS); // Bit width for channel mux config register (32)
        localparam CHAN_SAMPLES          = (CHANNEL_MUX_WIDTH/(axi_params_pkg::WD_DATA_WIDTH));             // Number of mem_map entries for one channel mux register (2)
        localparam BUFF_TIMESTAMP_WIDTH  = 32;                                                              // Bit width for buffer timestamp register (32) 
        localparam BUFF_SAMPLES          = (BUFF_TIMESTAMP_WIDTH/(axi_params_pkg::WD_DATA_WIDTH));          // Number of mem_map entries for one buff_timestamp register (2)
        localparam INTERPOLATER_DELAY    = 3;                                                               // Clock cycles required to produce an output from the interpolater module 
        localparam DAC_NUM               = 8;                                                               // Number of parallel DACs on fpga
        localparam FIRMWARE_VERSION      = 16'h1_0046;                                                      // Data Acquisition System (DAS) Version Number: 
    endpackage 
`endif