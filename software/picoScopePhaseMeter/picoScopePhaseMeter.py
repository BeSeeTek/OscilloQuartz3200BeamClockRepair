import ctypes
import numpy as np
import threading
from datetime import datetime, timezone
import matplotlib.pyplot as plt
from picosdk.ps6000a import ps6000a as ps
from picosdk.PicoDeviceEnums import picoEnum as enums
from picosdk.functions import adc2mV, assert_pico_ok, mV2adc

# Helper to map channel number to letter A-H
_NUM_TO_LETTER = {str(i+1): letter for i, letter in enumerate('ABCDEFGH')}

class Phasemeter:
    def __init__(self, channels, trigger,
                 sample_rate=100e6, samples=8*1024*1024,
                 pretrigger=4096, on_block=None, waveform_width=8192):
        """
        channels: dict mapping 'CH1'..'CH8' to dicts with keys:
            'Signal', 'nom_freq', 'vertical', 'input'
        trigger: dict with keys 'source' ('CHx'), 'level' (V), 'direction' ('rising'/'falling'), 'mode'
        on_block: callback(results_dict) for streaming updates
        """
        self.channels = channels
        self.trigger = trigger
        self.sample_rate = sample_rate
        self.samples = samples
        self.pretrigger = pretrigger
        self.on_block = on_block
        self.waveform_width = waveform_width
        self.last_waveform = None
        self.running = False

        # PicoScope handle & status
        self.chandle = ctypes.c_int16()
        self.status = {}
        # Store both max and min buffers for each channel
        self.max_buffers = {}
        self.min_buffers = {}

    def setup_scope(self):
        # Open unit (8-bit resolution)
        resolution = enums.PICO_DEVICE_RESOLUTION['PICO_DR_8BIT']
        self.status['openunit'] = ps.ps6000aOpenUnit(ctypes.byref(self.chandle), None, resolution)
        assert_pico_ok(self.status['openunit'])

        # Channel setup: enable configured, disable others
        # Parse vertical ranges for each channel
        vranges = {}
        for name, cfg in self.channels.items():
            letter = _NUM_TO_LETTER[name[-1]]
            key = f'PICO_CHANNEL_{letter}'
            channel = enums.PICO_CHANNEL[key]
            # vertical range string like '+-5V' or '+-500mV'
            vr = cfg['vertical']
            vranges[name] = vr
            # coupling + bandwidth
            coupling = enums.PICO_COUPLING['PICO_DC_50OHM']
            bw = enums.PICO_BANDWIDTH_LIMITER['PICO_BW_FULL']
            self.status[f'setCh{name}'] = ps.ps6000aSetChannelOn(
                self.chandle, channel, coupling, vr, 0, bw)
            assert_pico_ok(self.status[f'setCh{name}'])

        # Disable all other channels
        for num, letter in _NUM_TO_LETTER.items():
            ch_name = f'CH{num}'
            if ch_name not in self.channels and int(num)<=3:
                key = f'PICO_CHANNEL_{letter}'
                channel = enums.PICO_CHANNEL[key]
                self.status[f'clrCh{num}'] = ps.ps6000aSetChannelOff(self.chandle, channel)
                assert_pico_ok(self.status[f'clrCh{num}'])

        # ADC limits for conversion
        self.minADC = ctypes.c_int16()
        self.maxADC = ctypes.c_int16()
        self.status['limits'] = ps.ps6000aGetAdcLimits(
            self.chandle, resolution,
            ctypes.byref(self.minADC), ctypes.byref(self.maxADC))
        assert_pico_ok(self.status['limits'])

        # Trigger setup
        src = self.trigger['source']
        letter = _NUM_TO_LETTER[src[-1]]
        key = f'PICO_CHANNEL_{letter}'
        src_ch = enums.PICO_CHANNEL[key]
        # threshold in ADC counts
        ch_vr = vranges[src]
        thr_mV = self.trigger['level'] * 1e3
        threshold = mV2adc(thr_mV, ch_vr, self.maxADC)
        direction = enums.PICO_THRESHOLD_DIRECTION[f'PICO_{self.trigger["direction"].upper()}']
        auto_us = 1_000_000  # 1 second
        self.status['trig'] = ps.ps6000aSetSimpleTrigger(
            self.chandle, 1, src_ch, threshold, direction, 0, auto_us)
        assert_pico_ok(self.status['trig'])

        # Timebase determination
        flags = 0
        for name in self.channels:
            letter = _NUM_TO_LETTER[name[-1]]
            flag_key = f'PICO_CHANNEL_{letter}_FLAGS'
            flags |= enums.PICO_CHANNEL_FLAGS[flag_key]
        tb = ctypes.c_uint32(0)
        interval = ctypes.c_double(0)
        self.status['tb'] = ps.ps6000aGetMinimumTimebaseStateless(
            self.chandle, flags, ctypes.byref(tb), ctypes.byref(interval), resolution)
        assert_pico_ok(self.status['tb'])
        self.timebase = tb.value
        self.sample_interval = interval.value

        # Allocate data buffers (max & min)
        for name in self.channels:
            max_buf = (ctypes.c_int16 * self.samples)()
            min_buf = (ctypes.c_int16 * self.samples)()
            self.max_buffers[name] = max_buf
            self.min_buffers[name] = min_buf
            channel = enums.PICO_CHANNEL[f'PICO_CHANNEL_{_NUM_TO_LETTER[name[-1]]}']
            # bufferLength as int, pointers via byref
            clear = enums.PICO_ACTION["PICO_CLEAR_ALL"]
            add = enums.PICO_ACTION["PICO_ADD"]
            action = clear | add  # PICO_ACTION["PICO_CLEAR_WAVEFORM_CLEAR_ALL"] | PICO_ACTION["PICO_ADD"]
            self.status[f'buf{name}'] = ps.ps6000aSetDataBuffers(
                self.chandle, channel,
                ctypes.byref(max_buf), ctypes.byref(min_buf),
                self.samples,
                enums.PICO_DATA_TYPE['PICO_INT16_T'],
                0,
                enums.PICO_RATIO_MODE['PICO_RATIO_MODE_RAW'],
                action)
            assert_pico_ok(self.status[f'buf{name}'])

    def acquire_block(self):
        # Start block capture with Python ints, not ctypes
        t_ind = ctypes.c_double(0)
        self.status['run'] = ps.ps6000aRunBlock(
            self.chandle,
            self.pretrigger,
            self.samples - self.pretrigger,
            self.timebase,
            ctypes.byref(t_ind),
            0, None, None)
        assert_pico_ok(self.status['run'])

        # Poll until ready
        rd = ctypes.c_int16(0)
        while not rd.value:
            self.status['rdy'] = ps.ps6000aIsReady(self.chandle, ctypes.byref(rd))

        # Fetch values
        cnt = ctypes.c_uint64(self.samples)
        ovf = ctypes.c_int16(0)
        self.status['get'] = ps.ps6000aGetValues(
            self.chandle,
            0,
            ctypes.byref(cnt),
            1,
            enums.PICO_RATIO_MODE['PICO_RATIO_MODE_RAW'],
            0,
            ctypes.byref(ovf))
        assert_pico_ok(self.status['get'])

        # Convert to numpy arrays
        return {name: np.array(self.max_buffers[name], dtype=np.float64)
                for name in self.channels}

    def process_block(self, data):
        # Timestamp to nearest second
        ts = datetime.now(timezone.utc).replace(microsecond=0)
        N = self.samples
        freqs = np.fft.rfftfreq(N, d=self.sample_interval)
        res = {'timestamp': ts}
        for name, cfg in self.channels.items():
            x = data[name] * np.hanning(N)
            F = np.fft.rfft(x)
            target = float(cfg['nom_freq'])
            idx = np.argmin(np.abs(freqs - target))
            amp = 2.0 * np.abs(F[idx]) / N
            ph = np.angle(F[idx])
            res[f'{name}_amp'] = amp
            res[f'{name}_phase'] = ph

        # last waveform around trigger
        c = self.pretrigger
        h = self.waveform_width // 2
        s = max(c - h, 0)
        e = s + self.waveform_width
        self.last_waveform = {n: data[n][s:e] for n in data}
        return res

    def _run(self):
        while self.running:
            block = self.acquire_block()
            out = self.process_block(block)
            print(f"Timestamp: {out['timestamp']}")
            for name in self.channels:
                print(f"{name} Amp={out[f'{name}_amp']:.3e}, Phase={out[f'{name}_phase']:.3f} rad")
            print('-'*40)
            if self.on_block:
                self.on_block(out)

    def start(self):
        self.setup_scope()
        self.running = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        if hasattr(self, 'thread'):
            self.thread.join()
        ps.ps6000aCloseUnit(self.chandle)

    def get_last_waveform(self):
        return self.last_waveform

# Usage example
if __name__ == '__main__':
    channels = {
        'CH1': {'Signal':'CS_Clock_5MHz','nom_freq':5e6,'vertical':8,'input':'DC50'},
        'CH2': {'Signal':'GPS_PPS','nom_freq':1.0,'vertical':8,'input':'DC50'},
        'CH4': {'Signal':'GPS_10MHz','nom_freq':1e7,'vertical':5,'input':'DC50'},
    }
    trigger = {'source':'CH2','level':1.0,'direction':'rising','mode':'normal'}
    pm = Phasemeter(channels, trigger, on_block=lambda r: None)
    pm.start()
    import time; time.sleep(5)
    pm.stop()
    pm.
    print('Done.')