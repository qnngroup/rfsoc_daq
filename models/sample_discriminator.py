import numpy as np
import matplotlib.pyplot as plt

N = 1024
P_SAMP = 1

T = 64
W = 18

t_high = 1
t_low = 0.2

x_in = np.arange((N//P_SAMP)*P_SAMP) % T < W + np.random.randn((N//P_SAMP)*P_SAMP)
plt.plot(x_in)
plt.show()
any_high = np.zeros(N//P_SAMP)
all_low = np.zeros(N//P_SAMP)

for i in range(N//P_SAMP):
    any_high[i] = 0
    all_low[i] = 1
    for j in range(P_SAMP):
        if x_in[i*P_SAMP+j] > t_high:
            any_high[i] = 1
        elif x_in[i*P_SAMP+j] > t_low:
            all_low[i] = 0

