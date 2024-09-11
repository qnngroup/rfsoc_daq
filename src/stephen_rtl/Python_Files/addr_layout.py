from fpga_constants import * 


class AddrDict(dict):    
    def __setitem__(self, key, value):
        if key in [el for el in self]:
            if type(self[key]) == list: value = (self[key]+[value[0]], value[1])
            else: value = ([self[key], value[0]], value[1])
        super().__setitem__(key, value)
    def __getitem__(self, key):
        item = super().__getitem__(key)
        return item[0]
    def __repr__(self):
        di = {el:self[el] for el in self}
        return di.__repr__()
    def get_rtl_addr(self,key):
        item = super().__getitem__(key)
        return item[1]

def gen_dac_addrs(base,addrs_for_reg): return [base + addrs_for_reg*(4*i) for i in range(dac_num)]

def is_DAC_REG(addr_name):
    if addr_name in ["PS_SEED_BASE_ADDRS", "TRIG_WAVE_ADDRS", "DAC_HLT_ADDRS", "DAC_BURST_SIZE_ADDRS", "DAC_SCALE_ADDRS", "RUN_PWL_ADDRS", "PWL_PERIOD_ADDRS"]:
        return True
    return False
def is_VALID_DAC_REG(addr_name):
    if addr_name in ["PS_SEED_VALID_ADDRS", "PWL_PERIOD_VALID_ADDRS"]: return True
    return False
def is_VALID_REG(addr_name):
    if addr_name in ["seed_valids", "pwl_period_valids", "buff_time_valid", "sdc_valid", "chan_mux_valid"]:
        return True
    return False

def is_VALID_ADDR(addr):
    for addr_name in ["seed_valids", "pwl_period_valids", "buff_time_valid", "sdc_valid", "chan_mux_valid"]:
        addrs = addr_map[addr_name]
        if type(addrs) is not list: addrs = [addrs]
        if addr in addrs: 
            if len(addrs) > 1: return f"{addr_name}.{addrs.index(addr)}"
            return addr_name
    return None
    
def is_BIG_REG(addr_name):
    if addr_name == "PS_SEED_BASE_ADDRS":  return (batch_size, "seed_valids", "PS_SEED_VALID_ADDRS")
    if addr_name == "PWL_PERIOD_ADDRS":    return (pwl_period_size, "pwl_period_valids", "PWL_PERIOD_VALID_ADDRS")
    if addr_name == "BUFF_TIME_BASE_ADDR": return (buff_size, "buff_time_valid", "BUFF_TIME_VALID_ADDR")
    if addr_name == "SDC_BASE_ADDR":       return (sdc_size, "sdc_valid", "SDC_VALID_ADDR")
    if addr_name == "CHAN_MUX_BASE_ADDR": return (chan_size, "chan_mux_valid", "CHAN_MUX_VALID_ADDR")
    return None

    
def addAddr(el): addr_map[el[0]] = el[1]

def find_closest(i, li):
    if i in li: return None
    diffs = [i-el for el in li]
    if all([el < 0 for el in diffs]): return None
    railVal = max(diffs)+1
    diffs = [el if el > 0 else railVal for el in diffs]
    j = diffs.index(min(diffs))
    return li[j]

def find_upper_name(addr):
    for addr_name in ["mem_test_base", "mem_test_end", "abs_addr_ceiling"]:
        if addr == addr_map[addr_name]: return addr_name
    if addr < addr_map["mem_test_base"]: return f"XXX_{(addr - addr_map['mapped_addr_ceiling'])//4}"
    if addr < addr_map["mem_test_end"]: return f"mem_test_base + {(addr - addr_map['mem_test_base'])//4}"
    return f"XXX_{(addr - addr_map['mem_test_end'])//4}"
        
def find_name(addr):
    if addr > addr_map["mapped_addr_ceiling"]: return find_upper_name(addr)
    valid_name = is_VALID_ADDR(addr)
    if valid_name: return valid_name
    for addr_name in addr_map:     
        if is_VALID_REG(addr_name): continue 
        addrs = addr_map[addr_name]
        if type(addrs) is not list: addrs = [addr_map[addr_name]]
        
        if is_BIG_REG(addr_map.get_rtl_addr(addr_name)): reg_limit = addrs[-1] + (is_BIG_REG(addr_map.get_rtl_addr(addr_name))[0]*4)
        else: reg_limit = addrs[-1]
        
        if addr > reg_limit: continue
    
        if addr not in addrs: 
            base_addr = find_closest(addr, addrs)  
            if len(addrs) > 1: addr_name = f"{addr_name}.{addrs.index(base_addr)}"
            return f"{addr_name} + {(addr%base_addr)//4 if base_addr//4 != 1 else addr//base_addr-1}"
        
        is_big = is_BIG_REG(addr_map.get_rtl_addr(addr_name))
        if len(addrs) > 1: addr_name = f"{addr_name}.{addrs.index(addr)}"    
        if is_big: addr_name+=" + 0"
        return addr_name 
    
def align(s, pat):
    lines = s.split("\n")
    modelI = max([line.find(pat) for line in lines])
    out = ""
    for line in lines:
        i = line.find(pat)
        if i == -1: 
            i = 0
            line = "\t"+line
        out+=line[:i]+" "*(modelI-i)+line[i:]+"\n"
    return out

def validate_rtl_addrs(rtl_in, addrs):
    lines = rtl_addrs.split("\n")
    rtl_names = []
    for line in lines:
        
        i = line.find("[ADDRW-1:0]")+len("[ADDRW-1:0]")+1
        j = line[i:].find(" ")+i
        if line[i:j] == "PS_BASE_ADDR": continue
        rtl_names.append(line[i:j])
        
    failed = False
    failed_pairs = ""
    for expc,got in zip(rtl_in,rtl_names):
        if expc != got: 
            failed = True
            failed_pairs+= str((expc,got))+"\n"
    if len(addrs) != len(rtl_names): failed = True
    print("####### ADDR_LAYOUT #######")
    if failed: print(f"FAILED\nCheck fpga_constants: Provided rtl addrs do not match\n{failed_pairs}") 
    else: print("PASSED\nProvided rtl addrs match")
    print("###########################\n")
        
    

addrs_full = ["rst", "seeds", "seed_valids", "triangle_waves", "hlt_dacs", "dac_burst_sizes", "max_dac_burst_size", 
              "dac_scales","dac1","dac2", "run_pwls", "pwl_periods", "pwl_period_valids", "buff_config", "buff_time_base", 
              "buff_time_valid", "chan_mux_base", "chan_mux_valid", "sdc_base", "sdc_valid", "firmware_version", "mem_size", 
              "mapped_addr_ceiling", "mem_test_base", "mem_test_end", "abs_addr_ceiling"]
rtl_names_full = ["RST_ADDR", "PS_SEED_BASE_ADDRS", "PS_SEED_VALID_ADDRS", "TRIG_WAVE_ADDRS", "DAC_HLT_ADDRS", "DAC_BURST_SIZE_ADDRS", 
                  "MAX_DAC_BURST_SIZE_ADDR","DAC_SCALE_ADDRS", "DAC1_ADDR", "DAC2_ADDR", "RUN_PWL_ADDRS", "PWL_PERIOD_ADDRS", "PWL_PERIOD_VALID_ADDRS",
                  "BUFF_CONFIG_ADDR", "BUFF_TIME_BASE_ADDR", "BUFF_TIME_VALID_ADDR", "CHAN_MUX_BASE_ADDR", "CHAN_MUX_VALID_ADDR", 
                  "SDC_BASE_ADDR", "SDC_VALID_ADDR", "VERSION_ADDR", "MEM_SIZE_ADDR", "MAPPED_ADDR_CEILING", "MEM_TEST_BASE_ADDR", 
                  "MEM_TEST_END_ADDR", "ABS_ADDR_CEILING"]

validate_rtl_addrs(rtl_names_full, addrs_full)

addr_map = AddrDict()
addAddr(("rst",(0x0,"RST_ADDR")))

addrs, rtl_names = [],[]
for addr_name, rtl_name in zip(addrs_full[1:-3], rtl_names_full[1:-3]):
    if is_VALID_REG(addr_name): continue    
    addrs.append(addr_name)
    rtl_names.append(rtl_name)

for i in range(len(addrs)):
    curr_addr_name = addrs[i]
    curr_addr_rtl_name = rtl_names[i]
    n = dac_num if is_DAC_REG(curr_addr_rtl_name) else 1
    for j in range(n):
        last_addr = addr_map[[el for el in addr_map][-1]]
        if type(last_addr) == list: base = last_addr[-1]+4
        else: base = last_addr+4

        addAddr((curr_addr_name, (base, curr_addr_rtl_name)))
        if is_BIG_REG(curr_addr_rtl_name):        
            reg_size, valid_name, valid_rtl_name = is_BIG_REG(curr_addr_rtl_name)
            addAddr((valid_name, (base+(reg_size*4), valid_rtl_name)))
    
addAddr(("mem_test_base", (4*(mem_size-55), "MEM_TEST_BASE_ADDR")))
addAddr(("mem_test_end", (addr_map["mem_test_base"] + 4*50, "MEM_TEST_END_ADDR")))
addAddr(("abs_addr_ceiling", (4*(mem_size-1), "ABS_ADDR_CEILING")))

id_map = dict()
memory_map = ""
for i in range(mem_size):
    name = find_name(4*i)
    id_map[i] = name
    memory_map+= f"{hex(base_addr+4*i).upper()}, {i} : {name}\n"
memory_map = align(memory_map,":")
    
    
    
    
    