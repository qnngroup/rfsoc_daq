import numpy as np
import matplotlib.pyplot as plt
from scipy import signal
from matplotlib.font_manager import FontProperties

files = []
names = ["20240116_225849_parsed", "20240116_230041_parsed", "20240116_230206_parsed", "20240116_230448_parsed"]
for name in names: files.append(np.load(f"poster_raw_data/{name}.npz"))
i = 0
def plt_file(file, limit):
	global i
	i = i+1
	channels = ['samples', 'num_samples', 'num_channels', 'gate_ampl_fs', 'chan_bias_fs']
	raw_chan,loop_chan = file["samples"][0],file["samples"][1]
	gate_amp,bias = file["gate_ampl_fs"], file["chan_bias_fs"]
	gate_amp = round(float(gate_amp),2)
	bias = round(float(bias),2)
	sample_rate = 4.096e9
	max_time = len(raw_chan)/sample_rate
	t = [((max_time/len(raw_chan))*i)/1e-6 for i in range(len(raw_chan))]

	sos = signal.butter(4, [1e6,20e6],btype="bandpass", fs=sample_rate, output='sos')
	x0 = np.mean(raw_chan)
	zi = signal.sosfilt_zi(sos)
	filtered, _ = signal.sosfilt(sos, raw_chan, zi=zi*x0)
	raw_chan = [el/(2**14-1)*100 for el in raw_chan]
	loop_chan = [el/(2**14-1)*100 for el in loop_chan]
	filtered = [el/(2**14-1)*100 for el in filtered]

	font = FontProperties()
	font.set_family('serif')
	font.set_name('Times New Roman')
	fig, ax = plt.subplots(3,1,sharex=True, gridspec_kw={'hspace': 0.3})
	fig.supylabel(r"% Of Max ADC Voltage",fontsize=17,fontproperties=font,fontweight='light')
	fig.suptitle(f"Gate Amplification: {gate_amp} | Channel Bias: {bias}",fontsize=15,fontproperties=font,fontweight='bold')

	ax3,ax1,ax2= ax[0],ax[1],ax[2]
	ax1.set_title(f"nTron Raw Response",fontsize=10,fontproperties=font)
	ax2.set_title(f"nTron Filtered Response",fontsize=10,fontproperties=font)
	ax3.set_title(f"nTron Raw Gate Input",fontsize=10,fontproperties=font)

	limit_index = int(min([(abs(limit-el),i) for i,el in enumerate(t)], key=lambda x: x[0])[1])
	t = t[:limit_index]
	raw_chan = raw_chan[:limit_index]
	loop_chan = loop_chan[:limit_index]
	filtered = filtered[:limit_index]
	ax1.plot(t,raw_chan)
	ax2.plot(t,filtered,marker=",",alpha=0.05)
	ax3.plot(t,loop_chan)
	ax2.set_xlabel(r"Time (us)",fontsize=17,fontproperties=font,fontweight='light')
	ax2.plot(t,[el-20 for el in loop_chan], alpha=0.2)
	file_name = f"poster_plots_out/{gate_amp},{bias}_{i}.png"
	plt.savefig(file_name)
	print(f"plotted {file_name}")


for f in files: plt_file(f,2.5)
