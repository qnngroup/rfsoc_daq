from math import log2
mem_size = 256
base_addr = 0x9000_0000
sample_width = 16
wd_data_width = sample_width
max_ila_burst_size = 20
batch_width = 1024
batch_size = batch_width//sample_width
rfdc_channels = 8
sdc_data_width = 2*rfdc_channels*sample_width
sdc_samples = sdc_data_width//wd_data_width
buff_config_width = int(2*log2(log2(rfdc_channels)+1))
func_per_chan = 1
chan_mux_width = int(log2((1+func_per_chan)*rfdc_channels))*rfdc_channels
chan_samples = chan_mux_width//wd_data_width
buff_time_width = 32
buff_samples = buff_time_width//wd_data_width

def addAddr(el): addr_map[el[0]] = el[1]

addr_map = {"rst":0x0, "seed_base": 0x4}
addAddr(("seed_valid",addr_map['seed_base']+ 4*batch_size))
addrs = ["triangle_wave", "hlt_dac", "set_trigger", "ila_resp", "ila_resp_valid", "ila_burst_size", "max_burst_size", "scale_dac_out","dac1","dac2", "pwl_prep", "run_pwl", "buff_config", "buff_time_base"]
[addAddr((addrs[i],addr_map['seed_valid'] + 4*(i+1))) for i in range(len(addrs))]
addAddr(("buff_time_valid",addr_map["buff_time_base"]+4*buff_samples))
addAddr(("chan_mux_base",addr_map["buff_time_valid"]+4))
addAddr(("chan_mux_valid",addr_map["chan_mux_base"]+ 4*chan_samples))
addAddr(("sdc_base",addr_map["chan_mux_valid"]+ 4))
addAddr(("sdc_valid",addr_map["sdc_base"]+ 4*sdc_samples))
addAddr(("mem_size",addr_map["sdc_valid"]+4))
addAddr(("mapped_addr_ceiling", (addr_map["mem_size"] + 4) ))
addAddr(("mem_test_base", 4*(mem_size-55)))
addAddr(("firmware_version", 4*(mem_size-2)))
addAddr(("abs_addr_ceiling", 4*(mem_size-1)))
