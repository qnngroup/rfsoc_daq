from DataAcquisitionOverlay_TEST import *
# from DataAcquisitionOverlay import *
from IPython.display import clear_output

download = input("Download bitstream? (y/n) ")
download = True if download == "y" else False

verbose = True
dacOverlay = DataAcquisitionOverlay("sys_design.bit", download = True)

seeds = [0xBEEF,0xABCD,0x1234,0xFEED,0xBEAD]
seed = seeds[0]

cmd = [""]
cmds = {k:i-i%2 for i,k in enumerate(["choose",'c',"rst",'r',"random",'rs',"trig",'t',"hlt",'h',"twave",'tw', "burstSize",'bs', "readBurstSize", "rbs", "help", "scale", "s", "simple_test", "st", "pwl_test", "tpw", "draw_pwl", "dpw", "full_test", "ft"])}
cmds['q'] = 0xaaaaaa
removeBlanks = lambda li: [el for el in li if el != '']
helpMsg = "\n\nCommands:\n\
choose n (c n) Choose the nth seed for random generator\n\
rst (r) Resets the system\n\
random (rs) Sends a random sequence of values to the DAC based on the selected seed\n\
trig (t) Sets the trigger for the onboard ila system to collect (burstSize) number of samples\n\
hlt (h) Halts the output to the DAC\n\
twave (t) Sends a triangle wave to the DAC\n\
burstSize (bs) Sets the number of samples saved by the onboard ila to be (bs) batches of samples\n\
readBurstSize (rbs) Returns the current burstSize value as well as the max\n\
scale (s) Divides the output to the dac by 2**s\n\
simple_test (st) Runs a simple memory test\n\
pwl_test (tpw) Triggers pwl sequence (testing phase)\n\
draw_pwl (dpw, T) Allows the user to draw a wave to send to the pwl (T=period of waveform in us)\n\
full_test (ft) Runs a full system test\n\n"

print("Entering Interface. Enter 'help' to display commands")

while (cmd[0] != "q"):
    cmd = removeBlanks(input("ZYNQ> ").split(' '))
    if not cmd:
        cmd = [""]
        continue
    if len(cmd) > 1: cmd[1] = eval(cmd[1])
    if (cmd[0] not in cmds):
        print("Invalid Command")
        continue

    if (cmd[0] == "help"): print(helpMsg)

    elif (cmd[0] == "choose" or cmd[0] == "c"):
        i = int(cmd[1])%len(seeds)
        seed = seeds[i]
        print(f"Selected Seed: {hex(seed)}")

    elif (cmd[0] == "burstSize" or cmd[0] == "bs"):
        if (len(cmd) != 2): print("Please select a burst size (1 arg)")
        else:
            print("Changing ila burst size")
            dacOverlay.change_burst_size(int(cmd[1]),verbose=verbose)

    elif (cmd[0] == "readBurstSize" or cmd[0] == "rbs"):
        bs,maxBs = dacOverlay.read(addr_map["ila_burst_size"]),dacOverlay.read(addr_map["max_burst_size"])
        print(f"Current samples to record: {bs*batch_size}\nMaximum samples to record: {maxBs*batch_size}")

    elif (cmd[0] == "rst" or cmd[0] == "r"):
        print("Resetting System")
        dacOverlay.rst()

    elif (cmd[0] == "random" or cmd[0] == "rs"):
        print(f"Producing random DAC samples. Seed = {hex(seed)}")
        dacOverlay.run_random_wave(seed,verbose=verbose)

    elif (cmd[0] == "trig" or cmd[0] == "t"):
        print("Setting dac_ila Trigger")
        dacOverlay.set_trigger()

    elif (cmd[0] == "hlt" or cmd[0] == "h"):
        print("Halting random DAC stream")
        dacOverlay.hlt_dac()

    elif (cmd[0] == "twave" or cmd[0] == "tw"):
        print("Initiating Triangle Wave")
        dacOverlay.run_triangle_wave(verbose=verbose)

    elif (cmd[0] == "simple_test" or cmd[0] == "st"):
        print("Beginning Simple Memory Test:")
        dacOverlay.run_simple_mem_test(verbose=verbose)

    elif (cmd[0] == "scale" or cmd[0] == "s"):
        if (len(cmd) != 2):
            print("Please provide one argument (scale factor to reduce dac output)")
            continue
        dacOverlay.set_scale(cmd[1])
        amount = 2**cmd[1] if cmd[1] <= 15 else 2**15
        print(f"Dac output divided by {amount}")

    elif (cmd[0] == "pwl_test" or cmd[0] == "tpw"):
        print("Plotting and running hardcoded pwl wave:")
        # coords = [(0, 0), (231, 3481), (611, 5940), (1220, 7271), (1241, 10669),(1561, 8000),(1681, 8000),(2041, 10669), (2046, 7271), (2545, 7271), (2811, 5940), (3200, 0)]
        # coords = [(0,0),(8000,(2**14-1)/1.1), (6000+5000, (2**14-1)/2.9),(3500+9000+20000,0)]
        coords = [(0, 0), (1174, 11671), (2348, 12463), (3522, 13254), (4198, 16651), (4678, 19256), (5140, 21861), (5603, 24492), (6065, 27097), (6528, 29702), (7417, 27173), (7737, 24722), (8058, 22270), (8378, 19818), (8645, 22270), (8662, 26382), (8680, 30493), (8929, 27735), (9321, 25258), (9712, 22806), (10192, 25028), (10406, 27761), (10601, 30519), (11313, 28067), (11562, 25488), (11793, 22908), (12451, 26331), (12647, 25947), (12843, 25564), (12878, 22934), (12949, 20354), (13038, 17749), (13127, 15144), (13359, 12233), (13394, 0), (14853, 5235), (14977, 11875), (16311, 10471), (16596, 11543), (17788, 15681), (19247, 20916), (20705, 26152), (22253, 24619), (22609, 22423), (22964, 20227), (23249, 17085), (23267, 32767), (25597, 21529), (25935, 20814), (26255, 20099), (26593, 19384), (26931, 18669), (27269, 17979), (27589, 17264), (27927, 16549), (28265, 15834), (28603, 15144), (28923, 14429), (29261, 13714), (29760, 0)]
        pwlf.generate_test(0,0,provided_coords=coords)
        plt.show()
        dacOverlay.prep_pwl(coords)

    elif (cmd[0] == "draw_pwl" or cmd[0] == "dpw"):
        if (len(cmd) != 2): print("Please enter a waveform period (us)")
        else:
            print("Entering MagicPen Interface:")
            coords = magic_pen.drawPath(0.99,eval(f"{cmd[1]}e-6"),make_periodic=True)
            dacOverlay.prep_pwl(coords)

    elif (cmd[0] == "full_test" or cmd[0] == "ft"):
        print("Running full system test:")
        dacOverlay.run_full_test(verbose=verbose)

    clear_output(wait=True)
print("Exiting Interface")
