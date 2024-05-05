from math import log2
firmware_version = 1.004
raw_fv = 0x1004
mem_size = 256
max_dac_burst_size = 32767
base_addr = 0x9000_0000
sample_width = 16
wd_data_width = sample_width
batch_width = 256
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
addrs = ["triangle_wave", "hlt_dac", "dac_burst_size", "max_dac_burst_size", "scale_dac_out","dac1","dac2", "run_pwl", "buff_config", "buff_time_base"]
[addAddr((addrs[i],addr_map['seed_valid'] + 4*(i+1))) for i in range(len(addrs))]
addAddr(("buff_time_valid",addr_map["buff_time_base"]+4*buff_samples))
addAddr(("chan_mux_base",addr_map["buff_time_valid"]+4))
addAddr(("chan_mux_valid",addr_map["chan_mux_base"]+ 4*chan_samples))
addAddr(("sdc_base",addr_map["chan_mux_valid"]+ 4))
addAddr(("sdc_valid",addr_map["sdc_base"]+ 4*sdc_samples))
addAddr(("firmware_version", addr_map["sdc_valid"]+4))
addAddr(("mem_size",addr_map["sdc_valid"]+8))
addAddr(("mapped_addr_ceiling", (addr_map["mem_size"] + 4) ))
addAddr(("mem_test_base", 4*(mem_size-55)))
addAddr(("mem_test_end", addr_map["mem_test_base"] + 4*50))
addAddr(("abs_addr_ceiling", 4*(mem_size-1)))

def find_closest_val(key,di):
    diffs = [(key-k,k) for k in di.keys() if key >= k]
    closest_key = min(diffs,key=lambda el: el[0])[1]
    return di[closest_key]

addr_map_inverted_1 = {val:key for key,val in addr_map.items()}
addr_map_inverted = dict()
for i in range(256):
    curr_addr = 4*i
    base_name = find_closest_val(curr_addr,addr_map_inverted_1)
    name = base_name if curr_addr in addr_map_inverted_1 else base_name+"+4*"+str(int((curr_addr-addr_map[base_name])/4))
    addr_map_inverted[curr_addr] = name