from addr_layout import *

addrs_str = ""
index_str = ""
li = [(el1,hex(el2[0]+base_addr),el2[1]) for el1,el2 in addr_map.items()]
for el in li:
        addrs_str+= el[0] + " <=> " +el[1]+"\n"
        index_str+= el[0] + " <=> " +str(int((eval(el[1])-base_addr)/4))+"\n"

def tabsize(s):
        out = ""
        sout = []
        s = s.split('\n')
        indices = []
        for el in s:
                i = el.find('<')
                indices.append(i)
                sout.append((el[:i],el[i:]))
        tdist = max(indices)
        for i in range(len(sout)):
                out+= sout[i][0] + (tdist - indices[i])* " " + sout[i][1]+ " \n"
        return out

def mkAddrList(rtl_addrs,name):
        excluded_addrs = ["MAPPED_ADDR_CEILING", "MEM_TEST_BASE_ADDR", "ABS_ADDR_CEILING", "MAPPED_ID_CEILING", "MEM_TEST_BASE_ID", "MEM_TEST_END_ADDR", "MEM_TEST_END_ID", "ABS_ID_CEILING", "PS_BASE_ADDR", "PS_BASE_ID"]
        size = "MEM_WIDTH" if name=="ids" else "A_DATA_WIDTH"
        out = f"logic[ADDR_NUM-1:0][{size}:0] {name} = {{"
        addr_lst = []
        rtl_addrs = rtl_addrs.split("\n")
        rtl_addrs.reverse()
        ignore = [' ', '\t']
        j = 0
        passed = True
        for line in rtl_addrs:
                if not line or all([el in ignore for el in line]): continue
                line = line.replace("\t", "")
                i = line.find("logic[A_DATA_WIDTH-1:0]")+len("logic[A_DATA_WIDTH-1:0]")+1
                line = line[i:]
                line = line[:line.find(' ')]
                expected_line = li[len(li)-j-1][2]
                if name == "ids": expected_line = expected_line.replace("ADDR","ID")
                if line != expected_line: 
                    passed = False
                    print(f"Address mismatch! {(line,expected_line)}")
                j+=1
                if line in excluded_addrs: continue                
                addr_lst.append(line)
        for a in addr_lst: out+=f"{a}, "
        return out[:-2]+"};", len(addr_lst), passed

print("Processor MMIO Addresses:\n"+tabsize(addrs_str))
print("RTL MMIO Indices:\n"+tabsize(index_str))


rtl_addrs = """
        logic[A_DATA_WIDTH-1:0] PS_BASE_ADDR            = 32'h9000_0000;
        logic[A_DATA_WIDTH-1:0] RST_ADDR                = PS_BASE_ADDR;
        logic[A_DATA_WIDTH-1:0] PS_SEED_BASE_ADDR       = RST_ADDR + 4;
        logic[A_DATA_WIDTH-1:0] PS_SEED_VALID_ADDR      = PS_SEED_BASE_ADDR + 4 * (daq_params_pkg::BATCH_SIZE);
        logic[A_DATA_WIDTH-1:0] TRIG_WAVE_ADDR          = PS_SEED_VALID_ADDR + 4;
        logic[A_DATA_WIDTH-1:0] DAC_HLT_ADDR            = PS_SEED_VALID_ADDR + 4*2;
        logic[A_DATA_WIDTH-1:0] DAC_BURST_SIZE_ADDR     = PS_SEED_VALID_ADDR + 4*3;
        logic[A_DATA_WIDTH-1:0] MAX_DAC_BURST_SIZE_ADDR = PS_SEED_VALID_ADDR + 4*4;
        logic[A_DATA_WIDTH-1:0] SCALE_DAC_OUT_ADDR      = PS_SEED_VALID_ADDR + 4*5;
        logic[A_DATA_WIDTH-1:0] DAC1_ADDR               = PS_SEED_VALID_ADDR + 4*6;
        logic[A_DATA_WIDTH-1:0] DAC2_ADDR               = PS_SEED_VALID_ADDR + 4*7;
        logic[A_DATA_WIDTH-1:0] RUN_PWL_ADDR            = PS_SEED_VALID_ADDR + 4*8;
        logic[A_DATA_WIDTH-1:0] PWL_PERIOD0_ADDR        = PS_SEED_VALID_ADDR + 4*9;
        logic[A_DATA_WIDTH-1:0] PWL_PERIOD1_ADDR        = PS_SEED_VALID_ADDR + 4*10;
        logic[A_DATA_WIDTH-1:0] BUFF_CONFIG_ADDR        = PS_SEED_VALID_ADDR + 4*11;
        logic[A_DATA_WIDTH-1:0] BUFF_TIME_BASE_ADDR     = PS_SEED_VALID_ADDR + 4*12;
        logic[A_DATA_WIDTH-1:0] BUFF_TIME_VALID_ADDR    = BUFF_TIME_BASE_ADDR + 4 * (daq_params_pkg::BUFF_SAMPLES);
        logic[A_DATA_WIDTH-1:0] CHAN_MUX_BASE_ADDR      = BUFF_TIME_VALID_ADDR + 4;
        logic[A_DATA_WIDTH-1:0] CHAN_MUX_VALID_ADDR     = CHAN_MUX_BASE_ADDR + 4 * (daq_params_pkg::CHAN_SAMPLES);
        logic[A_DATA_WIDTH-1:0] SDC_BASE_ADDR           = CHAN_MUX_VALID_ADDR + 4;
        logic[A_DATA_WIDTH-1:0] SDC_VALID_ADDR          = SDC_BASE_ADDR + 4 * (daq_params_pkg::SDC_SAMPLES);
        logic[A_DATA_WIDTH-1:0] VERSION_ADDR            = SDC_VALID_ADDR + 4;
        logic[A_DATA_WIDTH-1:0] MEM_SIZE_ADDR           = SDC_VALID_ADDR + 4*2;
        logic[A_DATA_WIDTH-1:0] MAPPED_ADDR_CEILING     = MEM_SIZE_ADDR + 4;
        logic[A_DATA_WIDTH-1:0] MEM_TEST_BASE_ADDR      = PS_BASE_ADDR + 4*(MEM_SIZE - 55);
        logic[A_DATA_WIDTH-1:0] MEM_TEST_END_ADDR       = MEM_TEST_BASE_ADDR + 4*50;
        logic[A_DATA_WIDTH-1:0] ABS_ADDR_CEILING        = PS_BASE_ADDR + 4*(MEM_SIZE-1);
                """
rtl_ids = rtl_addrs.replace("ADDR", "ID")
a,lena,pass1 = mkAddrList(rtl_addrs,"addrs")
print(a,"\n")
ids, lenids,pass2 = mkAddrList(rtl_ids,"ids")
print(ids)
print("\n\n")
print(lena, lenids,len(li))
if (not(pass1 and pass2)): print("ADDRESS GENERATION FAILED")
else: print("ADDRESS GENERATION PASSED")
if (len(set((lena,lenids,len(li)-5)))>1): print("Mismatch between provided rtl_addrs and imported rtl addrs from addr_layout.py")
else: print("Provided rtl_addrs and imported rtl_addrs match")

