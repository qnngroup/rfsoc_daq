import pwl_wrapper as c
import pwl_wrapper_python as p
from random import randrange as rr
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties

def gen_rand_coords(avg_dt=100,T=500,n=5,max_val=2**15-1):
    coords = [(0,0)]
    abs_t = 0
    for i in range(n):
        t = rr(1,avg_dt)
        x = rr(0,max_val)
        abs_t+=t
        coords.append((x,abs_t))
    return coords

def test_avg(n,test_num=50,scale=1e6):
    intvs = []
    for i in range(test_num):
        coords = gen_rand_coords(n=n)
        intv = p.main(coords)*scale
        intvs.append(intv)
    return sum(intvs)/len(intvs)
# times = []
# sizes = [10, 30, 50, 100, 300, 500, 1000, 1300, 1500, 5000, 10000, 15000]
# for s in sizes:
#     avg_intv = test_avg(s)
#     times.append(avg_intv)

# font = FontProperties()
# font.set_family('serif')
# font.set_name('Times New Roman')

# plt.plot(sizes,times)
# plt.ylabel(r"Function Time (us)",fontsize=17,fontproperties=font,fontweight='light')
# plt.xlabel(r"Input Size",fontsize=17,fontproperties=font,fontweight='light')
# t = test_avg(5000)
# plt.title(f"1000 samples => {round(t)} us (Python Algorithm)",fontsize=20,fontproperties=font)

coords = [(0,0),(96,48),(116,58),(122,64), (10,176),(0,181),(0,192)]
pwl_cmds = [(0,2,48,1),(96,2,10,0),(116,1,6,0),(122,-1,112,1),(10,-2,5,0),(0,0,11,0)]
coords.reverse()
path,l,intv = p.main(coords)
print(path[:l])