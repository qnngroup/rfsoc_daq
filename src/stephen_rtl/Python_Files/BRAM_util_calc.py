import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
import matplotlib.ticker as ticker
from math import log2,ceil

clk = 400e6
T = 1/clk
batch_width = 1024
sample_width = 16
MB_of_BRAM = 38/8
batch_size = int(batch_width/sample_width)

def calc_pwl_BRAM_util(max_wavelet_period):
    periods_in_max_wavelet = max_wavelet_period/T
    samples_in_max_wavelet = periods_in_max_wavelet*batch_size
    MB_in_max_wavelet = ((samples_in_max_wavelet*sample_width)/8)/1e6
    percent_of_BRAM = (MB_in_max_wavelet/MB_of_BRAM)*100
    percent_of_BRAM = round(percent_of_BRAM,2)
    max_BRAM_depth = (samples_in_max_wavelet*sample_width)/batch_width
    return str(percent_of_BRAM)+"% of BRAM Utilization",percent_of_BRAM,max_BRAM_depth

def calc_period(batch_num): return T*batch_num

def plt_percs():
    x,percs,depths = [],[],[]
    for i in range(80):
        T = i*1e-6
        _,perc,max_BRAM_depth = calc_pwl_BRAM_util(T)
        percs.append(perc)
        depths.append(max_BRAM_depth)
        x.append(i)


    fig, ax1 = plt.subplots(1,2)
    ax1,ax2 = ax1
    fig.tight_layout(pad=5)
    ax1.plot(x,percs)
    ax2.plot(x,depths)
    font = FontProperties()
    font.set_family('serif')
    font.set_name('Times New Roman')
    ax1.xaxis.set_major_locator(ticker.MultipleLocator(16))
    ax2.xaxis.set_major_locator(ticker.MultipleLocator(16))
    ax1.set_xlabel(r"PWL Wavelet period ($\mu$s)",fontsize=17,fontproperties=font,fontweight='light')
    ax1.set_ylabel(r"% of BRAM Utilization",fontsize=17,fontproperties=font,fontweight='light')
    ax2.set_xlabel(r"PWL Wavelet period ($\mu$s)",fontsize=17,fontproperties=font,fontweight='light')
    ax2.set_ylabel(r"PWL BRAM Depth",fontsize=17,fontproperties=font,fontweight='light')

# plt_percs()
#potential_max_period = 24.5e-6
#s,p,b = calc_pwl_BRAM_util(potential_max_period)
#print(s)
# bram_depth = int(b)
# time_bit_width = ceil(log2(bram_depth*batch_size))
# print(f"{s}, {bram_depth} BRAM depth required\n{time_bit_width} bits needed for the time field")
