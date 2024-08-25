import numpy as np
import matplotlib.pyplot as plt

N = 1024
P_SAMP = 8

T = 209
W = 18

t_high = 1
t_low = 0.4

D_pre = 5
D_post = 1

x_in = (np.arange((N//P_SAMP)*P_SAMP) % T < W) + np.random.randn((N//P_SAMP)*P_SAMP)/5
any_high = np.zeros(N//P_SAMP)
any_high_delay = np.zeros(N//P_SAMP)
all_low = np.zeros(N//P_SAMP)
all_low_delay = np.zeros(N//P_SAMP)
x_in_delay = np.zeros((N//P_SAMP)*P_SAMP)
x_in_delay[D_pre*P_SAMP:] = x_in[:N-D_pre*P_SAMP]


for i in range(N//P_SAMP):
    any_high[i] = 0
    all_low[i] = 1
    for j in range(P_SAMP):
        if x_in[i*P_SAMP+j] > t_high:
            any_high[i] = 1
        if x_in[i*P_SAMP+j] > t_low:
            all_low[i] = 0

any_high_delay[D_post+D_pre:] = any_high[:N//P_SAMP-D_post-D_pre]
all_low_delay[D_post+D_pre:] = all_low[:N//P_SAMP-D_post-D_pre]
enabled = np.zeros(N//P_SAMP)
hold = 0
en = 0
for i in range(N//P_SAMP):
    if any_high[i] and not(hold):
        hold = 1
        en = 1
    if any_high_delay[i] and hold:
        hold = 0
    if all_low_delay[i] and not(hold):
        en = 0
    enabled[i] = en


plt.plot(x_in, '.', label='x_in')
plt.plot(x_in_delay, '.', label='x_in_d')
plt.plot(np.arange(0,N,P_SAMP), any_high, '-o', label='any_high')
plt.plot(np.arange(0,N,P_SAMP), all_low, '-o', label='all_low')
plt.plot(np.arange(0,N,P_SAMP), any_high_delay, '-o', label='any_high_delay')
plt.legend()
for i in range(N//P_SAMP):
    if (enabled[i]):
        plt.axvspan(i*P_SAMP,(i+1)*P_SAMP, facecolor='g', alpha=0.2)


plt.show()
