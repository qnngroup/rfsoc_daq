from addr_layout import *
import pyperclip
def hexU(num): return "0x"+hex(num)[2:].upper()

copy_addr_map = False
copy_addr_id_list = True
copy_addr_list_test = False 
if copy_addr_map:
    addrs_str = ""
    index_str = ""
    for addr_name in addrs_full:
        addrs = addr_map[addr_name]
        addr_vals = ""
        indx_vals = ""
        if type(addrs) is list: 
            addr_vals+=""
            indx_vals+=""
            for i,addr in enumerate(addrs): 
                    addr_vals+= f"({i}): {hexU(base_addr+addr)}, "
                    indx_vals+=f"({i}): {addr//4}, "
            addr_vals = addr_vals[:-2]
            indx_vals = indx_vals[:-2]
        else: 
            addr_vals+=hexU(base_addr+addrs)
            indx_vals+=str(addrs//4)
        addrs_str+= addr_name + " <=> " + addr_vals + "\n"
        index_str+= addr_name + " <=> " + indx_vals + "\n"
    addrs_str = addrs_str[:-1]
    index_str = index_str[:-1]
    
    cpy = "(Numbers in parenthesis indicate DAC number)\n"
    cpy+="\nProcessor MMIO Addresses\n################################################\n"+align(addrs_str,"<")
    cpy+="################################################\n\nRTL MMIO Indices\n################################################\n"+align(index_str,"<")
    cpy+=f"################################################\n\n Full Memory Map\n################################################\n{memory_map}"
    pyperclip.copy(cpy)
    print("Copied full address map")
elif copy_addr_id_list:
    cpy = "logic[ADDR_NUM-1:0][ADDRW-1:0] addrs = {"
    addrs = ""
    ids = ""
    list_len = 0
    for addr in reversed(rtl_names_full): 
        if is_DAC_REG(addr) or is_VALID_DAC_REG(addr): 
            for i in range(dac_num-1,-1,-1): addrs+=f"{addr}[{i}], "
            list_len+=8
        else: 
            addrs+= f"{addr}, "
            list_len+=1
    addrs = addrs[:-2]
    ids = addrs.replace("ADDRS", "IDS")
    ids = ids.replace("ADDR", "ID")
    cpy+=f"{addrs}}};\nlogic[ADDR_NUM-1:0][MEM_WIDTH-1:0] ids = {{{ids}}};"
    cpy = f"localparam ADDR_NUM = {list_len};\n"+cpy
    pyperclip.copy(cpy)
    print("Copied address/id list")
elif copy_addr_list_test:
    print("Copied address list test")

