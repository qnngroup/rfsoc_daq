import mouse
import keyboard
from math import sqrt,atan,sin,cos,degrees,radians, ceil
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
import numpy as np
import random
import time
from IPython.display import clear_output

import warnings
warnings.filterwarnings("ignore")

xMax = 1706                 # Pixels in screen (x dir)
yMax = 1065                 # Pixels in screen (y dir)
distThresh = 100            # Samples points must be this far apart to be considered adding anything

clk = 150e6
batch_width = 1024
sample_width = 16
max_dac_out = (2**(sample_width-1))-1
batch_samples = batch_width/sample_width

class Point():
    def __init__ (self,pnt):
        self.x = pnt[0] 
        self.y = pnt[1]

    def __str__(self): return f"{(self.x,self.y)}"

    def cpy(self):
        return Point((self.x,self.y))

    def set(self,newPnt):
        self.x = newPnt.x
        self.y = newPnt.y

    def update(self,dCoor):
        newPnt = self.cpy()
        newPnt.x+=dCoor[0]
        newPnt.y+=dCoor[1]
        return newPnt

    def pntDiff(self,p2): return p2.x - self.x,p2.y - self.y

    def mkLine(self,p2):
        dx,dy = self.pntDiff(p2)
        m = dy/dx
        b = p2.y-m*p2.x
        return m,b

    def toTup(self): return (round(self.x),round(self.y))

    def __eq__(self,p2):
        return self.x == p2.x and self.y == p2.y

def dist(p1,p2):
    return sqrt((p2.x-p1.x)**2 + (p2.y-p1.y)**2)

def split(li):
    lix,liy = [],[]
    for el in li:
        lix.append(el[0])
        liy.append(el[1])
    return lix,liy

def errorf(f,points):
    e = [abs(f(x)-y) for x,y in points]
    return sum(e)/len(e)

def straighten(points_in, errorThreshold=0.25, stoppingPercent = 0.2,showTruePath=True):
    points = []
    pointsX = []
    # Perturbe duplicates in x (so no infinite slopes)
    for el in points_in:
        points.append(el)
        pointsX.append(el[0])
    while len(pointsX) != len(set(pointsX)):
        dup = [i for i, x in enumerate(pointsX) if i != pointsX.index(x)]
        randVal = 0
        while randVal == 0: randVal = random.uniform(-0.1,0.1)
        for i in dup: pointsX[i]+=randVal
    # Find lines for sequences of points_in
    optFuncs = []
    endLen = ceil(stoppingPercent*len(points_in))
    while len(points) > 1:
        errors = []
        startingPoint = 0
        maxWindowSize = len(points)
        # Find all errors for a given window of the path
        for i in range(startingPoint,maxWindowSize):
            window = points[startingPoint:i+1]
            px,py = split(window)
            m,b = np.polyfit(px,py,deg=1)
            f = lambda x: m*x+b
            errors.append(errorf(f,window))
        # Normalize and integrate these erorrs.
        errors = [el/sum(errors) for el in errors]
        error_int = [sum(errors[:i]) for i in range(len(errors))]

        # Look for the point where the integral of this curve is less than the errorThreshold (25% or so)
        opt_i = len(points)
        for i in range(len(error_int)):
            if error_int[i] < errorThreshold: continue
            opt_i = i-1
            break
        # At a certain time, just accept the rest of the remaining points to optimize a line through, or else you'll keep halving (1/2->1/4->/8 ->...)
        if len(points) <= endLen or opt_i == 0: opt_i = len(points)
        optWindow = points[startingPoint:opt_i]
        px,py = split(optWindow)
        m,b = np.polyfit(px,py,deg=1)
        optFuncs.append([optWindow,(m,b)])

        points = points[opt_i:]

    # Reconstruct the results
    # First squeeze in intersecting lines in optFuncs, then you can easily connect them.
    fullOptFuncs = []
    for i,el in enumerate(optFuncs):
        window,(m,b) = el
        if i == len(optFuncs) - 1:
            fullOptFuncs.append([window,(m,b)])
            break
        windowX = [el[0] for el in window]
        start = min(windowX)

        nxtPnt = optFuncs[i+1][0][0]
        interM,interB = Point(window[-1]).mkLine(Point(nxtPnt))
        interWindow = [window[-1],nxtPnt]
        fullOptFuncs+=[[window,(m,b)],[interWindow,(interM,interB)]]

    # Connect the lines described in fullOptFuncs by determining the correct domains based on their intersections
    def intersection(m1,b1,m2,b2):
        y = (m2*b1)/(m2-m1)+(m1*b2)/(m1-m2)
        x = (b1-b2)/(m2-m1)
        return x,y

    someStartVal = points_in[0][0]
    someEndVal = points_in[-1][0]
    firstWindow, (firstM,firstB) = fullOptFuncs[0]
    graphInstructions = [[someStartVal,-1,firstM,firstB,len(firstWindow)]] # graphInstructions[i] = [startX,endX,m_i,b_i,numOfPoints]
    for i,el in enumerate(fullOptFuncs):
        if i == len(fullOptFuncs) - 1: break
        window,(m,b) = el
        nxtWindow,(nxtM,nxtB) = fullOptFuncs[i+1]
        interPoint = intersection(m,b,nxtM,nxtB)
        end = interPoint[0]
        graphInstructions[-1][1] = end
        graphInstructions.append([end,-1,nxtM,nxtB,len(nxtWindow)])
    graphInstructions[-1][1] = someEndVal

    # Use the instructions to graph each line in the appropriate range, and save the new points

    plt.xlim((0,xMax))
    plt.ylim((0,yMax))
    adjustedPoints = []
    for start,end,m,b,windowLen in graphInstructions:
        x = np.linspace(start,end,windowLen)
        y = [m*el+b for el in x]
        for pnt in zip(x,y):
            if Point(pnt) in adjustedPoints: continue
            adjustedPoints.append(Point(pnt))
        plt.plot(x,y,'-g.')

    if not showTruePath:
        plt.show()
        return adjustedPoints

    px,py = split(points_in)
    plt.xlim((0,xMax))
    plt.ylim((0,yMax))
    plt.plot(px,py,'--.r')
    plt.show()

    return adjustedPoints

def mk_pwl_coords(points,T,make_periodic=True):
    points.sort(key=lambda el:el[0])
    base_time,base_val = points[0][0],min(points,key=lambda el:el[1])[1]
    points = [(time-base_time,val-base_val) for time,val in points]
    if make_periodic: points[0] = (0,0)

    times,adj_times,vals,adj_vals = [],[],[],[]
    for el in points:
        if el[0] in times: continue
        times.append(el[0])
        vals.append(el[1])

    if make_periodic:
        diffs = []
        for i in range(len(times)):
            if (i+1) < len(times): diffs.append(times[i+1]-times[i])
        avg_diff = int(sum(diffs)/len(diffs))
        times.append(times[-1]+avg_diff)
        vals.append(0)

    T = int(batch_samples*(T/(1/clk)))
    max_time = max(times)
    for t in times: adj_times.append(int(T*(t/max_time)))
    times = adj_times

    max_val = max(vals)

    for v in vals: adj_vals.append(int(max_dac_out*(v/max_val)))
    vals = adj_vals
    return [(times[i],vals[i]) for i in range(len(times))]

def drawPath(fitterAcc,wave_period,showTruePath=True,make_periodic=True):
    actual_path = []
    ctrlPressed = False
    print("Press Space to quit, ctl to start drawing")
    while (True):
        if keyboard.is_pressed('space'):
            clear_output()
            return None
        if keyboard.is_pressed('ctrl'):
            if not ctrlPressed:
                print("Recording...")
                actual_path = []
                ctrlPressed = True
            x,y = mouse.get_position()
            y = yMax - y
            p = Point((x,y))
            if not actual_path:
                actual_path.append(p)
                continue
            if dist(p,actual_path[-1]) > distThresh and p.x > actual_path[-1].x: actual_path.append(p)
        else:
            if ctrlPressed:
                if len(actual_path) > 1:
                    path = [eval(str(el)) for el in actual_path]
                    plt.clf()
                    try:
                        adjusted_points = straighten(path,1-fitterAcc,showTruePath=showTruePath)
                    except ZeroDivisionError:
                        print("Sorry, the path was too verticle and I couldn't fix the dx/0 error. Try again?")
                        ctrlPressed = False
                        continue
                    adjusted_points = [el.toTup() for el in adjusted_points]
                    coords = mk_pwl_coords(adjusted_points,wave_period,make_periodic=make_periodic)
                    print("Press d to display constructed pwl wave\nPress g to draw again")
                    while True:
                        if keyboard.is_pressed('g'):
                            clear_output()
                            print("Draw again")
                            break
                        if keyboard.is_pressed('d'):
                            clear_output()
                            plt.clf()
                            font = FontProperties()
                            font.set_family('serif')
                            font.set_name('Times New Roman')
                            plt.xlabel(r"Time (us)",fontsize=17,fontproperties=font,fontweight='light')
                            plt.ylabel(r"% Of Max DAC Voltage",fontsize=17,fontproperties=font,fontweight='light')
                            plt.plot([((el[0]//64)*(1/clk))/(1e-6) for el in coords],[(el[1]/max_dac_out)*100 for el in coords],"-*")
                            plt.show()
                            send = input("Send? y/n ")
                            if send == "y":
                                clear_output()
                                return coords
                            clear_output()
                            print("Draw again")
                            break
                else:
                    print("Path was too short")
                clear_output(wait = True)
                ctrlPressed = False
    print("-1")
    return

# print(drawPath(0.99,3.gd1e-6,make_periodic=True))
