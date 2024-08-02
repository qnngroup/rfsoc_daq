from bitstring import Bits, BitArray
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
from random import randrange
from pyperclip import copy as cb_copy
import BRAM_util_calc as util

sample_width = 16
batch_samples = 1024
batch_samples = int(batch_samples/sample_width)
clk = 150e6
T = (1/clk)/1e-9

def toHex(val,width): return Bits(int=val, length=width).hex

# Coordinate els of the form (time,value), path els of the form (time, value, slope). Output path as well as the corresponding DMA buffer
def mk_path(coords):
	path = []
	path_hex = []
	for i in range(len(coords)):
		c1 = coords[i]
		slope = 0
#       print(coords)
		if i+1 < len(coords):
			c2 = coords[i+1]
			dv = c2[1] - c1[1]
			dt = c2[0] - c1[0]
			if dt == 0: print(c1,c2)
			slope = round(dv/dt)
			if slope == 0 and c2[1] != c1[1]: slope = 1 if dv > 1 else -1
		t,v,s = (toHex(el,sample_width) for el in c1+(slope,))
		hex_cmd = int(eval("0x"+t+v+s))
		path.append(c1+(slope,))
		path_hex.append(hex_cmd)
	return (path,path_hex)

def fmt_hxpath(path):
	dma_width = sample_width*3
	buff_len = len(path)
	out = f"localparam BUFF_LEN = {buff_len};\nlogic[BUFF_LEN-1:0][`DMA_DATA_WIDTH-1:0] dma_buff;\nassign dma_buff = {{"
	for el in path: out+= f"{dma_width}'h"+el[2:]+", "
	out = out[:-2]
	out +="};"
	return out

def mk_expected_out(path, plot = True, display_in_ns = True):

	checkpoints = [time for time,_,_ in path]
	all_samples,timeline = [],[]
	for el in range(checkpoints[-1]): all_samples.append(0),timeline.append(el)

	sample_ptr = 0
	for i in range(len(path)):
		t, val, slope = path[i]
		if i == len(path)-1:
			all_samples.append(val)
			break
		stop_time,nxt_val,_ = path[i+1]
		for j in range(sample_ptr,len(all_samples)):
			if timeline[j] == stop_time:
				sample_ptr = stop_time
				break
			new_val = val+slope*(j-sample_ptr)
			if slope > 0: all_samples[j] = new_val if new_val < nxt_val else nxt_val
			else: all_samples[j] = new_val if new_val > nxt_val else nxt_val

	batches = []
	while True:
		if all_samples == []: break
		if len(all_samples) < batch_samples:
			batches.append(all_samples + [path[-1][1] for el in range(batch_samples-len(all_samples))])
			break
		batch = all_samples[:batch_samples]
		batches.append(batch)
		all_samples = all_samples[batch_samples:]

	all_samples = []
	for batch in batches: all_samples+=batch
	if plot:
		time_factor = (T)/(batch_samples) if (display_in_ns) else (T*(1e-9/1e-6))/batch_samples
		xlabel = r"Time (ns)" if (display_in_ns) else r"Time (us)"
		max_voltage = (2**(sample_width-1))-1
		font = FontProperties()
		font.set_family('serif')
		font.set_name('Times New Roman')
		plt.xlabel(xlabel,fontsize=17,fontproperties=font,fontweight='light')
		plt.ylabel(r"% Of Max DAC Voltage",fontsize=17,fontproperties=font,fontweight='light')
		plt.plot([i*time_factor for i in range(len(all_samples))], [(el/max_voltage)*100 for el in all_samples])
		x,y = [el[0]*time_factor for el in path],[(el[1]/max_voltage)*100 for el in path]
		plt.scatter(x,y)

	buff_len = len(batches)
	temp = f"logic[PWL_BRAM_DEPTH-1:0][BATCH_SIZE-1:0][SAMPLE_WIDTH-1:0] expected_batches;\nassign expected_batches = {{0,"
	batches_codes,batches_samples = temp,temp
	b_r = batches[:]
	b_r.reverse()
	for batch in b_r:
		batch.reverse()
		code = f"{batch_samples}'h"
		for val in batch: code+=toHex(val,sample_width)
		batches_codes+=code+",\n"
		samples = "{"
		for val in batch: samples+=f"{sample_width}'h"+toHex(val,sample_width)+", "
		samples = samples[:-2]
		batches_samples += samples + "},\n"
	batches_codes,batches_samples = batches_codes[:-2],batches_samples[:-2]
	batches_codes+="};"
	batches_samples+="};"

	return batches,batches_codes,batches_samples

def generate_rand_coords(sz, max_time):
	t_slope = (max_time//sz)
	coords = [[t_slope*t,0] for t in range(sz-1)]+[[max_time,0]]
	for i,el in enumerate(coords):
		if i == 0: continue
		curr_time,curr_val,prev_time= el[0],el[1],coords[i-1][0]
		if i != len(coords)-1: curr_time = curr_time + randrange(-t_slope-1,t_slope-1)
		if (curr_time <= prev_time):
			new_time = curr_time + (prev_time-curr_time) + 1
			if new_time > max_time: new_time = max_time
			curr_time = new_time
		curr_val = randrange(0,(2**(sample_width-2))-1)
		coords[i] = (curr_time,curr_val)
	return [tuple(el) for el in coords]

def generate_test(sz,mx_tm,plot=True,display_in_ns=True,provided_coords = None, verbose=False, do_cpy=False):
	if provided_coords:
		coords = provided_coords
		path,path_hex = mk_path(provided_coords)
	else:
		coords = generate_rand_coords(sz,mx_tm)
		path,path_hex = mk_path(coords)
	path_hex.reverse()
	out = "//DMA BUFFER TO SEND\n"
	out+=fmt_hxpath([hex(el) for el in path_hex])

	b,bc,bs = mk_expected_out(path,plot,display_in_ns)
	out+=f"\n//EXPECTED OUTPUT\n{bs}"
	if (verbose): print(out)
	if (do_cpy): cb_copy(out)
	out = ""
	if (verbose): print("\n\nFOLLOWING PATH: (time,val,slope)")
	path_out = ""
	for i,el in enumerate(path): path_out = path_out + f"{el} --> " if (i%5 != 0 or i == 0) else path_out + f"{el}\n"
	path_out = path_out[:-5] if path_out[-2 ] == ">" else path_out
	if (verbose): print(rf"{path_out}")

	if (verbose): print("\n\nWave period:")
	T = 1/clk
	w_T = len(b)*T
	w_Tm,w_Tn = round((w_T/1e-6),2),round((w_T/1e-9),2)
	if (verbose): print(f"{w_Tm} us, {w_Tn} ns\n")

	num_of_samples = int(w_T/T)
	s,_,_ = util.calc_pwl_BRAM_util(w_T)
	print(s)
	if (verbose) and do_cpy: print("Outputs copied into clipboard")
	return b, path, coords

def formatted_path_to_coords(fmt_path):
	path = "["
	fmt_path = fmt_path.replace("\n"," --> ")
	for tup in fmt_path.split("-->"):
		tup = tup.replace(" ", "")
		path+=tup+","
	path = path[:-1] + "]"
	path = eval(path)
	path = [el[:-1] for el in path]
	return path


sz,mx_tm= 5,15412
# batches, path, coords = generate_test(sz,mx_tm)


fmt_path = """(0, 0, 3) --> (347, 1025, 2707) --> (348, 3732, 33) --> (680, 14530, -20) --> (987, 8278, 4435) --> (988, 12713, -13)
	(1596, 5069, 55) --> (1795, 15952, -49) --> (1796, 15903, -43) --> (2106, 2679, 16) --> (2368, 6917, 1)
	(2673, 6977, -140) --> (2709, 1941, 12) --> (3097, 6791, -4043) --> (3098, 2748, 13) --> (3370, 6308, 4)
	(3712, 7677, 5) --> (4039, 9221, -59) --> (4186, 492, 8) --> (4466, 2610, 7440) --> (4467, 10050, -23)
	(4716, 4305, -23) --> (4830, 1645, 1) --> (5069, 1680, 17) --> (5662, 11647, -8) --> (5917, 9619, -57)
	(5957, 7324, 24) --> (6276, 14974, -3) --> (6668, 13631, 6) --> (6827, 14599, -3) --> (6931, 14245, -14)
	(7203, 10468, 19) --> (7426, 14647, -39) --> (7754, 1979, 8765) --> (7755, 10744, -28) --> (8039, 2704, 1)
	(8250, 2925, 16) --> (8658, 9337, -177) --> (8707, 679, 24) --> (9078, 9762, -52) --> (9094, 8928, 15)
	(9249, 11185, 6) --> (9783, 14268, -620) --> (9784, 13648, -28) --> (10141, 3803, 17) --> (10382, 7807, 53)
	(10425, 10075, 10) --> (10966, 15594, -60) --> (11171, 3241, 34) --> (11371, 10084, -8432) --> (11372, 1652, 45)
	(11515, 8023, -8) --> (12070, 3804, 2) --> (12316, 4387, -4) --> (12562, 3429, 3587) --> (12563, 7016, -19)
	(12877, 1036, 6) --> (12913, 1267, 26) --> (13379, 13418, -33) --> (13559, 7427, 22) --> (13936, 15737, -9)
	(14027, 14910, -103) --> (14166, 624, 1) --> (14598, 1044, 36) --> (14872, 10893, -1) --> (15144, 10869, -31)
	(15412, 2431, 0)"""


# coords = formatted_path_to_coords(fmt_path)
# coords = [(0, 0), (940, 2156), (1880, 4333), (2820, 6489), (3780, 8645), (4720, 10823), (5660, 12979), (6600, 15135), (7620, 13529), (8059, 11309), (8500, 9111), (10540, 9702), (11260, 11668), (11980, 13634), (12200, 11605), (12260, 295), (14380, 21), (16420, 232), (18460, 422), (19540, 2473), (19560, 6151), (19760, 8434), (19820, 10210), (19880, 11986), (19980, 15304), (22100, 15664), (24200, 16023), (26320, 16383), (28180, 14818), (28320, 12408), (28460, 9998), (28620, 7589), (28760, 5179), (28900, 2769), (29760, 0)]
# coords = [(0,0),(8000,(2**14-1)/1.1), (6000+5000, (2**14-1)/2.9),(3500+9000+20000,0)]
# coords = [(0, 0), (1711, 334), (3404, 236), (5116, 118), (6828, 0), (6960, 4739), (6979, 11289), (7148, 11092), (8841, 11426), (10703, 11584), (12566, 11741), (13657, 10128), (13788, 8221), (13901, 6313), (14165, 4189), (14390, 2202), (15839, 3579), (16516, 5310), (17193, 7040), (17983, 9932), (18510, 11466), (19056, 13019), (19263, 16383), (19582, 13786), (19921, 11171), (20636, 5329), (21106, 3422), (21953, 2222), (23100, 2596), (24267, 2989), (25414, 3382), (26580, 3756), (27728, 4149), (28894, 4543), (29760, 0)]
coords = [(0, 0), (1174, 11671), (2348, 12463), (3522, 13254), (4198, 16651), (4678, 19256), (5140, 21861), (5603, 24492), (6065, 27097), (6528, 29702), (7417, 27173), (7737, 24722), (8058, 22270), (8378, 19818), (8645, 22270), (8662, 26382), (8680, 30493), (8929, 27735), (9321, 25258), (9712, 22806), (10192, 25028), (10406, 27761), (10601, 30519), (11313, 28067), (11562, 25488), (11793, 22908), (12451, 26331), (12647, 25947), (12843, 25564), (12878, 22934), (12949, 20354), (13038, 17749), (13127, 15144), (13359, 12233), (13394, 0), (14853, 5235), (14977, 11875), (16311, 10471), (16596, 11543), (17788, 15681), (19247, 20916), (20705, 26152), (22253, 24619), (22609, 22423), (22964, 20227), (23249, 17085), (23267, 32767), (25597, 21529), (25935, 20814), (26255, 20099), (26593, 19384), (26931, 18669), (27269, 17979), (27589, 17264), (27927, 16549), (28265, 15834), (28603, 15144), (28923, 14429), (29261, 13714), (29760, 0)]
batches, path, coords = generate_test(0,0, display_in_ns=False, provided_coords=coords,verbose=True)
path,path_hx = mk_path(coords)
print(path_hx)






