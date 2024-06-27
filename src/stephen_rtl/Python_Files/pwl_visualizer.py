import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
from fpga_constants import *
from math import log2
from sys import path
path.insert(0, r'C:\Users\skand\OneDrive\Documents\GitHub\rfsoc_daq\src\stephen_rtl\Python_Files/cython_files')
import pwl_wrapper_python as p
import pwl_wrapper as c 
from random import randrange as rr 

def flatten(li):
    out = []
    for el in li:
        if type(el) == list: out += flatten(el)
        else: out.append(el)
    return out 

def mk_delays(dli = None,n = 10, delay_range=(0,5)):
    if dli:
        dli.reverse()
    else:       
        dli = []
        for i in range(n): dli.append(rr(delay_range[0], delay_range[1]))
    bit_width = int(log2(max(dli)))
    out = f"logic[{len(dli)-1}:0][{bit_width-1}:0] delays = {{"
    for el in dli: out+= f"{bit_width}'d{el}, "
    return out[:-2] + "};"

def assign_packed_probe(probe_len, names, cond=None):
    if len(names) == 2: template = lambda i: f"assign test{i} = ({cond})? {names[0]}[{i}] : {names[1]}[{i}];\n"
    else: template = lambda i: f"assign test{i} = {names[0]}[{i}];\n"
    out = "logic[15:0] "
    for i in range(probe_len): out+=f"test{i},"
    out = out[:-1]+";\n\n"
    for i in range(probe_len): out+=template(i)
    return out

def get_wave(coords_in=None, path=None):
    if path is None:
        if coords_in is None: return None
        coords = coords_in[:]
        coords.reverse()
        intv,fpga_cmds = p.main(coords)
        path = c.fpga_to_pwl(fpga_cmds)
    waves,coords_decoded = p.decode_pwl_cmds(path)
    if coords_in is None: coords = coords_decoded
    return waves,coords,path

def plot_wave(coords, waves, simple_plot=True):
    flat_wave = flatten(waves)
    split = lambda li: ([el[0] for el in li],[el[1]for el in li])
    if coords is not None:
        x,t = split(coords)
        plt.scatter(t,x)
    if simple_plot: plt.plot(flat_wave)
    else:
        abs_t = 0
        for wave in waves:
            t = [abs_t+i for i in range(len(wave))]
            f = [el for el in wave]
            plt.plot(t,f)
            abs_t+=len(wave)
            
def make_expc_test(path,waves):
    cmd = "dma_buff = {"
    path = [(x,p.create_slope_obj(slope),dt,sb) for x,slope,dt,sb in path]
    fpga_cmds = p.mk_fpga_cmds(path)
    for el in fpga_cmds:
        cmd+=f"64'd{el}, "
    cmd = cmd[:-2]+"};"
    flat_wave = flatten(waves)
    expc_wave = "expc_wave = {"
    flat_wave.reverse()
    for el in flat_wave: expc_wave+=f"{el},"
    expc_wave = expc_wave[:-1]+"};"
    return cmd,expc_wave

def cmds_to_path(cmds):
    cmds = eval(cmds.replace("64'd","").replace("{","[").replace("};","]"))
    return c.fpga_to_pwl(cmds)
    
mv = max_voltage
coords = None
path = None
cmds = None

# coords = [(0,0), (mv,64), (mv,1050),(mv/4,1150), (mv/4,2000), (mv/2,2400),(mv/2,3000), (0,4000), (0,4500)]
# coords = [(0,0), (-6,5),(6,16),(10,40),(0,64),(10,74), (-15, 84), (10,130), (0,135)]
# coords = [(0, 0), (-1760, 42), (-7823, 63), (10099, 92), (-11395, 131), (-14864, 165), (31756, 174), (23458, 249), (-29850, 327), (-8388, 345), (-24704, 372), (4581, 471), (-23581, 538), (6848, 622), (-23950, 656), (-27731, 716), (7791, 788), (-13726, 806), (-3027, 815), (-5832, 860), (-19937, 951), (-29623, 1045), (-11459, 1139), (-12895, 1233), (-16154, 1258), (-16353, 1266), (25784, 1286), (-26716, 1288), (3537, 1310), (12971, 1311), (4453, 1401), (-16336, 1493), (9867, 1586), (15805, 1601), (-3561, 1678), (-18282, 1719), (8408, 1749), (10175, 1829), (4553, 1873), (-8570, 1918), (-19377, 1948), (13855, 2013), (-32620, 2112), (30056, 2175), (16947, 2203), (-19117, 2288), (8908, 2356), (-29130, 2372), (-9543, 2463), (13296, 2501), (25241, 2578)]
coords = [(5000,0), (5000,15), (2000,16),(2000,31), (100,32), (100,47)]
# coords = [(0,0), (100,5),(100,9),(-100,11), (-100,14),(0,15)]


# path = [(0,2,8,0),(16,-10,8,0)]
# path = [(0, 8.600006103515625,16,1)]
# path = [(11,-4.79291,16,1)]

# cmds = "{64'd281294997160001, 64'd18069567424937721876, 64'd17951628349657120780, 64'd17464113689994264606, 64'd16244767985191878658, 64'd16418719520799064097, 64'd755200016804479000, 64'd2842894897700012040, 64'd2222242574053015617, 64'd15704893958493437958, 64'd15239617750855319578, 64'd14866381931736989729, 64'd14407014769745199114, 64'd14262922267812954130, 64'd8938800360205123588, 64'd8876594390352068737, 64'd6883470080263913490, 64'd6603118543320449038, 64'd5256542254736670849, 64'd11391570847122128910, 64'd10044721139929120786, 64'd13065229115011170322, 64'd16086010848604454926, 64'd14895371697118380065, 64'd12173790147303047176, 64'd11493187519535513624, 64'd12492423686858342561, 64'd706784937006465038, 64'd1289716537991692306, 64'd224896701095280737, 64'd12992601644690636820, 64'd11809284203747475468, 64'd12421210803116441729, 64'd500182589466738716, 64'd1927818225008836612, 64'd1417785567209128001, 64'd11705699585811546209, 64'd10854237781261811736, 64'd10641163613516201992, 64'd11196513742566326401, 64'd1637342058495737864, 64'd2193247884373262360, 64'd16602233417168453644, 64'd14583223649140736018, 64'd17595000526463500290, 64'd17577549077907439681, 64'd17016006499369680920, 64'd16805462818789785608, 64'd16630948333229179041, 64'd13140658622017044494, 64'd12835258495441502226, 64'd12574331192030724257, 64'd10254132959004786698, 64'd10108611668543668246, 64'd10707027469030523041, 64'd15058349134000553990, 64'd15221603724946374682, 64'd15165590204580954273, 64'd14821627783040532482, 64'd14817405164110413854, 64'd14267121584641081364, 64'd13900078668065013772, 64'd13858138896535126020, 64'd13843792828412067868, 64'd3699434667760025612, 64'd7257719531592744964, 64'd10926864502073393168, 64'd14023370720867319836, 64'd995617511347060738, 64'd3651292991395856386, 64'd3624552868608344225, 64'd1493224344955256850, 64'd1253688575746703374, 64'd808395162590445729, 64'd14166916082301468682, 64'd13848570064282845206, 64'd14720861017109168289, 64'd2618562918457802756, 64'd2777315295438438428, 64'd4337249616368893954, 64'd4448992401676435486, 64'd3386987314547130465, 64'd18435765469405642780, 64'd17444691614516838404, 64'd17242592581238587457, 64'd14008445098833149966, 64'd13300822370574598162, 64'd15554592509096820769, 64'd1114644728863457290, 64'd2366641699048259606, 64'd2435040118388949121, 64'd2833045735457816586, 64'd2864288814227980310, 64'd2468816471949508673, 64'd1317865292179636226, 64'd1281835791432417310, 64'd50664243300007969, 64'd17184046075677638684, 64'd16034783451085537284, 64'd15832121467853864993, 64'd14209699702093643800, 64'd12992605645838745608, 64'd13568221973212037217, 64'd2029155302958694426, 64'd3900115261054320646, 64'd3503798493845717185, 64'd9265034606286864481, 64'd4259565095441268766, 64'd8460291364180525058, 64'd8328561075079938081, 64'd6220032024540413974, 64'd4770436083013386250, 64'd4173427657410085025, 64'd13065788714026926209, 64'd2043228626037637128, 64'd2507650356767359000, 64'd12924476294875316232, 64'd10247378926584463384, 64'd10974428791428087937, 64'd14851746595617374238, 64'd15760630952348155906, 64'd15929797413351260225, 64'd2896661566717755402, 64'd3742491956622589974, 64'd4222688266890969217, 64'd7017171835674361860, 64'd7104709887153668124};"

if cmds: 
    coords = None
    path = cmds_to_path(cmds)

waves,coords,path = get_wave(coords_in = coords, path=path)
plot_wave(coords,waves)
cmd,expc_wave = make_expc_test(path,waves)
print(cmd)
print(expc_wave)


#####################################################################################################
# simple_plot = True
# desired_period = None
# fpga_cmds,fw = plot_path(coords,simple_plot=simple_plot,desired_period=desired_period)
# print("\n",fpga_cmds)
# fpga_cmds.reverse()
# print(c.rtl_cmd_formatter(fpga_cmds),len(fpga_cmds))

# dli = [1,2,1,2,2,1]
# print(mk_delays(n=len(fpga_cmds),delay_range=(0,150)),"\n")
# plt.axhline(-,color="orange", alpha=0.4)
# print(assign_packed_probe(16,["batch_out","intrp_batch"],"gen_mode"))






# def plot_path(coords,simple_plot=True,desired_period=None):
#     if desired_period:
#         req_max_t = desired_period//dac_T
#         given_max_t = coords[-1][1]
#         coords = [(el[0],int(req_max_t*(el[1]/given_max_t))) for el in coords]
    
#     coords.reverse()
#     intv,fpga_cmds = c.main(coords)
#     path = c.fpga_to_pwl(fpga_cmds)
#     waves = c.decode_pwl_cmds(path)
#     flat_wave = flatten(waves)
#     if desired_period:
#         flat_wave = [(el/max_voltage)*100 for el in flat_wave]
#         ts = [round((i*dac_T)/1e-6,3) for i in range(len(flat_wave))]
#     else: ts = [i for i in range(len(flat_wave))]
    
#     dense_packs,sparse_packs = 0,0
#     for x,slope,dt,sb in path:
#         if sb == 0: dense_packs+=1
#         else: sparse_packs+=1
#     total_bytes = ((dense_packs*batch_width) + (sparse_packs*dma_data_width))/8

#     period = round((dac_T*len(flat_wave))/1e-6,3)
#     font = FontProperties()
#     font.set_family('serif')
#     font.set_name('Times New Roman')
#     if desired_period: 
#         plt.xlabel(r"$\mu s$",fontsize=17,fontproperties=font,fontweight='light')
#         plt.ylabel("% of Max DAC Voltage",fontsize=17,fontproperties=font,fontweight='light')
#     plt.title(f"PWL Wave Period: {period} us\n{total_bytes/1e3} KB required",fontsize=20,fontproperties=font,fontweight='heavy')
#     if desired_period: split = lambda li: ([(el[0]/max_voltage)*100 for el in li],[(el[1]*dac_T)/1e-6 for el in li])
#     else: split = lambda li: ([el[0] for el in li],[el[1]for el in li])
#     x,t = split(coords)
#     plt.scatter(t,x)
#     # print(flat_wave,"\n")
#     if simple_plot: plt.plot(ts,flat_wave)
#     else:
#         abs_t = 0
#         for wave in waves:
#             if desired_period:
#                 t = [((abs_t+i)*dac_T)/1e-6 for i in range(len(wave))]
#                 f = [(el/max_voltage)*100 for el in wave]
#             else: 
#                 t = [abs_t+i for i in range(len(wave))]
#                 f = [el for el in wave]
#             plt.plot(t,f)
#             abs_t+=len(wave)
#     # print(path)
#     return fpga_cmds,flat_wave




