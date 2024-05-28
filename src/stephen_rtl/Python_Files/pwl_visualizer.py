import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
from fpga_constants import *
from sys import path
path.insert(0, r'C:\Users\skand\OneDrive\Documents\GitHub\rfsoc_daq\src\stephen_rtl\Python_Files/cython_files')
import pwl_wrapper_python as p
import pwl_wrapper as c 

def flatten(li):
    out = []
    for el in li:
        if type(el) == list: out += flatten(el)
        else: out.append(el)
    return out 

def plot_path(coords,simple_plot=True,desired_period=None):
    if desired_period:
        req_max_t = desired_period//dac_T
        given_max_t = coords[-1][1]
        coords = [(el[0],int(req_max_t*(el[1]/given_max_t))) for el in coords]
    
    coords.reverse()
    intv,fpga_cmds = c.main(coords)
    path = c.fpga_to_pwl(fpga_cmds)
    waves = c.decode_pwl_cmds(path)
    flat_wave = flatten(waves)
    print(flat_wave)
    if desired_period:
        flat_wave = [(el/max_voltage)*100 for el in flat_wave]
        ts = [round((i*dac_T)/1e-6,3) for i in range(len(flat_wave))]
    else: ts = [i for i in range(len(flat_wave))]
    
    dense_packs,sparse_packs = 0,0
    for x,slope,dt,sb in path:
        if sb == 0: dense_packs+=1
        else: sparse_packs+=1
    total_bytes = ((dense_packs*batch_width) + (sparse_packs*dma_data_width))/8

    period = round((dac_T*len(flat_wave))/1e-6,3)
    font = FontProperties()
    font.set_family('serif')
    font.set_name('Times New Roman')
    if desired_period: 
        plt.xlabel(r"$\mu s$",fontsize=17,fontproperties=font,fontweight='light')
        plt.ylabel("% of Max DAC Voltage",fontsize=17,fontproperties=font,fontweight='light')
    plt.title(f"PWL Wave Period: {period} us\n{total_bytes/1e3} KB required",fontsize=20,fontproperties=font,fontweight='heavy')
    if desired_period: split = lambda li: ([(el[0]/max_voltage)*100 for el in li],[(el[1]*dac_T)/1e-6 for el in li])
    else: split = lambda li: ([el[0] for el in li],[el[1]for el in li])
    x,t = split(coords)
    plt.scatter(t,x)
    # print(flat_wave,"\n")
    if simple_plot: plt.plot(ts,flat_wave)
    else:
        abs_t = 0
        for wave in waves:
            if desired_period:
                t = [((abs_t+i)*dac_T)/1e-6 for i in range(len(wave))]
                f = [(el/max_voltage)*100 for el in wave]
            else: 
                t = [abs_t+i for i in range(len(wave))]
                f = [el for el in wave]
            plt.plot(t,f)
            abs_t+=len(wave)
    print(path)
    return fpga_cmds


mv = max_voltage
coords = [(0,0), (18,18), (36,27), (0, 63)]
# coords = [(0,0), (5,5), (10,10), (15,16)]


simple_plot = True
desired_period = None
fpga_cmds = plot_path(coords,simple_plot=simple_plot,desired_period=desired_period)
fpga_cmds.reverse()
print()

def rtl_cmd_formatter(fpga_cmds): 
    out = f"localparam BUFF_LEN = {len(fpga_cmds)};\nlogic[BUFF_LEN-1:0][DMA_DATA_WIDTH-1:0] dma_buff;\n dma_buff = {{"
    for el in fpga_cmds: out+=f"{dma_data_width}'d{el}, "
    out = out[:-2]+"};"
    return out 

print(rtl_cmd_formatter(fpga_cmds))



