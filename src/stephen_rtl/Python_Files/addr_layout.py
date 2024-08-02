from fpga_constants import * 

class AddrDict(dict):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def __getitem__(self, key):
        item = super().__getitem__(key)
        return item[0]
    
    def get_rtl_addr(self,key):
        item = super().__getitem__(key)
        return item[1]
        
def addAddr(el): addr_map[el[0]] = el[1]

addr_map = AddrDict()

[addAddr(el) for el in [("ps_base",(0x0,"PS_BASE_ADDR")), ("rst",(0x0,"RST_ADDR")), ("seed_base",(0x4,"PS_SEED_BASE_ADDR"))]]
addAddr(("seed_valid",(addr_map['seed_base']+ 4*batch_size,"PS_SEED_VALID_ADDR")))
addrs = ["triangle_wave", "hlt_dac", "dac_burst_size", "max_dac_burst_size", "scale_dac_out","dac1","dac2", "run_pwl", "pwl_period0", "pwl_period1","buff_config", "buff_time_base"]
rtl_names = ["TRIG_WAVE_ADDR", "DAC_HLT_ADDR", "DAC_BURST_SIZE_ADDR", "MAX_DAC_BURST_SIZE_ADDR", "SCALE_DAC_OUT_ADDR", "DAC1_ADDR", "DAC2_ADDR", "RUN_PWL_ADDR", "PWL_PERIOD0_ADDR", "PWL_PERIOD1_ADDR", "BUFF_CONFIG_ADDR", "BUFF_TIME_BASE_ADDR"]
[addAddr((addrs[i],(addr_map['seed_valid'] + 4*(i+1), rtl_names[i]))) for i in range(len(addrs))]
addAddr(("buff_time_valid", (addr_map["buff_time_base"]+4*buff_samples,"BUFF_TIME_VALID_ADDR")))
addAddr(("chan_mux_base", (addr_map["buff_time_valid"]+4, "CHAN_MUX_BASE_ADDR")))
addAddr(("chan_mux_valid", (addr_map["chan_mux_base"]+ 4*chan_samples, "CHAN_MUX_VALID_ADDR")))
addAddr(("sdc_base", (addr_map["chan_mux_valid"]+ 4, "SDC_BASE_ADDR")))
addAddr(("sdc_valid", (addr_map["sdc_base"]+ 4*sdc_samples, "SDC_VALID_ADDR")))
addAddr(("firmware_version", (addr_map["sdc_valid"]+4, "VERSION_ADDR")))
addAddr(("mem_size", (addr_map["sdc_valid"]+8, "MEM_SIZE_ADDR")))
addAddr(("mapped_addr_ceiling", (addr_map["mem_size"] + 4, "MAPPED_ADDR_CEILING")))
addAddr(("mem_test_base", (4*(mem_size-55), "MEM_TEST_BASE_ADDR")))
addAddr(("mem_test_end", (addr_map["mem_test_base"] + 4*50, "MEM_TEST_END_ADDR")))
addAddr(("abs_addr_ceiling", (4*(mem_size-1), "ABS_ADDR_CEILING")))

def find_closest_val(key,di):
    diffs = [(key-k,k) for k in di.keys() if key >= k]
    closest_key = min(diffs,key=lambda el: el[0])[1]
    return di[closest_key]

addr_map_inverted_1 = {val[0]:key for key,val in addr_map.items()}
addr_map_inverted = dict()
for i in range(256):
    curr_addr = 4*i
    base_name = find_closest_val(curr_addr,addr_map_inverted_1)
    name = base_name if curr_addr in addr_map_inverted_1 else base_name+"+4*"+str(int((curr_addr-addr_map[base_name])/4))
    addr_map_inverted[curr_addr] = name