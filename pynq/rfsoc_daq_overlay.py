import os
from datetime import datetime
from pynq import Overlay
from pynq import allocate
import xrfclk
import numpy as np
from axififo import AxiStreamFifoDriver
import matplotlib.pyplot as plt

def clog2(x):
    """Return ceil(log2(x))"""
    return int(np.ceil(np.log2(x)))

def ns_to_samp(ns, fsamp):
    """Convert ns duration to number of samples at rate fsamp"""
    return int(ns*1e-9*fsamp)

def get_savefile(device_name):
    return datetime.now().strftime("%Y%m%d_%H%M%S") + f'_{device_name}'

class DAQOverlay(Overlay):
    """Overlay for rfsoc_daq data acquisition system
    
    Attributes:
        adc_fsamp (float): sample rate of ADCs in Hz
        dac_fsamp (float): sample rate of DACs in Hz
    
    """
    def __init__(self,
                 bitfile_name: str,
                 verbose: bool = False,
                 **kwargs):
        self.verbose = verbose
        if self.verbose:
            print(f"loading bistream {bitfile_name}")
        super().__init__(bitfile_name, **kwargs)
        if self.verbose:
            print(f"loaded bistream")
            
        xrfclk.set_ref_clks(lmk_freq=122.88, lmx_freq=409.6)
        
        # TODO store these things in a register and then read them out
        self._adc_fsamp = 4.096e9 # Hz
        self._dac_fsamp = 6.144e9 # Hz

        self._dds_phase_bits = 32
        self._tri_phase_bits = 32
        self._scale_bits = 16
        self._offset_bits = 16
        self._scale_offset_int_bits = 2

        self._awg_frame_depth_max = 2048
        self._awg_frame_depths = None

        self._discriminator_max_delay = 64
        self._adc_buffer_data_depth = 4096
        self._adc_buffer_tstamp_depth = 512

        self._tstamp_width = 64
        self._sample_width = 16
        self._dac_parallel_samples = 16
        self._adc_parallel_samples = 8
        self._dac_data_width = self._dac_parallel_samples*self._sample_width
        self._adc_data_width = self._adc_parallel_samples*self._sample_width
        self._num_channels = 8
        
        # DMA IP handles
        self._awg_dma = self.dma.dma.sendchannel
        self._adc_dma = self.dma.dma.recvchannel
        
        # DMA buffers
        self._awg_buffer = None
        self.allocate_awg_memory([self._awg_frame_depth_max] * self._num_channels)
        adc_dma_bits = self._num_channels * self._adc_buffer_data_depth * self._adc_data_width
        adc_dma_bits += self._num_channels * self._adc_buffer_tstamp_depth * self._tstamp_width
        if self.verbose:
            print(f"allocating _adc_buffer with size {adc_dma_bits // 16} x 16b")
        self._adc_buffer = allocate(shape=(adc_dma_bits // 16,), dtype=np.uint16)
        
        # keep track of number of active channels
        self._active_channels = 1
        
        ###############################
        # configuration registers
        ###############################
        # awg configuration
        self._awg_burst_length = self.daq.awg_burst_length.fifo
        self._awg_frame_depth = self.daq.awg_frame_depth.fifo
        self._awg_start_stop = self.daq.awg_start_stop.fifo
        self._awg_trigger_output_mode = self.daq.awg_trigger_config.fifo
        # capture configuration
        self._capture_arm_start_stop = self.daq.capture_arm_start_stop.fifo
        self._capture_banking_mode = self.daq.capture_banking_mode.fifo
        self._capture_sw_reset = self.daq.capture_sw_reset.fifo
        self._capture_trigger_config = self.daq.capture_trigger_config.fifo
        self._readout_start = self.daq.readout_start.fifo
        self._readout_sw_reset = self.daq.readout_sw_reset.fifo
        # sample discriminator configuration
        self._discriminator_bypass = self.daq.discriminator_bypass.fifo
        self._discriminator_event_source = self.daq.discriminator_trigger_source.fifo
        self._discriminator_delays = self.daq.sample_discriminator_delays.fifo
        self._discriminator_thresholds = self.daq.sample_discriminator_thresholds.fifo
        # channel muxes
        self._receive_channel_mux = self.daq.receive_channel_mux_config.fifo
        self._transmit_channel_mux = self.daq.transmit_channel_mux.fifo
        # misc
        self._pgood = self.daq.afe_pgood
        self._lmh6401_config = self.daq.lmh6401_config.fifo
        self._dac_scale_offset = self.daq.dac_scale_offset.fifo
        self._dds_phase_inc = self.daq.dds_phase_inc.fifo
        self._tri_phase_inc = self.daq.tri_phase_inc.fifo
        
        ###############################
        # status registers
        ###############################
        self._awg_dma_error = self.daq.awg_dma_error.fifo
        self._write_depth_samples = self.daq.samples_write_depth.fifo
        self._write_depth_timestamps = self.daq.timestamps_write_depth.fifo
        
        if self.verbose:
            print("finished initializing overlay")
    
    def __del__(self):
        """Free DMA buffers"""
        if self._awg_buffer is not None:
            self._awg_buffer.freebuffer()
        self._adc_buffer.freebuffer()
        
    def _check_list_length(self, name: str, config: list):
        """Verify a list is num_channels long, throw ValueError if not"""
        if len(config) != self._num_channels:
            raise ValueError(
                f'{name} must be a list with {self._num_channels} ints, got {config}'
            )
    
    def _packetize(self, long_word: int, num_words: int):
        """Convert long_word containing num_words 32-bit ints into a list of 32-bit ints"""
        packet = []
        if self.verbose:
            print(f'packetizing word {long_word:#0{num_words*8}x} into {num_words} words')
        for word in range(num_words):
            packet.append(long_word & ((1 << 32) - 1))
            long_word >>= 32
        if long_word != 0:
            print(f'WARNING: packetize has leftover data {hex(long_word)}')
        return packet
    
    def _generate_pinc_packet(self, freqs_hz: list[float], phase_bits: int):
        """Generate phase increment word and packetize it
        
        Arguments:
            freqs_hz (list[float]): frequencies in Hz for each channel
            phase_bits (int): number of bits for fixed point representation
        """
        pinc_word = 0
        self._check_list_length('freqs_hz', freqs_hz)
        for channel, freq_hz in enumerate(freqs_hz):
            pinc = int((freq_hz / self._dac_fsamp) * (2**phase_bits))
            pinc_word |= pinc << (phase_bits * channel)
        expected_word_count = (phase_bits * self._num_channels + 31) // 32
        return self._packetize(pinc_word, expected_word_count)


    def _generate_mux_packet(self, sources: list[int], max_num_sources: int):
        """Generate mux select word and packetize it
        
        Arguments:
            sources (list[int]): desired source for each output channel
            max_num_sources (int): number of source channels
        """
        self._check_list_length('sources', sources)
        source_word = 0
        source_bits = clog2(max_num_sources)
        for channel, source in enumerate(sources):
            if source < 0 or source >= max_num_sources:
                raise ValueError(
                    f"invalid source {source}, must be between 0 and {max_num_sources}"
                )
            source_word |= source << (source_bits * channel)
        return self._packetize(source_word, (source_bits * self._num_channels + 31)//32)
    
    def receive_adc_data(self, override_write_depth_errors: bool):
        """Perform DMA to receive data from ADC.
        
        Checks if a capture was performed before running DMA
        
        Arguments:
            override_write_depth_errors (bool): if True, perform transfer regardless of write_depth status
        
        Returns:
            depth_packets (list[list[int]]): for each (timestamps, samples), a packet of write depth information
        """
        failure = False
        timestamps_write_depth = self.get_timestamps_write_depth()
        sample_write_depth = self.get_samples_write_depth()
        depths = []
        for packet in (timestamps_write_depth, sample_write_depth):
            num_packets = len(packet)
            if num_packets == 0:
                print(f"WARNING: didn't get the right number of packets for fifo, got {num_packets}")
                failure = True
            depths.append(packet)
        if not(failure) or override_write_depth_errors:
            self._adc_dma.transfer(self._adc_buffer)
        return depths
    
    def get_samples_and_timestamps_from_adc_data(self, depth_packets: list[list[int]]):
        """Split raw data from ADC into timestamps and samples
        
        Arguments:
            depth_packets (list[list[int]]): for each (timestamps, samples), a packet of write depth information
        
        Returns:
            timestamps (list[array_like]): list of arrays of timestamps for each channel
            samples (list[array_like]): list of arrays of collected samples for each channel
        """
        sample_depth_bits = clog2(self._adc_buffer_data_depth) + 1
        timestamp_depth_bits = clog2(self._adc_buffer_tstamp_depth) + 1
        buffer_midpoint = self._num_channels * self._adc_buffer_tstamp_depth * self._tstamp_width // 16
        data = []
        for i in range(2):
            data.append([])
            packet = depth_packets[i]
            if i == 0:
                depth_bits = timestamp_depth_bits
                depth_to_words = self._tstamp_width // 16
                offset = 0
                bank_size = self._adc_buffer_tstamp_depth * depth_to_words
            else:
                depth_bits = sample_depth_bits
                depth_to_words = self._adc_data_width // 16
                offset = buffer_midpoint
                bank_size = self._adc_buffer_data_depth * depth_to_words
            # merge 32-bit qtys
            depth_word = 0
            for n, word in enumerate(packet):
                depth_word |= word << (32 * n)
            mask = ((1 << depth_bits) - 1)
            total_depth = [0 for i in range(self._num_channels)]
            depth_per_bank = []
            for bank in range(self._num_channels):
                depth = (depth_word >> (bank * depth_bits)) & mask
                if depth & (1 << (depth_bits - 1)):
                    depth = bank_size // depth_to_words
                depth_per_bank.append(depth)
                channel = bank % self._active_channels
                total_depth[channel] += depth
            for channel in range(self._num_channels):
                data[-1].append(np.zeros((total_depth[channel] * depth_to_words,), dtype=np.uint16))
            for bank in range(self._num_channels):
                channel = bank % self._active_channels
                read_start = offset + (bank_size * bank)
                read_stop = offset + (bank_size * bank) + depth_per_bank[bank] * depth_to_words
                write_start = (bank // self._active_channels) * bank_size
                write_stop = (bank // self._active_channels) * bank_size + depth_per_bank[bank] * depth_to_words
                data[-1][channel][write_start:write_stop] = self._adc_buffer[read_start:read_stop]
        timestamps = [d.view(np.uint64) for d in data[0]]
        samples = data[1]
        return timestamps, samples
            
    def allocate_awg_memory(self, frame_depths: list[int]):
        """Allocate or reallocate AWG buffer based on specified frame_depths
        
        Arguments:
            frame_depths (list[int]): list of desired frame depth for each channel
        """
        if self._awg_buffer is not None:
            self._awg_buffer.freebuffer()
        total_size = 0
        self._check_list_length('frame_depths', frame_depths)
        for depth in frame_depths:
            if depth < 1 or depth > self._awg_frame_depth_max:
                raise ValueError(
                    f'depth must be on [1,{self._awg_frame_depth_max}] but got {depth}'
                )
            if depth % (self._dac_data_width//128) != 0:
                raise ValueError(
                    f'depth must be a multiple of {self._dac_data_width//128} but got {depth}'
                )
            total_size += depth*self._dac_data_width//16 # (16-bit dtype)
        if self.verbose:
            print(f'allocating _awg_buffer with size {total_size} x 16b')
        self._awg_frame_depths = frame_depths
        self._awg_buffer = allocate(shape=(total_size,), dtype=np.uint16)

    def send_awg_data(self):
        """Set AWG frame depths and perform DMA to send data to AWG"""
        if self._awg_buffer is None:
            raise ValueError(
                f"""AWG DMA buffer is not initialized, call
                ol.allocate_awg_memory(depths)
                to allocate a buffer"""
            )
        self.set_awg_frame_depth(self._awg_frame_depths)
        self._awg_dma.transfer(self._awg_buffer)
    
    def get_samples_write_depth(self):
        """Get packet of samples write depth"""
        packet = self._write_depth_samples.get_rx_fifo_pkt()
        if self.verbose:
            print(f'samples_write_depth reported: {packet}')
        return packet

    def get_timestamps_write_depth(self):
        """Get packet of timestamps write depth"""
        packet = self._write_depth_timestamps.get_rx_fifo_pkt()
        if self.verbose:
            print(f'timestamps_write_depth reported: {packet}')
        return packet

    def get_dma_error(self):
        """Get packet of AWG DMA error"""
        return self._awg_dma_error.get_rx_fifo_pkt()
    
    def start_capture(self):
        """Start capture buffer"""
        self._capture_arm_start_stop.send_tx_pkt([0x6])
        
    def arm_capture(self):
        """Arm capture buffer, but don't start capture; wait for digital trigger"""
        self._capture_arm_start_stop.send_tx_pkt([0x4])
        
    def stop_capture(self):
        """Stop capture buffer"""
        self._capture_arm_start_stop.send_tx_pkt([0x1])

    def set_capture_channel_count(self, num_channels: int):
        """Set banking mode / channel count of capture buffer"""
        if num_channels not in [1,2,4,8]:
            raise ValueError(
                f"""Incorrect number of active channels:
                {num_channels}, expected one of [1,2,4,8]
                """
            )
        banking_mode = clog2(num_channels)
        self._active_channels = num_channels
        if self.verbose:
            print(f'sending banking mode packet {banking_mode} to buffer_config.fifo')
        self._capture_banking_mode.send_tx_pkt([banking_mode])

    def reset_capture(self):
        """Reset capture FSM; will require re-arming before capture can be triggered again"""
        self._capture_sw_reset.send_tx_pkt([0x1])
        
    def reset_readout(self):
        """Reset readout FSM"""
        self._capture_sw_reset.send_tx_pkt([0x1])

    def start_readout(self):
        """Transition readout FSM from IDLE to ACTIVE"""
        self._readout_start.send_tx_pkt([0x1])

    def configure_capture_trigger(self, mask: int, mode: str):
        """Configure capture trigger manager

        Args:
            mask (int): num_channels-bit mask
            mode (str): if "and", does reduction AND after bitwise mask.
                        if "or", does reduction OR after bitwise mask
        """
        if mode.lower() not in ("and", "or"):
            raise ValueError(f'invalid mode {mode}, expected "and" or "or"')
        if mask < 0 or mask >= 2**self._num_channels:
            raise ValueError(
                f"invalid mask {hex(mask)} for number of channels {self._num_channels})"
            )
        packet = [(1 if mode.lower() == "and" else 0) << (self._num_channels + 1) | mask]
        self._capture_trigger_config.send_tx_pkt(packet)

    def set_discriminator_thresholds(self,
                                     low_thresholds: list[int],
                                     high_thresholds: list[int]):
        """Configure sample discriminator high/low thresholds

        Args:
            low_thresholds (list[int]): for each channel, all-below-low threshold
                                            to stop saving samples
            high_thresholds (list[int]): for each channel, any-above-high threshold
                                            to start saving samples
        """
        packet = []
        self._check_list_length('low_thresholds', low_thresholds)
        self._check_list_length('high_thresholds', high_thresholds)
        for channel in range(self._num_channels):
            low = low_thresholds[channel]
            high = high_thresholds[channel]
            for threshold in (low, high):
                if threshold < 0 or threshold >= 2**self._sample_width:
                    raise ValueError(
                        f"""invalid threshold ({hex(threshold)}) for channel {channel},
                        should be between 0x00 and {hex(2**self._sample_width)}
                        """
                    )
            packet.append((high << self._sample_width) | low)
        if self.verbose:
            print(f'sending packet {packet} to discriminator_thresholds')
        self._discriminator_thresholds.send_tx_pkt(packet)

    def set_discriminator_delays(self,
                                 start_delays: list[int],
                                 stop_delays: list[int],
                                 digital_delays: list[int]):
        """Configure sample discriminator delays. Each word is 8 samples for 4096 MS/s
        ADC with 512 MHz data clock.

        Args:
            start_delays (list[int]): for each channel, number of words to save before
                                        each any-above-high event
            stop_delays (list[int]): for each channel, number of words to save after
                                        each all-below-low event
            digital_delays (list[int]): number of cycles to delay digital delay by
        """
        delay_word = 0
        timer_bits = clog2(self._discriminator_max_delay)
        self._check_list_length('start_delays', start_delays)
        self._check_list_length('stop_delays', stop_delays)
        self._check_list_length('digital_delays', digital_delays)
        for channel in range(self._num_channels):
            start_delay = start_delays[channel]
            stop_delay = stop_delays[channel]
            digital_delay = digital_delays[channel]
            for delay in (start_delay, stop_delay, digital_delay):
                if delay < 0 or delay >= self._discriminator_max_delay:
                    raise ValueError(
                        f"""invalid delay ({delay}) for channel {channel},
                        should be between 0 and {self._discriminator_max_delay}"""
                    )
            delay_word |= digital_delay << ((2 + 3 * channel) * timer_bits)
            delay_word |= stop_delay << ((1 + 3 * channel) * timer_bits)
            delay_word |= start_delay << (3 * channel * timer_bits)
        packet = self._packetize(delay_word, (3 * timer_bits * self._num_channels + 31)//32)
        if self.verbose:
            print(f'sending packet {packet} to discriminator_delays')
        self._discriminator_delays.send_tx_pkt(packet)

    def set_discriminator_event_sources(self, sources: list[int]):
        """Configure sample discriminator event sources.

        Args:
            sources (list[int]): for each channel, which input channel to get any-above-high
                                    and all-below-low events from
        """
        packet = self._generate_mux_packet(sources, 2 * self._num_channels)
        if self.verbose:
            print(f'sending packet {packet} to discriminator_trigger_source')
        self._discriminator_event_source.send_tx_pkt(packet)

    def bypass_discriminators(self, bypass_mask: int):
        """Disable sample discriminator and pass samples directly through.

        Args:
            bypass_mask (int): one disable bit per channel, LSB is channel 0. If bit is set,
                                the discriminator for the corresponding channel is disabled
        """
        if bypass_mask < 0 or bypass_mask >= 2**self._num_channels:
            raise ValueError(
                f"""bypass_mask = {bypass_mask} is an invalid
                mask for channel count {self._num_channels}"""
            )
        if self.verbose:
            print(f'sending packet {[bypass_mask]} to discrimininator_bypass')
        self._discriminator_bypass.send_tx_pkt([bypass_mask])

    # receive channel mux
    def adc_mux_select(self, sources: list[int]):
        """Configure data sources for ADC channels.

        Args:
            sources (list[int]): for each channel to sample discriminator/capture buffer,
                                    selects physical ADC that provides data. Also accesses
                                    differentiator (and in the future, FIR filter) data by
                                    providing a source > num_channels
        """
        packet = self._generate_mux_packet(sources, 2 * self._num_channels)
        if self.verbose:
            print(f'sending packet {packet} to receive_channel_mux')
        self._receive_channel_mux.send_tx_pkt(packet)

    # VGA attenuation
    def set_vga_atten_dB(self, atten_dB: list[float]):
        """Set attenuation (in dB) for variable gain amplifiers.

        Args:
            atten_dB (list[float]): for each channel, desired attenuation in dB.
                                        will be rounded to the nearest integer
        """
        self._check_list_length('atten_dB', atten_dB)
        for channel, atten in enumerate(atten_dB):
            atten = round(atten)
            if atten < 0 or atten > 32:
                raise ValueError(
                    f"atten_dB {atten} out of range, pick a number between 0 and 32dB"
                )
            packet = 0x0200 | (atten & 0x3f) # address 0x02, 6-bit data atten_dB
            packet |= channel << 16 # address/channel ID is above 16-bit address+data
            if self.verbose:
                print(f'sending packet {packet} to lmh6401_config')
            self._lmh6401_config.send_tx_pkt([packet])

    def set_awg_frame_depth(self, depths: list[int]):
        """Configure depth of AWG data frames.

        Arguments:
            depths (list[int]): for each channel, determine number of samples before
                                AWG loops. DMA data must match this setting.
        """
        frame_depth_word = 0
        depth_bits = clog2(self._awg_frame_depth_max)
        self._check_list_length('depths', depths)
        for channel, depth in enumerate(depths):
            if depth < 1 or depth > self._awg_frame_depth_max:
                raise ValueError(f'invalid frame depth ({depth}) for channel ({channel})')
            frame_depth_word |= (depth-1) << (depth_bits*channel)
        if self.verbose:
            print(f'sending frame_depth word = {hex(frame_depth_word)} to awg_frame_depth.fifo')
        expected_word_count = (depth_bits*self._num_channels + 31) // 32
        self._awg_frame_depth.send_tx_pkt(self._packetize(frame_depth_word, expected_word_count))
        
    def set_awg_triggers(self, trigger_modes: list[int]):
        """Configure trigger output of AWG.

        Arguments:
            depths (list[int]): for each channel, set trigger output mode
                                    - 0: no output
                                    - 1: trigger outputted only at the start of a burst
                                    - 2: trigger outputted at the start of each frame in a burst
        """
        trigger_word = 0
        self._check_list_length('trigger_modes', trigger_modes)
        for channel, mode in enumerate(trigger_modes):
            if mode < 0 or mode > 2:
                raise ValueError(
                    f'invalid selection for trigger mode ({mode}) on channel ({channel})'
                )
            trigger_word |= mode << (2*channel)
        if self.verbose:
            print(f'sending trigger_word {hex(trigger_word)} to awg_trigger_config.fifo')
        self._awg_trigger_output_mode.send_tx_pkt([trigger_word])

    def set_awg_burst_length(self, burst_lengths):
        """Configure AWG burst length in number of frames.

        Arguments:
            depths (list[int]): 64-bit quantity for each, 0 -> 2**64 - 1
                                which is effectively infinite
        """
        packet = []
        self._check_list_length('burst_lengths', burst_lengths)
        for burst_length in burst_lengths:
            packet.append(burst_length & ((1 << 32) - 1))
            packet.append((burst_length >> 32) & ((1 << 32) - 1))
        if self.verbose:
            print(f'sending packet {packet} to awg_burst_length.fifo')
        self._awg_burst_length.send_tx_pkt(packet)

    def start_awg(self):
        """Start AWG. Will send triggers to capture buffer if they have been configured"""
        self._awg_start_stop.send_tx_pkt([2])

    def stop_awg(self):
        """Stop AWG"""
        self._awg_start_stop.send_tx_pkt([1])

    def set_dac_scale_offset(self, scales: list[float], offsets: list[float]):
        """Set gain and offset correction for DAC output

        Args:
            scales (list[float]): number between -1 and 1 for each channel
            offsets (list[float]): number between -1 and 1 for each channel
        """
        scale_offset_word = 0
        self._scale_frac_bits = self._scale_bits - self._scale_offset_int_bits
        self._offset_frac_bits = self._offset_bits - self._scale_offset_int_bits
        word_bits = self._scale_bits + self._offset_bits
        max_fs_val = 2**(self._scale_offset_int_bits - 1)
        self._check_list_length('scales', scales)
        self._check_list_length('offsets', offsets)
        for channel in range(self._num_channels):
            # scale is 2Q16, so quantize appropriately
            quant_scale = int(scales[channel] * 2**self._scale_frac_bits)
            quant_offset = int(offsets[channel] * 2**self._offset_frac_bits)
            for value in (scales[channel], offsets[channel]):
                if (value >= max_fs_val or value < -max_fs_val):
                    raise ValueError(f'cannot quantize {value} to {self._scale_offset_int_bits}Qx')
            if quant_scale < 0:
                quant_scale += 2**self._scale_bits
            if quant_offset < 0:
                quant_offset += 2**self._offset_bits
            scale_offset_word |= quant_scale << (word_bits * channel + self._offset_bits)
            scale_offset_word |= quant_offset << (word_bits * channel)
        if self.verbose:
            print(f'sending scale_word {hex(scale_offset_word)} to dac_scale_config.fifo')
        expected_word_count = (word_bits * self._num_channels + 31) // 32
        self._dac_scale_offset.send_tx_pkt(self._packetize(scale_offset_word, expected_word_count))

    # DDS and triangle wave generators
    def set_dds_freq(self, freqs_hz: list[float]):
        """Set frequency of DDS sinusoid generator

        Args:
            freqs_hz (list[float]): frequencies in Hz for each channel
        """
        packet = self._generate_pinc_packet(freqs_hz, self._dds_phase_bits)
        if self.verbose:
            print(f'sending dds_phase_inc packet {packet}')
        self._dds_phase_inc.send_tx_pkt(packet)

    def set_tri_freq(freqs_hz):
        """Set frequency of triangle wave generator

        Args:
            freqs_hz (list[float]): frequencies in Hz for each channel
        """
        packet = self._generate_pinc_packet(freqs_hz, self._tri_phase_bits)
        if self.verbose:
            print(f'sending tri_phase_inc packet {packet}')
        self._tri_phase_inc.send_tx_pkt(packet)
        
    def dac_mux_select(self, sources: list[int]):
        """Configure data sources for DAC channels.

        Args:
            sources (list[int]): for each channel to DAC, selects whether it is fed by
                                    AWG, triangle wave, or DDS sinusoid.
        """
        packet = self._generate_mux_packet(sources, 3 * self._num_channels)
        if self.verbose:
            print(f'sending packet {packet} to transmit_channel_mux.fifo')
        self._transmit_channel_mux.send_tx_pkt(packet)
    
    def afe_power_status(self):
        """Get status of power rails.
        
        Returns:
            pgood (int): bitstring. For nominal operation, all bits should be set
        """
        # xor 2.7V pgood since its logic level is inverted
        return (self._pgood.channel1[1:7].read() ^ 0x4)
    
    def _get_tvecs_from_timestamps(self,
                                   channel_list: list[int],
                                   timestamps: list[np.ndarray],
                                   num_samples: list[int]):
        """Generate time vector from timestamp data
        
        Arguments:
            channel_list (list[int]): list of received channels to plot
            timestamps (list[array_like]): list of timestamp data for each channel
            num_samples (list[int]): number of samples per channel
        
        Returns:
            tvecs (list[array_like]): list of time vectors (units: seconds)
        """
    
        tvecs = []
        index_bits = int(np.ceil(np.log2(self._adc_buffer_data_depth)))
        index_mask = (1 << index_bits) - 1
        # first get minimum t0
        min_t0 = np.inf
        for channel in channel_list:
            if len(timestamps[channel]) > 0:
                min_t0 = min(min_t0, int(timestamps[channel][0]) >> index_bits)
        for channel in channel_list:
            if len(timestamps[channel]) > 0:
                tvec = np.empty(num_samples[channel])
                tstamp = int(timestamps[channel][0])
                overflow = 0
                for n in range(len(timestamps[channel])):
                    tstamp = int(timestamps[channel][n])
                    toffset = ((tstamp >> index_bits) - min_t0) * self._adc_parallel_samples
                    sample_index = (tstamp & index_mask) * self._adc_parallel_samples
                    sample_index += overflow * (1 << index_bits) * self._adc_parallel_samples
                    if n == len(timestamps[channel]) - 1:
                        sample_index_next = len(tvec)
                    else:
                        tstamp = int(timestamps[channel][n + 1])
                        sample_index_next = (tstamp & index_mask) * self._adc_parallel_samples
                        sample_index_next += overflow * (1 << index_bits) * self._adc_parallel_samples
                        if sample_index_next < sample_index:
                            overflow += 1
                            sample_index_next += (1 << index_bits) * self._adc_parallel_samples
                    n_samples = sample_index_next - sample_index
                    tvec[sample_index:sample_index_next] = (toffset + np.arange(n_samples))/self._adc_fsamp
            else:
                tvec = np.arange(num_samples[channel])/self._adc_fsamp
            tvecs.append(tvec)
        return tvecs
    
    def plot_channels(self,
                      channel_list: list[int],
                      timestamps: list[np.ndarray],
                      samples: list[np.ndarray]):
        """Plot received data for specified channels
        
        Arguments:
            channel_list (list[int]): list of received channels to plot
            timestamps (list[array_like]): list of timestamp data for each channel
            samples (list[array_like]): list of sample data for each channel
        """
        fig, axes = plt.subplots(len(channel_list), 1, sharex=True, figsize=(12,8+0.5*len(channel_list)), dpi=90)
        tvecs = self._get_tvecs_from_timestamps(channel_list, timestamps, [len(s) for s in samples])
        for n, axis in enumerate(axes):
            channel = channel_list[n]
            axis.plot(tvecs[n], np.int16(samples[channel])/2**15)
            
            
    def generate_pulse(self,
                       pulse_param_ns: list[float],
                       fsamp: float):
        """Generate a pulse based on supplied configuration in ns and sample rate
        
        Arguments:
            pulse_param_ns (list[float]): [rise, hold, fall, init delay, period] of waveform in ns
            fsamp (float): sample rate in Hz
        """
        rise_samples = ns_to_samp(pulse_param_ns[0], fsamp)
        width_samples = ns_to_samp(pulse_param_ns[1], fsamp)
        fall_samples = ns_to_samp(pulse_param_ns[2], fsamp)
        delay_samples = ns_to_samp(pulse_param_ns[3], fsamp)
        period_samples = ns_to_samp(pulse_param_ns[4], fsamp)
        data = np.zeros(period_samples)
        offset = delay_samples
        # rising edge
        data[offset:offset+rise_samples] = np.linspace(0, 2**15 - 1, rise_samples)
        offset += rise_samples
        # mesa
        data[offset:offset+width_samples] = 2**15 - 1
        offset += width_samples
        # falling edge
        data[offset:offset+fall_samples] = np.linspace(2**15 - 1, 0, fall_samples)
        return data