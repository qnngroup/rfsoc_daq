from math import log2,ceil,floor

firmware_version = 1.004
raw_fv = 0x1004
mem_size = 512
max_dac_burst_size = 32767
base_addr = 0x9000_0000
sample_width = 16
wd_data_width = sample_width
dataw = wd_data_width
batch_width = 256
batch_size = batch_width//sample_width
fixed_point_percision = 8
rfdc_channels = 8
sdc_data_width = 2*rfdc_channels*sample_width
sdc_size = sdc_data_width//dataw
buff_config_width = int(2*log2(log2(rfdc_channels)+1))
func_per_chan = 1
chan_mux_width = int(log2((1+func_per_chan)*rfdc_channels))*rfdc_channels
chan_size = chan_mux_width//dataw
buff_time_width = 32
buff_size = buff_time_width//dataw
dac_clk = 384e6
dac_T = 1/dac_clk
MB_of_BRAM = 38/8
max_voltage = 0x7fff
dma_data_width = 48
dac_num = 8
pwl_period_width = 32;                    
pwl_period_size = pwl_period_width//dataw;

rtl_addrs = """localparam logic[ADDRW-1:0] PS_BASE_ADDR                        = 32'h9000_0000;
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
        localparam logic[ADDRW-1:0] ABS_ADDR_CEILING                    = PS_BASE_ADDR + 4*(MEM_SIZE-1);"""
        
        
        
        
        
        
        
        
        