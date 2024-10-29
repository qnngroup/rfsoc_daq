import time
import numpy as np
import matplotlib.pyplot as plt
from rfsoc_daq_overlay import DAQOverlay, ns_to_samp, get_savefile, clog2

class ShiftregTester(DAQOverlay):
    """Overlay for testing the shift register.
    
    Augments DAQOverlay with a few extra methods for generating pulses and visualizing results
    """
    def __init__(self,
             bitfile_name: str,
             verbose: bool = False,
             **kwargs):
        super().__init__(bitfile_name, verbose, **kwargs)
        
    def generate_shiftreg_pulses(self, pulse_param_ns):
        reallocate = False
        for depth in self._awg_frame_depths:
            if depth != self._awg_frame_depth_max:
                reallocate = True
                break
        if reallocate:
            if self.verbose:
                print(f"WARNING: AWG frame depths not maximal, reallocating")
            self.allocate_awg_memory([self._awg_frame_depth_max]*self._num_channels)
        # do random pulses on DAC0, clock pulses on DAC1, DAC2, DAC3 (DAC1, DAC3 same phase as DAC0, DAC2 180deg out of phase)
        clock_period = ns_to_samp(pulse_param_ns[4], self._dac_fsamp)
        channel_size = self._awg_frame_depth_max*self._dac_parallel_samples
        num_pulses = channel_size//clock_period
        # ignore pulse_param_ns[3] delay and substitute 0 and pulse_param_ns[4]/2 (period / 2)
        phi1_param_ns = pulse_param_ns.copy()
        phi2_param_ns = pulse_param_ns.copy()
        phi1_param_ns[3] = 0
        phi2_param_ns[3] = pulse_param_ns[4]/2
        phi1_pulse = self.generate_pulse(phi1_param_ns, self._dac_fsamp)
        phi2_pulse = self.generate_pulse(phi2_param_ns, self._dac_fsamp)
        bitstring = np.random.randint(2, size=(num_pulses,))
        self._awg_buffer[0:num_pulses*clock_period] = np.kron(bitstring, phi1_pulse)
        for i in range(1, 4):
            start = i*channel_size
            end = start+num_pulses*clock_period
            self._awg_buffer[start:end] = np.tile(phi1_pulse if i != 2 else phi2_pulse, num_pulses)
            if i < 3:
                # clear end pulses on input/clk1/clk2
                self._awg_buffer[end-clock_period:end] = 0
            else:
                # clear beginning pulse on clkro
                self._awg_buffer[start:start+clock_period] = 0
        return bitstring
    
    def single_shiftreg_measurement(self,
                                    expt_name: str,
                                    adc_save_channels: list[int],
                                    pulse_param_ns: list[float],
                                    dac_amplitudes_mV: list[float],
                                    discriminator_thresholds: list[list[int]],
                                    discriminator_delays: list[list[int]],
                                    discriminator_sources: list[int],
                                    adc_atten_dB: list[float],
                                    dac_bias_correction: list[float],
                                    dac_scale_per_mV: list[float]):
        """Test shiftreg with a PRBS data stream
        
        Arguments:
            expt_name (str): name of experiment, e.g. sr0a
            adc_save_channels (list[int]): which ADC channels to save (0-7: raw ADC output, 8-15 diff. output)
            pulse_param_ns (list[float]): [rise, hold, fall, init delay, period] of waveform in ns
            dac_amplitudes_mV (list[float]): [input, clk1, clk2, clkro] amplitude in mV
            discriminator_thresholds (list[list[int]]): [[low, ...], [high, ...]] low and high discriminator thresholds
            discriminator_delays (list[list[int]]): [[start, ...], [stop, ...]] pre- and post-event extension of capture
            discriminator_sources (list[int]): event source for each discriminator channel
            adc_atten_dB (list[float]): between 0 and 32 dB, attenuation for each channel
            dac_bias_correction (list[float]): offset correction for DACs
            dac_scale_per_mV (list[float]): conversion between mV and full-scale input for amplitude of pulses
            
        Returns:
            savefile (str): name of file (located in data/) with saved data
        """
        device_name = f'SPG717_single_{expt_name}'
        savefile = get_savefile(device_name)
        active_channels = 2 ** clog2(len(adc_save_channels))
        if active_channels > self._num_channels:
            raise ValueError("can only save up to 8 channels")
        if len(discriminator_thresholds[0]) > active_channels or len(discriminator_thresholds[1]) > active_channels:
            raise ValueError("discriminator_thresholds has too many elements; please specify more save channels")
        if len(discriminator_delays[0]) > active_channels or len(discriminator_delays[1]) > active_channels:
            raise ValueError("discriminator_delays has too many elements; please specify more save channels")
        if len(discriminator_sources) > active_channels:
            raise ValueError("discriminator_sources has too many elements; please specify more save channels")
        ### Initialization ###
        self.stop_awg() # stop the AWG to make sure we return to DMA_IDLE state
        self.reset_readout() # reset capture state machines
        self.reset_capture()
        ### AWG setup ###
        self.set_awg_triggers([1] + [0]*7) # set the trigger to output a 1 only at the beginning of a burst, only on channel 0
        num_bursts = 64 # if num_bursts = 0, run for 2^64 - 1 cycles, basically forever
        self.set_awg_burst_length([num_bursts]*8)
        self.dac_mux_select([0,1,2,3,4,5,6,7])
        bitstring = self.generate_shiftreg_pulses(pulse_param_ns)
        ### Set output amplitudes ####
        # extra divide by 2 to correct for error in prescaler
        self.set_dac_scale_offset(dac_scale_per_mV * np.array(dac_amplitudes_mV + [0]*4) / 2, dac_bias_correction)
        ### Set up capture buffer ###
        self.set_capture_channel_count(active_channels)
        self.adc_mux_select(adc_save_channels+[0]*(self._num_channels - len(adc_save_channels))) # ADC0, ADC1, ADC2, diff(ADC2)
        self.bypass_discriminators(0x0) # don't bypass any discriminators
        self.set_discriminator_thresholds(
            discriminator_thresholds[0] + [0]*(self._num_channels - len(discriminator_thresholds[0])),
            discriminator_thresholds[1] + [0]*(self._num_channels - len(discriminator_thresholds[1]))
        )
        self.set_discriminator_delays(
            discriminator_delays[0] + [0]*(self._num_channels - len(discriminator_delays[0])),
            discriminator_delays[1] + [0]*(self._num_channels - len(discriminator_delays[1])),
            [0]*8
        )
        self.set_discriminator_event_sources(
            discriminator_sources+[0]*(self._num_channels - len(discriminator_sources))
        )
        # set capture to trigger from AWG channel 0 only
        self.configure_capture_trigger(0x1, 'or')
        self.arm_capture()
        self.set_vga_atten_dB(adc_atten_dB)
        ### Start capture ###
        self.send_awg_data()
        self.start_awg()
        time.sleep(0.001) # wait a bit to make sure we actually save some data
        dma_exit_code = self.get_dma_error()
        if dma_exit_code != 0 or self.verbose:
            print(f'AWG DMA transfer exit code = {dma_exit_code}')
        self.stop_capture()
        self.start_readout()
        write_depths = self.receive_adc_data(False)
        timestamps, samples = self.get_samples_and_timestamps_from_adc_data(write_depths)
        np.savez(f'data/{savefile}',
                 awg_buffer=self._awg_buffer,
                 bitstring=bitstring,
                 timestamps=np.asarray(timestamps, dtype=object),
                 samples=np.asarray(samples, dtype=object),
                 active_channels=active_channels,
                 discriminator_thresholds=discriminator_thresholds,
                 discriminator_delays=discriminator_delays,
                 discriminator_sources=discriminator_sources,
                 dac_amplitudes_mV=dac_amplitudes_mV,
                 pulse_param_ns=pulse_param_ns,
                 adc_atten_dB=adc_atten_dB,
                 dac_bias_correction=dac_bias_correction,
                 dac_scale_per_mV=dac_scale_per_mV,
        )
        return savefile
 
    def plot_shiftreg_experiment(self, savefile: str, t0: float, trange: list[float]):
        f = np.load(f'data/{savefile}.npz', allow_pickle=True)
        active_channels = f['active_channels']
        fig, ax = plt.subplots(2,1,sharex=True,figsize=(12,8),dpi=90)
        dac_channel_size = self._dac_parallel_samples*self._awg_frame_depth_max
        tvec_awg = np.linspace(0,dac_channel_size/self._dac_fsamp,dac_channel_size,endpoint=False)
        awg_buffer = f['awg_buffer']
        dac_labels = ["input", "clk1", "clk2", "clkro"]
        for channel in range(4):
            data = awg_buffer[channel*dac_channel_size:(channel+1)*dac_channel_size]
            ax[0].plot(t0*1e6 + tvec_awg*1e6, 0.8 * (data/2**15) - channel, label=dac_labels[channel])
        ax[0].legend()
        
        timestamps = f['timestamps']
        samples = f['samples']
        tvecs = self._get_tvecs_from_timestamps([0,1,2,3], timestamps, [len(s) for s in samples])
        adc_labels = ["shunt1", "shunt2", "output", "ch4"]
        yoffset = 0
        prev_min = 0
        for channel in range(4):
            if len(samples[channel]) == 0:
                continue
            data = np.int16(samples[channel])/2**15
            yoffset += np.max(data - yoffset) - prev_min
            data -= 1.1*yoffset
            prev_min = np.min(data)
            ax[1].plot(tvecs[channel]*1e6, data, '.', alpha=0.2, label=adc_labels[channel])
        ax[1].legend(loc='lower right')
        ax[0].set_xlim(trange[0], trange[1])
        ax[1].set_xlabel('t [us]')
        titlestr = f"""{savefile}
        input, clk1, clk2, clkro amplitudes (uA) = {f['dac_amplitudes_mV']/1e3/50*1e6}
        thresholds_low = {f['discriminator_thresholds'][0]}
        thresholds_high = {f['discriminator_thresholds'][1]}
        delays_start = {f['discriminator_delays'][0]}
        delays_stop = {f['discriminator_delays'][1]}
        """
        fig.suptitle(titlestr)
        plt.tight_layout()
        plt.savefig(f'figures/{savefile}.png')