import numpy as np
import matplotlib.pyplot as plt
import scipy

colors = plt.rcParams['axes.prop_cycle'].by_key()['color']

adc_fsamp = 4.096e9
dac_fsamp = 6.144e9

awg_frame_depth = 2048

adc_buffer_data_depth = 2048
adc_buffer_tstamp_depth = 512 

parallel_samples = 16
sample_width = 16
num_channels = 8

def parse_adc_data(adc_buffer, num_active_channels):
    if num_active_channels not in [1,2,4,8]:
        raise ValueError(f'Incorrect number of active channels: {num_active_channels}, expected one of [1,2,4,8]')
    dma_word = 0
    dma_word_leftover_bits = 0
    dma_buffer_index = 0
    word_width = 64 # until we get the axis-register to work, don't use get_tstamp_width()
    word_mask = (1 << word_width) - 1
    parse_mode = "timestamp"
    need_channel_id = True
    need_word_count = True
    parsed_bank_count = 0
    done_parsing = False
    words_remaining = None
    timestamps = np.zeros((num_active_channels, (8//num_active_channels)*adc_buffer_tstamp_depth),dtype=np.uint64)
    samples = np.zeros((num_active_channels, (8//num_active_channels)*adc_buffer_data_depth*parallel_samples),dtype=np.int16)
    timestamp_index = [0 for i in range(num_active_channels)]
    sample_index = [0 for i in range(num_active_channels)]
    while not done_parsing:
        for _ in range(2 if parse_mode == "timestamp" else 4):
            dma_word = (int(adc_buffer[dma_buffer_index]) << dma_word_leftover_bits) | dma_word
            dma_word_leftover_bits += 64 # 64b numpy array
            dma_buffer_index += 1
        while dma_word_leftover_bits >= word_width:
            if need_channel_id:
                current_channel = dma_word & word_mask
                need_channel_id = False
                need_word_count = True
            else:
                if need_word_count:
                    words_remaining = dma_word & word_mask
                    need_word_count = False
                else:
                    if parse_mode == "timestamp":
                        timestamps[current_channel][timestamp_index[current_channel]] = dma_word & word_mask
                        timestamp_index[current_channel] += 1
                    elif parse_mode == "data":
                        for i in range(parallel_samples):
                            samples[current_channel][sample_index[current_channel]] = (dma_word >> (16*i)) & 0xffff
                            sample_index[current_channel] += 1
                    words_remaining -= 1
                if words_remaining == 0:
                    need_channel_id = True
                    parsed_bank_count += 1
            if parsed_bank_count == num_channels:
                if parse_mode == "timestamp":
                    word_width = parallel_samples*16
                    parse_mode = "data"
                else:
                    done_parsing = True
                dma_word = 0
                dma_word_leftover_bits = 0
                parsed_bank_count = 0
            else:
                dma_word >>= word_width
                dma_word_leftover_bits -= word_width
    return timestamps, samples, timestamp_index, sample_index

def plot_pulses(captured_channels, n_burst, t_min, t_max, filter_cfg, pulse_period_ns):
    plots = 3
    f, ax = plt.subplots(plots,1,sharex=True,figsize=(20,plots*2+1),dpi=100)
    tvec = np.linspace(0,(8//captured_channels)*adc_buffer_data_depth*parallel_samples/adc_fsamp,(8//captured_channels)*adc_buffer_data_depth*parallel_samples,endpoint=False)

    sos = scipy.signal.butter(2,filter_cfg[0],btype=filter_cfg[1],output='sos',fs=adc_fsamp)
    zi = scipy.signal.sosfilt_zi(sos)

    titles = []

    # plot AWG buffer
    current_plot = 0

    # plot raw ADC data + filtered ADC data
    x0 = np.mean(samples[0][0:int(50e-9*adc_fsamp)])
    filt, _ = scipy.signal.sosfilt(sos, samples[0]/2**sample_width, zi=zi*x0/2**sample_width)
    # find peaks
    peaks, _ = scipy.signal.find_peaks(filt, height=0.3*np.max(filt), prominence=0.7*np.max(filt), distance=0.5*pulse_period_ns*1e-9*adc_fsamp)
    #peaks, _ = scipy.signal.find_peaks(samples[0], height=0.3*np.max(samples[0]), prominence=0.7*np.max(samples[0]), distance=0.5*pulse_period_ns*1e-9*adc_fsamp)
    print(f'n_peaks = {len(peaks)}')

    ax[current_plot].plot(tvec*1e6, samples[0]/2**sample_width, '.', alpha=0.2)
    titles.append('adc_raw')
    current_plot += 1
    ax[current_plot].plot(tvec*1e6, filt, '.', alpha=0.2)
    ax[current_plot].plot(tvec[peaks]*1e6, filt[peaks], 'x')
    titles.append(f'adc_filt ({filter_cfg[0][0]/1e6}MHz, {filter_cfg[0][1]/1e6}MHz, {filter_cfg[1]})')
    current_plot += 1
    diff = np.diff(samples[0])
    x0 = np.mean(diff[0:int(50e-9*adc_fsamp)])
    diff_filt, _ = scipy.signal.sosfilt(sos, diff/2**sample_width, zi=zi*x0/2**sample_width)
    ax[current_plot].plot(tvec[1:]*1e6, diff_filt, '.', alpha=0.2)
    titles.append(f'diff(adc_filt)')
    ax[0].set_xlim(t_min, t_max)
    ax[-1].set_xlabel('t [us]')
    for i in range(plots):
        ax[i].set_title(titles[i], fontsize=12)
    f.tight_layout()
    #f.suptitle(f'V_gate = {gate_ampl_mV}mV ({round(gate_ampl_mV*dac_scale_per_mV[0],5)}fs)    I_chan = {chan_bias_uA}uA')
    plt.show()

def filt_data(data, filter_cfg, adc_fsamp):
    sos = scipy.signal.butter(4,filter_cfg[0],btype=filter_cfg[1],output='sos',fs=adc_fsamp)
    zi = scipy.signal.sosfilt_zi(sos)
    x0 = np.mean(data[0:int(50e-9*adc_fsamp)])
    filt, _ = scipy.signal.sosfilt(sos, data/2**sample_width, zi=zi*x0/2**sample_width)
    return filt

def get_peaks(data, filter_cfg, adc_fsamp, pulse_period_ns):
    filt = filt_data(data, filter_cfg, adc_fsamp)
    peaks, _ = scipy.signal.find_peaks(filt, height=0.3*np.max(filt), prominence=0.7*np.max(filt), distance=0.5*pulse_period_ns*1e-9*adc_fsamp)
    return peaks

def get_p_switch(data, filter_cfg, adc_fsamp, sent_pulses, pulse_period_ns):
    peaks = get_peaks(data, filter_cfg, adc_fsamp, pulse_period_ns)
    p_mean = len(peaks)/sent_pulses
    p_std = abs(p_mean*(1 - p_mean) * 2 / sent_pulses)**0.5
    return p_mean, p_std

def get_delays(data, filter_cfg, pulse_period_ns, dac_fsamp, adc_fsamp, pulses_per_burst, up=10):
    pulse_period = int(pulse_period_ns*1e-9*dac_fsamp)/dac_fsamp
    frame_period = awg_frame_depth*parallel_samples/dac_fsamp
    burst_times = np.linspace(0, pulses_per_burst*pulse_period, pulses_per_burst, endpoint=False)
    # delay to first pulse is 180ns
    init_delay = 181.2e-9
    expected_delays = init_delay + np.linspace(burst_times, frame_period*12 + burst_times, 12, endpoint=False).reshape(12 * pulses_per_burst, 1)

    burst_length_adc_samples = int(awg_frame_depth*parallel_samples/dac_fsamp*adc_fsamp)
    adc_tvec = np.linspace(0, len(data)/adc_fsamp, len(data), endpoint=False)
    adc_up_tvec = np.linspace(0, (len(data)*up-1)/(adc_fsamp*up), len(data)*up-1, endpoint=False)
    # get rough location of peaks
    peaks = get_peaks(data, filter_cfg, adc_fsamp, pulse_period_ns)
    # find rising edge location
    # up
    upsamp = scipy.signal.resample_poly(filt_data(data/2**sample_width, ([1e6, 500e6], 'bandpass'), adc_fsamp), up, 1)
    diff = np.diff(upsamp)
    rel_times = np.zeros(expected_delays.shape)
    delta_n = int(20e-9*adc_fsamp*up)
    for p, t_exp in enumerate(expected_delays):
        n = int(t_exp*adc_fsamp*up)
        t_rec = (np.argmax(diff[n-delta_n:n+delta_n])+n-delta_n)/(adc_fsamp*up)
        rel_times[p] = t_exp - t_rec
    return rel_times

if __name__ == '__main__':
    #data = np.load('data/20240423_153919_C4.npz')

    Ich_50uA = [
        '20240423_154253_C4.npz',
        '20240423_154744_C4.npz',
        '20240423_154328_C4.npz',
        '20240423_154727_C4.npz',
        '20240423_154622_C4.npz',
        '20240423_154711_C4.npz',
        '20240423_154644_C4.npz',
    ]
    Ich_55uA = [
        '20240423_155653_C4.npz',
        '20240423_155715_C4.npz',
        '20240423_155737_C4.npz',
        '20240423_155809_C4.npz',
        '20240423_155825_C4.npz',
        '20240423_160056_C4.npz',
        '20240423_160115_C4.npz',
        '20240423_160151_C4.npz',
        '20240423_160135_C4.npz',
        '20240423_160228_C4.npz',
        '20240423_160244_C4.npz',
        '20240423_160308_C4.npz',
    ]
    Ig_50uA = np.zeros(len(Ich_50uA))
    Psw_50uA = np.zeros(len(Ich_50uA))
    Psw_err_50uA = np.zeros(len(Ich_50uA))
    sw_times_50uA = []
    Ig_55uA = np.zeros(len(Ich_55uA))
    Psw_55uA = np.zeros(len(Ich_55uA))
    Psw_err_55uA = np.zeros(len(Ich_55uA))
    sw_times_55uA = []
    for n, f in enumerate(Ich_50uA):
        data = np.load(f'data/{f}')
        adc_buffer = data['dma_data']
        num_active_channels = data['num_active_channels']
        gate_ampl_mV = data['gate_ampl_mV']
        pulse_period_ns = data['pulse_period_ns']
        num_pulses = data['num_pulses']
        timestamps, samples, num_timestamps, num_samples = parse_adc_data(adc_buffer, num_active_channels)
        Psw_50uA[n], Psw_err_50uA[n] = get_p_switch(samples[0]/2**sample_width, ([1e6, 100e6], 'bandpass'), adc_fsamp, num_pulses * 12, pulse_period_ns)
        Ig_50uA[n] = gate_ampl_mV/1e3/10e3*1e6
        if Psw_50uA[n] > 0.3:
            sw_times_50uA.append(get_delays(samples[0], ([1e6, 500e6], 'bandpass'), pulse_period_ns, dac_fsamp, adc_fsamp, num_pulses, 20))
        else:
            sw_times_50uA.append(None)
    for n, f in enumerate(Ich_55uA):
        data = np.load(f'data/{f}')
        adc_buffer = data['dma_data']
        num_active_channels = data['num_active_channels']
        gate_ampl_mV = data['gate_ampl_mV']
        pulse_period_ns = data['pulse_period_ns']
        num_pulses = data['num_pulses']
        timestamps, samples, num_timestamps, num_samples = parse_adc_data(adc_buffer, num_active_channels)
        Psw_55uA[n], Psw_err_55uA[n] = get_p_switch(samples[0]/2**sample_width, ([1e6, 100e6], 'bandpass'), adc_fsamp, num_pulses * 12, pulse_period_ns)
        Ig_55uA[n] = gate_ampl_mV/1e3/10e3*1e6
        if Psw_55uA[n] > 0.3:
            sw_times_55uA.append(get_delays(samples[0], ([1e6, 500e6], 'bandpass'), pulse_period_ns, dac_fsamp, adc_fsamp, num_pulses, 20))
        else:
            sw_times_55uA.append(None)

    #f, ax = plt.subplots(1,2)
    #for i in range(2):
    #    ax[i].errorbar(Ig_50uA, Psw_50uA, xerr=0.5/1e3/10e3*1e6, yerr=Psw_err_50uA, label='Ich = 50uA')
    #    ax[i].errorbar(Ig_55uA, Psw_55uA, xerr=0.5/1e3/10e3*1e6, yerr=Psw_err_55uA, label='Ich = 55uA')
    #    ax[i].legend()
    #    ax[i].set_xlabel('Ig [uA]')
    #    ax[i].set_ylabel('P(switch)')
    #ax[0].set_yscale('log')
    #f.suptitle('C4')
    #plt.show()
    #print(f'num_pulses = {num_pulses}')
    # histograms
    f, ax = plt.subplots(1,2)
    c = 0
    for sw_time, Ig in zip(sw_times_50uA, Ig_50uA):
        if sw_time is not None:
            #sw_time -= np.mean(sw_time)
            q1 = np.quantile(sw_time, 0.25)
            q3 = np.quantile(sw_time, 0.75)
            iqr = q3 - q1
            std = np.std(sw_time[(sw_time > (q1 - 1.5*iqr)) & (sw_time < (q3 + 1.5*iqr))])
            ax[0].hist(sw_time*1e9, bins=50, label=f'Ig = {round(Ig,2)} $\mu$A ({round(std*1e12)}' + r'ps$_{\rm{rms}}$)', alpha=0.2, density=True, color=colors[c])
            c += 1
    c = 0
    for sw_time, Ig in zip(sw_times_55uA, Ig_55uA):
        if sw_time is not None:
            #sw_time -= np.mean(sw_time)
            q1 = np.quantile(sw_time, 0.25)
            q3 = np.quantile(sw_time, 0.75)
            iqr = q3 - q1
            std = np.std(sw_time[(sw_time > (q1 - 1.5*iqr)) & (sw_time < (q3 + 1.5*iqr))])
            ax[1].hist(sw_time*1e9, bins=50, label=f'Ig = {round(Ig,2)} $\mu$A ({round(std*1e12)}' + r'ps$_{\rm{rms}}$)', alpha=0.2, density=True, color=colors[c])
            c += 1
    ax[0].set_title('Ich = 50$\mu$A')
    ax[1].set_title('Ich = 55$\mu$A')
    for i in range(2):
        #ax[i].set_xlim([-5, 5])
        ax[i].legend()
        ax[i].set_xlabel('delay [ns]')
        ax[i].set_ylabel('count')
    f.suptitle('C4')
    plt.show()

    data = np.load('data/20240423_155653_C4.npz')
    adc_buffer = data['dma_data']
    num_active_channels = data['num_active_channels']
    gate_ampl_mV = data['gate_ampl_mV']
    pulse_period_ns = data['pulse_period_ns']
    num_pulses = data['num_pulses']
    timestamps, samples, num_timestamps, num_samples = parse_adc_data(adc_buffer, num_active_channels)
    #sw_times = get_delays(samples[0], ([1e6, 500e6], 'bandpass'), pulse_period_ns, dac_fsamp, adc_fsamp)
    sw_times = get_delays(samples[0], ([1e6, 500e6], 'bandpass'), pulse_period_ns, dac_fsamp, adc_fsamp, num_pulses, 20)
    plt.figure()
    plt.hist(sw_times*1e9, bins=100, alpha=0.2, density=True)
    plt.show()
    plot_pulses(1, 2, 0, 5.5, ([1e6, 500e6], 'bandpass'), pulse_period_ns)
    #plt.plot(samples)
    #plt.show()
