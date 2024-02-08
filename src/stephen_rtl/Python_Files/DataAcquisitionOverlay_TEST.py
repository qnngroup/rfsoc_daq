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
from colorama import Fore, Back, Style
fake_mem = dict()
read_only = ["max_dac_burst_size", "mem_size", "firmware_version", "abs_addr_ceiling"]
addr_debug = False

class dmaObj():
	def __init__(self):
		self.sendchannel = sendObj()
class sendObj():
	def transfer(self,li):
		print("DMA transfering...")
		for el in li: print(f"{el}, ",end="")
		print("DMA done")

class DataAcquisitionOverlay():
	def __init__ (self, bit_file,download=False,ps_int_name='ps_interface_0'):
		# Expected Devices: leds, switches, buttons
		# Produced Drivers: sys_driver, led_driver, switch_driver, button_driver
		# To set leds as output, write 0x0 at 0x4. 0x1 to set as input.
		if (download): print(f"Downloading {bit_file}...")
		else: print(f"Opening {bit_file}")
		print("Done. Initializing dacOverlay")
		print("Resetting System")
		self.rst()
		self.pwl_dma_driver = dmaObj()
		self.max_dac_bs = self.read(addr_map["max_dac_burst_size"])
		self.mem_size = self.read(addr_map["mem_size"])
		self.curr_dac_bs = self.max_dac_bs
		raw_vn = self.read(addr_map["firmware_version"])
		self.firmware_version = self.raw_2_pretty_vn(raw_vn)
		print(f"Data Acquisition System (DAS) Overlay Successfully Instantiated.\nDAS Verison Number: {self.firmware_version}")

	def fake_mem_reset(self):
		global fake_mem
		fake_mem = dict()
		for i in range(256):
			a = addr_map_inverted[4*i]
			if a == "max_dac_burst_size": val = max_dac_burst_size
			elif a == "mem_size": val = mem_size
			elif a == "dac_burst_size": val = 0
			elif a == "scale_dac_out": val = 0
			elif a == "firmware_version": val = raw_fv
			elif a == "abs_addr_ceiling": val = -2
			else: val = -1
			fake_mem[4*i] = val

	def write(self,offset,val):
		addr = addr_map_inverted[offset]
		if (offset >= addr_map["mem_test_base"] and offset < addr_map["mem_test_end"]):
			fake_mem[offset] = val - 10
			fake_mem[offset+4] = val + 10
		elif (offset == 0):
			self.fake_mem_reset()
			print("Reset System")
		elif (addr not in read_only and offset < addr_map["mapped_addr_ceiling"]):
			fake_mem[offset] = val
			if (addr_debug): print(f"Wrote {hex(val)} to address {addr}")
		else:
			if (addr_debug): print(f"Count not write to addr {addr}")
	def read(self, offset):
		addr = addr_map_inverted[offset]
		if (addr_debug): print(f"Reading from address {addr}")
		return fake_mem[offset]

	def rst(self):
		self.write(addr_map['rst'],1)
		self.curr_dac_bs = 0

	def raw_2_pretty_vn(self,raw_vn):
		raw_vn = hex(raw_vn)[2:]
		raw_vn = raw_vn[0] + "." + raw_vn[1:]
		return eval(raw_vn)

	def hlt_dac(self): self.write(addr_map['hlt_dac'],1)

	def produce_rand_samples(self,seed,verbose=False):
		for i in range(batch_size):
			addr = addr_map['seed_base'] + 4*i
			data = seed+(i*r.randrange(0,seed)%0xffff)
			self.write(addr,data)
		addr = addr_map['seed_valid']
		self.write(addr,1)
		if (verbose): print("Seeds Sent, PL Notified")

	def run_random_wave(self,seed,verbose=True):
		self.produce_rand_samples(seed,verbose=verbose)

	def run_triangle_wave(self, verbose=True):
		addr = addr_map["triangle_wave"]
		self.write(addr,1)

	def prep_pwl(self, coords):
		self.write(addr_map["pwl_prep"],1)
		path,path_hx = pwlf.mk_path(coords)
		buff_size = len(path_hx)
		pwl_cmd_buff = allocate(shape=(buff_size,), dtype=np.uint32)
		for i in range(buff_size): pwl_cmd_buff[i] = path_hx[i]
		dma_send = self.pwl_dma_driver.sendchannel
		dma_send.transfer(pwl_cmd_buff)

	def run_pwl(self): self.write(addr_map["run_pwl"],1)

	def change_burst_size(self, newSize, verbose=True):
		if newSize > self.max_dac_bs: newSize = self.max_dac_bs
		self.write(addr_map["dac_burst_size"], newSize)
		sampleSize = int(newSize*batch_size)
		self.curr_dac_bs = newSize
		if verbose: print(f"Dac will now burst {newSize} batches ({sampleSize} samples)")

	def set_scale(self, newScale):
		addr = addr_map["scale_dac_out"]
		self.write(addr, newScale)

	def idle_mode(self):
		print("Entering Idle Wave Production Mode. ctl-C to exit")
		prev_bs = self.curr_dac_bs
		self.change_burst_size(0,verbose=False)
		wave_funcs = [("run_random_wave",0xBEEF), ("run_triangle_wave", None)]
		i = 0
		try:
			while True:
				func_call = f"self.{wave_funcs[i][0]}("
				if wave_funcs[i][1]: func_call+=f"{wave_funcs[i][1]},"
				eval(func_call+"verbose=False)")
				t0 = time.time()
				while time.time() - t0 < 3: continue
				i = (i+1)%2
		except KeyboardInterrupt:
			self.write(addr_map["hlt_dac"],1)
			self.change_burst_size(prev_bs,verbose=False)
			print("Leaving Idle Mode")


	def run_simple_mem_test(self,verbose=True):
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
		if (verbose): print(f"Test Complete. {passed} Passed, {failed} Failed")
		return passed, failed

	def test_print(self, cond, name, c, w, i=None):
		if i: name+=f"_{i}"
		if cond:
			print(Fore.GREEN+f"{name}(+) ", end = "")
			c+=1
		else:
			print(Fore.RED+f"{name}(-) ", end = "")
			w+=1
		return c, w
	def run_full_test(self,verbose=True):
		self.rst()
		correct,wrong, total_wrong, total_right = 0,0,0,0
		# Firmware Version Check
		raw_vn = self.read(addr_map["firmware_version"])
		vn = self.raw_2_pretty_vn(raw_vn)
		correct,wrong = self.test_print(vn == firmware_version, "fm", correct, wrong)
		if wrong == 0: print(Fore.GREEN+"\nFirmware Version Firmware Version Test Passed\n")
		else: print(Fore.RED+"\nFirmware Version Firmware Version Test Failed\n")
		if wrong != 0: total_wrong+=1
		else: total_right+= 1
		correct,wrong = 0,0
		# Consts Check
		const_addrs = [("max_dac_burst_size",max_dac_burst_size), ("mem_size",mem_size), ("abs_addr_ceiling",-2), ("dac_burst_size",0), ("scale_dac_out",0)]
		for i,addr in enumerate(const_addrs):
			val = self.read(addr_map[addr[0]])
			correct, wrong = self.test_print(val == addr[1], "consts", correct, wrong,i=i)
		if wrong == 0: print(Fore.GREEN+"\nConstant Addresses Test Passed\n")
		else: print(Fore.RED+"\nConstant Addresses Test Failed\n")
		if wrong != 0: total_wrong+=1
		else: total_right+= 1
		correct,wrong = 0,0
		# Other Address Check
		for i, addr in enumerate(addr_map_inverted):
			if addr >= addr_map["mem_test_base"]: continue
			self.write(addr,69)
		for i, addr in enumerate(addr_map_inverted):
			if addr >= addr_map["mem_test_base"]: continue
			val = self.read(addr)
			if addr == 0x1a8:
				i = 10
			if addr_map_inverted[addr] == "max_dac_burst_size": cond = val == max_dac_burst_size
			elif addr_map_inverted[addr] == "mem_size": cond = val == mem_size
			elif addr_map_inverted[addr] == "abs_addr_ceiling": cond = val == -2
			elif addr_map_inverted[addr] == "rst": cond = val == -1
			elif addr_map_inverted[addr] == "firmware_version": cond = float(self.raw_2_pretty_vn(val)) == firmware_version
			elif (addr >= addr_map["mapped_addr_ceiling"] and addr < addr_map["mem_test_base"]) or  (addr >= addr_map["mem_test_end"] and addr < addr_map["abs_addr_ceiling"]): cond = val == -1
			else: cond = val == 69
			correct, wrong = self.test_print(cond, "addr", correct, wrong, i=f"{i}_{hex(addr)}")
		if wrong == 0: print(Fore.GREEN+"\nAddress Access Test Passed\n")
		else: print(Fore.RED+"\nAddress Access Test Failed\n")
		if wrong != 0: total_wrong+=1
		else: total_right+= 1
		correct,wrong = 0,0
		# Changing dac burst check
		for i in range(1,5):
			self.change_burst_size(i, verbose=False)
			curr_dac_bsize = self.read(addr_map["dac_burst_size"])
			correct, wrong = self.test_print(curr_dac_bsize == i, "change_dac_burst", correct, wrong,i=i)
		if wrong == 0: print(Fore.GREEN+"\nChange DAC Burst Test Passed\n")
		else: print(Fore.RED+"\nChange DAC Burst Test Failed\n")
		if wrong != 0: total_wrong+=1
		else: total_right+= 1
		correct,wrong = 0,0
		# Changing scale check
		for i in range(1,5):
			self.set_scale(i)
			curr_scale = self.read(addr_map["scale_dac_out"])
			correct, wrong = self.test_print(curr_scale == i, "change_scale", correct, wrong,i=i)
		if wrong == 0: print(Fore.GREEN+"\nChange Scale Test Passed\n")
		else: print(Fore.RED+"\nChange Scale Test Failed\n")
		if wrong != 0: total_wrong+=1
		else: total_right+= 1
		correct,wrong = 0,0
		# Simple Mem Test
		correct, wrong = self.run_simple_mem_test(verbose=False)
		if wrong == 0: print(Fore.GREEN+"Simple Mem Test Passed\n")
		else: print(Fore.RED+f"Simple Mem Test Failed ({correct} correct, {wrong} wrong)\n")
		if wrong != 0: total_wrong+=1
		else: total_right+= 1
		correct,wrong = 0,0
		# Reset Test
		self.rst()
		for i, addr in enumerate(addr_map_inverted):
			if (addr == 0x18c):
				j = 4
			val = self.read(addr)
			if addr_map_inverted[addr] == "max_dac_burst_size": cond = val == max_dac_burst_size
			elif addr_map_inverted[addr] == "mem_size": cond = val == mem_size
			elif addr_map_inverted[addr] == "abs_addr_ceiling": cond = val == -2
			elif addr_map_inverted[addr] == "firmware_version": cond = float(self.raw_2_pretty_vn(val)) == firmware_version
			elif addr_map_inverted[addr] == "dac_burst_size": cond = val == 0
			elif addr_map_inverted[addr] == "scale_dac_out": cond = val == 0
			else: cond = val == -1
			correct, wrong = self.test_print(cond, "rst", correct, wrong,i=f"{i}_{hex(addr)}")
		if wrong == 0: print(Fore.GREEN+"\nReset Test Passed\n")
		else: print(Fore.RED+"\nReset Test Failed\n")
		if wrong != 0: total_wrong+=1
		else: total_right+= 1
		correct,wrong = 0,0

		print(Style.RESET_ALL)
		print(f"Passed {total_right}, Failed {total_wrong} tests! {round((total_right/(total_right+total_wrong))*100,2)}%")
		self.idle_mode()
