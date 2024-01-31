import random as r
import time
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
import numpy as np
import os
import pickle
import pwl_formatter as pwlf
import magic_pen
from addr_layout import *

fake_mem = dict()
for a in addr_map:
    if a == "max_burst_size": val = 20
    elif a == "mem_size": val = 256
    elif a == "ila_burst_size": val = 0
    elif a == "scale_dac_out": val = 0
    elif a == "mapped_addr_ceiling": val = -2
    elif a == "abs_addr_ceiling": val = -1
    else: val = -1
    fake_mem[addr_map[a]] = val
for idx in range(addr_map["mem_test_base"], addr_map["abs_addr_ceiling"]): fake_mem[idx] = 100
addr_debug = False
IS_TEST = True
class DataAcquisitionOverlay():
    def __init__ (self, bit_file,download=False,ps_int_name='ps_interface_0'):
        # Expected Devices: leds, switches, buttons
        # Produced Drivers: sys_driver, led_driver, switch_driver, button_driver
        # To set leds as output, write 0x0 at 0x4. 0x1 to set as input.
        if (download): print(f"Downloading {bit_file}...")
        else: print(f"Opening {bit_file}")
        print("Done. Initializing dacOverlay")

        self.dac_samples = sampleSet("dac")
        self.maxBurstSize = self.read(addr_map['max_burst_size'])
        self.mem_size = self.read(addr_map["mem_size"])
        self.currBurstSize = self.maxBurstSize
        self.is_triggered = 0
        print("Overlay Successfully Instantiated")
    def write(self,offset,val):
        if (offset >= addr_map["mem_test_base"] and offset < addr_map["abs_addr_ceiling"]):
            fake_mem[offset] = val - 10
            fake_mem[offset+4] = val + 10
        else: fake_mem[offset] = val
        addr = "NAN"
        diffs = []
        for a in addr_map:
            if addr_map[a] == offset: addr = a
            else:
                if addr_map[a] > offset: break
                diffs.append((abs(addr_map[a]-offset), a))
        if addr == "NAN":
            min_el = min(diffs,key=lambda x:x[0])
            addr = f"{min_el[1]}+{(min_el[0])//4}"
        if (addr_debug): print(f"Wrote {hex(val)} to address {addr}")
    def read(self, offset):
        addr = "NAN"
        for a in addr_map:
            if addr_map[a] == offset: addr = a
        if (addr_debug): print(f"Reading from address {addr}")
        elif offset == addr_map['ila_resp_valid']:
            if len(self.dac_samples.samples) == (self.currBurstSize)*batch_size: return 0
            else: return 1
        elif offset == addr_map['ila_resp']: return r.randrange(0,100)
        else: return fake_mem[offset]

    def rst(self):
        self.write(addr_map['rst'],1)
        self.dac_samples.clear()
        self.currBurstSize = self.maxBurstSize
        self.is_triggered = 0
    def hlt_dac(self): self.write(addr_map['hlt_dac'],1)
    def set_trigger(self):
        if (self.is_triggered == 0):
            self.write(addr_map['set_trigger'],1)
            self.is_triggered = 1

    def produce_rand_samples(self,seed,verbose=False):
        for i in range(batch_size):
            addr = addr_map['seed_base'] + 4*i
            data = seed+(i*r.randrange(0,seed)%0xffff)
            self.write(addr,data)
        addr = addr_map['seed_valid']
        self.write(addr,1)
        if (verbose): print("Seeds Sent, PL Notified")

    def collect_ila_samples(self, total, verbose=True):
        if total > (self.maxBurstSize*batch_size): total = (self.maxBurstSize*batch_size)
        self.dac_samples.clear()
        ilaRespValid = False
        t0 = time.time()
        while (not ilaRespValid):
            if (not IS_TEST and time.time() - t0 > 5): return -1
            ilaRespValid = self.read(addr_map["ila_resp_valid"])
        lim = 10

        t0 = time.time()
        while (ilaRespValid):
            if IS_TEST: time.sleep(1e-3)
            elif (time.time() - t0 > 5): return -1
            new_sample = self.read(addr_map["ila_resp"])
            self.dac_samples.record_sample(new_sample)
            ilaRespValid = self.read(addr_map["ila_resp_valid"])
            sampleLen = len(self.dac_samples.samples)
            if (not ilaRespValid and verbose): print(f"Collected {sampleLen} samples")
            if (not verbose): continue
            p = round((sampleLen/total)*100)
            if (p > lim):
                print(f"{p}% Complete...{sampleLen} samples recieved")
                lim+=10
        self.is_triggered = 0
        return 0

    def run_random_wave(self,seed,verbose=True):
        self.produce_rand_samples(seed,verbose=verbose)
        if (self.is_triggered):
            error = self.collect_ila_samples(self.currBurstSize*batch_size, verbose)
            return error
        return 0

    def run_triangle_wave(self, verbose=True):
        addr = addr_map["triangle_wave"]
        self.write(addr,1)
        if (self.is_triggered):
            error = self.collect_ila_samples(self.currBurstSize*batch_size, verbose)
            return error
        return 0

    def prep_pwl(self, coords):
        self.write(addr_map["pwl_prep"],1)
        path,path_hx = pwlf.mk_path(coords)
        buff_size = len(path_hx)
        # pwl_cmd_buff = allocate(shape=(buff_size,), dtype=np.uint32)
        # for i in range(buff_size): pwl_cmd_buff[i] = path_hx[i]
        if IS_TEST:
         dma_send = "self.pwl_dma_driver.sendchannel\ndma_send.transfer(pwl_cmd_buff)"
         print(f"Sending {path_hx}")
        # self.pwl_dma_driver.sendchannel
        # dma_send.transfer(pwl_cmd_buff)

    def run_pwl(self): self.write(addr_map["run_pwl"],1)

    def change_burst_size(self, newSize, verbose=True):
        if newSize > self.maxBurstSize: newSize = self.maxBurstSize
        self.write(addr_map["ila_burst_size"], newSize)
        sampleSize = int(newSize*batch_size)
        self.currBurstSize = newSize
        if verbose: print(f"Ila will now {newSize} lines ({sampleSize} samples)")

    def set_scale(self, newScale):
        addr = addr_map["scale_dac_out"]
        self.write(addr, newScale)

    def idle_mode(self):
        print("Entering Idle Wave Production Mode. Press Space to exit")
        prev_bs = self.currBurstSize
        self.change_burst_size(0,verbose=False)
        wave_funcs = [("run_random_wave",0xBEEF), ("run_triangle_wave", None)]
        i = 0
        while True:
            func_call = f"{wave_funcs[i][1]}("
            i = (i+1)%2
            if wave_funcs[i][0]: func_call+=f"{wave_funcs[i][0]}"
            eval(func_call+")")
            if keyboard.is_pressed('space'):
                print("Leaving Idle Mode")
                self.change_burst_size(prev_bs,verbose=False)
                return 0
            t0 = time.time()
            while time.time() - t0 < 3: continue

    def run_mem_test_simple(self,verbose=True):
        addr = addr_map["mem_test_base"]
        passed,failed = 0,0
        for i in range(50):
            data = r.randrange(0,(2**15)-1)
            self.write(addr,data)
            rd1 = self.read(addr)
            rd2 = self.read(addr+4)
            read_vals = f"Sent {hex(data)}: {hex(addr)} = {hex(rd1)}, {hex(addr+4)} = {hex(rd2)}"
            if rd1 == data -10 and rd2 == data + 10:
                if (verbose): print("Success! "+read_vals)
                passed+=1
            else:
                if (verbose): print("Fail :(( "+read_vals)
                failed+=1
            addr+=4
        print(f"Test Complete. {passed} Passed, {failed} Failed")
        return passed, failed

    def test_print(cond, name, c, w, i=None):
        if i: name+=f"_{i}"
        if cond:
            out = print(f"{name}(+) ", end = "")
            c+=1
        else:
            print(f"{name}(-) ", end = "")
            w+=1
        return c, w
    def run_full_test(self,verbose=True):
        self.rst()
        correct,wrong, total_wrong, total_right = 0,0,0,0
        # Consts Check
        const_addrs = [("max_burst_size",max_ila_burst_size), ("mem_size",mem_size), ("abs_addr_ceiling",-2), ("ila_burst_size",0)]
        for i,addr in enumerate(const_addrs):
            val = self.read(addr_map[addr[1]])
            correct, wrong = test_print(val == addr[0], "consts", correct, wrong,i=i)
        if wrong != 0: print("\nConstant Addresses Test Passed")
        else: print("\nConstant Addresses Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # Other Address Check
        for i, addr in enumerate(addr_map):
            if addr in [el[1] for el in const_addrs]: continue
            val = self.read(addr)
            correct, wrong = test_print(val == -1, "addr", correct, wrong, i=i)
        if wrong != 0: print("\nAddress Access Test Passed")
        else: print("\nAddress Access Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # Changing ila burst check
        for i in range(1,5):
            self.change_burst_size(i, verbose=False)
            curr_ila_bsize = self.read(addr_map["ila_burst_size"])
            correct, wrong = test_print(curr_ila_bsize == i, "change_ila_burst", correct, wrong,i=i)
        if wrong != 0: print("\nChange ILA Burst Test Passed")
        else: print("\nChange ILA Burst Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # Changing scale check
        for i in range(1,5):
            self.set_scale(i)
            curr_scale = self.read(addr_map["scale_dac_out"])
            correct, wrong = test_print(curr_scale == i, "change_scale", correct, wrong,i=i)
        if wrong != 0: print("\nChange Scale Test Passed")
        else: print("\nChange Scale Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # Simple Mem Test
        correct, wrong = self.run_mem_test_simple(verbose=False)
        if wrong != 0: print("\nSimple Mem Test Passed")
        else: print("\nSimple Mem Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # Reset Test
        self.rst()
        for i, addr in enumerate(addr_map):
            default_val = -2
            for el in const_addrs:
                if el[1] == addr:
                    default_val = el[0]
                    break
            val = self.read(addr)
            correct, wrong = test_print(val == default_val, "rst", correct, wrong,i=i)
        if wrong != 0: print("\nReset Test Passed")
        else: print("\nReset Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # ila_sample collector test
        step = self.maxBurstSize//10 if self.maxBurstSize//10 != 0 else 1
        for i in range(1, self.maxBurstSize, step):
            self.change_burst_size(i,verbose=False)
            self.set_trigger()
            error = self.run_random_wave(0xBEEF, verbose=False)
            sampleLen = len(self.dac_samples.samples)
            correct, wrong = test_print(error == 0 and sampleLen == (self.currBurstSize*batch_size), "change_scale", correct, wrong,i=i)
        if wrong != 0: print("\nIla Sample Collector Test Passed")
        else: print("\nIla Sample Collector Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # Rand Wave test
        self.change_burst_size(1,verbose=False)
        self.set_trigger()
        self.run_random_wave(0xABCD,verbose=False)
        samples = self.dac_samples.samples
        rand_seeds = []
        addr = addr_map["seed_base"]
        for i in range(batch_size):
            rand_seeds.append(self.read(addr))
            addr+=4
        correct, wrong = test_print(samples[:16] == rand_seeds, "rand", correct, wrong)
        if wrong != 0: print("\nRandom Wave Test Passed")
        else: print("\nRandom Wave Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0
        # Triangle Wave Test
        self.set_trigger()
        self.run_triangle_wave(0xABCD,verbose=False)
        samples = self.dac_samples.samples
        exp_trig_out = [i for i in range(64)]
        correct, wrong = test_print(samples[:16] == exp_trig_out, "triangle", correct, wrong)
        if wrong != 0: print("\nTriangle Wave Test Passed")
        else: print("\nTriangle Wave Test Failed")
        if wrong != 0: total_wrong+=1
        else: total_right+= 1
        correct,wrong = 0,0

        print(f"Passed {total_right}, Failed {total_wrong} tests! {round((total_right/(total_right+total_wrong))*100,2)}%")
        self.idle_mode()

class sampleSet():
    def __init__ (self,name="default"):
        self.name = name
        self.samples = []
        self.times = []
        directory = f"{name}_stats"
        if not os.path.exists(directory): os.makedirs(directory)

    def record_sample(self,new_sample):
        self.samples.append(new_sample)
        t0 = time.time()
        if (len(self.times) == 0):
            self.times.append((t0,0))
        else:
            prevTime,prevTick = self.times[-1]
            dt = (t0 - prevTime)*1e3
            currTick = prevTick + dt
            self.times.append((t0,currTick))

    def clear(self):
        self.samples = []
        self.times = []

    def display_stats(self,samp_stream_pltLabels = [None]*2,verbose=False):
        if (len(self.samples) == 0):
            if (verbose): print("No samples to plot")
            return []
        #### Raw Sample Stream Plot ####
        plt.clf()
        plt.plot(self.samples)
        font = FontProperties()
        font.set_family('serif')
        font.set_name('DejaVu Sans')
        title, ylabel = [el if el else "" for el in samp_stream_pltLabels]
        plt.xlabel("Sample number",fontsize=20,fontproperties=font,fontweight='light')
        plt.ylabel(ylabel,fontsize=20,fontproperties=font,fontweight='light')
        plt.title(title,fontsize=21,fontproperties=font,fontweight='bold')
        file_name = f"{self.name}_stats/samples.png"
        try:
            with open(file_name,'x') as f: pass
        except: pass
        plt.savefig(file_name)
        if verbose: plt.show()
        plt.clf()

        #### Sample Acquision Rates Plot ####
        file_name = f"{self.name}_stats/sample_rates.png"
        rates = []
        N = 1
        ts = [el[1]*1e-3 for el in self.times]
        times = []
        for t in ts:
            if t == 0: continue
            times.append(t/1e-3)
            rates.append((N/t)/1000)
            N+=1
        plt.xlabel("Time (ms)",fontsize=20,fontproperties=font,fontweight='light')
        plt.ylabel("Rates (kSamples/sec)",fontsize=20,fontproperties=font,fontweight='light')
        plt.plot(times,rates)
        try:
            with open(file_name,'x') as f: pass
        except: pass
        plt.savefig(file_name)
        if verbose: plt.show()

        exSamples = self.samples[:16]
        self.clear()
        return exSamples
