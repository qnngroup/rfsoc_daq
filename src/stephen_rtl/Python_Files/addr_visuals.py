from addr_layout import *

addrs_str = ""
index_str = ""
li = [(el1,hex(el2+base_addr)) for el1,el2 in addr_map.items()]
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
	excluded_addrs = ["MAPPED_ADDR_CEILING", "MEM_TEST_BASE_ADDR", "ABS_ADDR_CEILING", "MAPPED_ID_CEILING", "MEM_TEST_BASE_ID", "ABS_ID_CEILING" ]
	out = f"logic[`ADDR_NUM-1:0][31:0] {name} = {{"
	addr_lst = []
	rtl_addrs = rtl_addrs.split("\n")
	rtl_addrs.reverse()
	ignore = [' ', '\t']
	for line in rtl_addrs:
		if not line or all([el in ignore for el in line]): continue
		line = line.replace("\t", "")
		i = line.find('`')+len("`define")+1
		line = line[i:]
		line = line[:line.find(' ')]
		if line in excluded_addrs: continue
		addr_lst.append(line)
	for a in addr_lst: out+=f"32'(`{a}), "
	return out[:-2]+"};", len(addr_lst)

print("Processor MMIO Addresses:\n"+tabsize(addrs_str))
print("RTL MMIO Indiceis:\n"+tabsize(index_str))


rtl_addrs = """
        `define RST_ADDR                (`PS_BASE_ADDR)
        `define PS_SEED_BASE_ADDR       (`RST_ADDR + 4)
        `define PS_SEED_VALID_ADDR      (`PS_SEED_BASE_ADDR + 4 * (`BATCH_SAMPLES))
        `define TRIG_WAVE_ADDR          (`PS_SEED_VALID_ADDR + 4)
        `define DAC_HLT_ADDR            (`PS_SEED_VALID_ADDR + 4*2)
        `define DAC_ILA_TRIG_ADDR       (`PS_SEED_VALID_ADDR + 4*3)
        `define DAC_ILA_RESP_ADDR       (`PS_SEED_VALID_ADDR + 4*4)
        `define DAC_ILA_RESP_VALID_ADDR (`PS_SEED_VALID_ADDR + 4*5)
        `define ILA_BURST_SIZE_ADDR     (`PS_SEED_VALID_ADDR + 4*6)
        `define MAX_BURST_SIZE_ADDR     (`PS_SEED_VALID_ADDR + 4*7)
        `define SCALE_DAC_OUT_ADDR      (`PS_SEED_VALID_ADDR + 4*8)
        `define DAC1_ADDR               (`PS_SEED_VALID_ADDR + 4*9)
        `define DAC2_ADDR               (`PS_SEED_VALID_ADDR + 4*10)
        `define PWL_PREP_ADDR           (`PS_SEED_VALID_ADDR + 4*11)
        `define RUN_PWL_ADDR            (`PS_SEED_VALID_ADDR + 4*12)
        `define BUFF_CONFIG_ADDR        (`PS_SEED_VALID_ID   + 4*13)
        `define BUFF_TIME_BASE_ADDR     (`PS_SEED_VALID_ADDR + 4*14)
        `define BUFF_TIME_VALID_ADDR    (`BUFF_TIME_BASE_ADDR + 4*(`BUFF_SAMPLES))
        `define CHAN_MUX_BASE_ADDR      (`BUFF_TIME_VALID_ADDR + 4)
        `define CHAN_MUX_VALID_ADDR     (`CHAN_MUX_BASE_ADDR + 4*(`CHAN_SAMPLES))
        `define SDC_BASE_ADDR           (`CHAN_MUX_VALID_ADDR + 4)
        `define SDC_VALID_ADDR          (`SDC_BASE_ADDR + 4*(`SDC_SAMPLES))
        `define MEM_SIZE_ADDR           (`SDC_VALID_ADDR + 4)
        `define MAPPED_ADDR_CEILING     (`MEM_SIZE_ADDR + 4)
        `define MEM_TEST_BASE_ADDR      (`PS_BASE_ADDR + 4*(`MEM_SIZE - 55))
        `define VERSION_ADDR            (`PS_BASE_ADDR + 4*(`MEM_SIZE - 2))
        `define ABS_ADDR_CEILING        (`PS_BASE_ADDR + 4*(`MEM_SIZE-1))
		"""
rtl_ids = rtl_addrs.replace("ADDR", "ID")
# a,lena = mkAddrList(rtl_addrs,"addrs")
# print(a)
# ids, lenids = mkAddrList(rtl_ids,"ids")
# print("\n"+ids)
# print(lena, lenids)

