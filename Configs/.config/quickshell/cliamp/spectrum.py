#!/usr/bin/env python3
"""Per-player calibrated spectrum capture for the media popup."""
import json
import os
import re
import signal
import subprocess
import sys
import time

import numpy as np

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR")
RUN_DIR = os.path.join(RUNTIME_DIR, "cliamp") if RUNTIME_DIR and os.path.isdir(RUNTIME_DIR) else os.path.expanduser("~/.cache/cliamp/run")
OUT_FILE = os.path.join(RUN_DIR, "spectrum.json")
TARGET_FILE = os.path.join(RUN_DIR, "spectrum-target.json")
RATE, CHANNELS, FFT_SIZE, HIGH_FFT_SIZE, HOP = 48000, 2, 8192, 2048, 1024
NUM_BANDS, WAVE_SAMPLES, METER_SIZE, TRUE_PEAK_FACTOR = 24, 512, 2048, 4
TRIGGER_SEARCH, TRIGGER_TAPS = 2048, 96
DB_FLOOR, MIN_FREQ, MAX_FREQ, LOW_MAX_FREQ = -72.0, 20.0, 20000.0, 300.0
EDGES = np.geomspace(MIN_FREQ, MAX_FREQ, NUM_BANDS + 1)
os.makedirs(RUN_DIR, mode=0o700, exist_ok=True)

def fft_plan(size):
    window = np.hanning(size).astype(np.float32)
    gain = 2.0 / float(window.sum())
    enbw = size * float(np.sum(window * window)) / float(window.sum() ** 2)
    frequencies = np.fft.rfftfreq(size, 1.0 / RATE)
    bin_hz = RATE / size
    lower, upper = frequencies - bin_hz / 2, frequencies + bin_hz / 2
    weights = np.empty((NUM_BANDS, len(frequencies)), dtype=np.float32)
    for index in range(NUM_BANDS):
        low, high = EDGES[index], EDGES[index + 1]
        weights[index] = np.clip((np.minimum(upper, high) - np.maximum(lower, low)) / bin_hz, 0.0, 1.0)
    weights[:, 0] = 0
    return window, gain, enbw, weights

LOW_PLAN, HIGH_PLAN = fft_plan(FFT_SIZE), fft_plan(HIGH_FFT_SIZE)

def to_dbfs(values):
    return 20.0 * np.log10(np.maximum(values, 1e-10))

def normalize_db(db):
    return np.clip((db - DB_FLOOR) / -DB_FLOOR, 0.0, 1.0)

def band_rms(audio, size, plan):
    window, gain, enbw, weights = plan
    spectra = np.abs(np.fft.rfft(audio[-size:] * window[:, None], axis=0)) * gain
    return np.sqrt(np.maximum(weights @ (spectra * spectra), 0.0) / (2.0 * enbw))

def true_peak(audio):
    size, oversampled_size = len(audio), len(audio) * TRUE_PEAK_FACTOR
    source = np.fft.rfft(audio, axis=0)
    padded = np.zeros((oversampled_size // 2 + 1, CHANNELS), dtype=np.complex128)
    padded[:len(source)] = source
    if size % 2 == 0:
        padded[size // 2] *= 0.5
    oversampled = np.fft.irfft(padded, n=oversampled_size, axis=0) * TRUE_PEAK_FACTOR
    trim = 8 * TRUE_PEAK_FACTOR
    return np.max(np.abs(oversampled[trim:-trim]), axis=0)

def low_passed(values, taps):
    sums = np.concatenate((np.zeros(1), np.cumsum(values, dtype=np.float64)))
    return (sums[taps:] - sums[:-taps]) / taps

def waveform(audio):
    # Trigger on a low-passed copy: broadband zero crossings are dense and their
    # position carries no stable phase, so triggering on them scatters the trace
    # across the displayed window instead of locking it.
    mono = np.mean(audio, axis=1)
    maximum = len(audio) - WAVE_SAMPLES
    lag = (TRIGGER_TAPS - 1) // 2
    smoothed = low_passed(mono, TRIGGER_TAPS)
    low = max(0, maximum - TRIGGER_SEARCH - lag)
    high = min(len(smoothed) - 1, maximum - lag)
    search = smoothed[low:high + 1]
    crossings = np.flatnonzero((search[:-1] <= 0) & (search[1:] > 0)) + low + 1 + lag
    start = int(crossings[-1]) if len(crossings) else maximum
    segment = audio[start:start + WAVE_SAMPLES]
    return np.mean(segment, axis=1), segment[:, 0], segment[:, 1]

def rounded(values, digits):
    return np.round(np.asarray(values, dtype=np.float64), digits).tolist()

def analyze(audio):
    low = band_rms(audio, FFT_SIZE, LOW_PLAN)
    high = band_rms(audio, HIGH_FFT_SIZE, HIGH_PLAN)
    stereo_band_rms = np.where((EDGES[1:] <= LOW_MAX_FREQ)[:, None], low, high)
    stereo_band_db = to_dbfs(stereo_band_rms)
    band_db = to_dbfs(np.sqrt(np.mean(stereo_band_rms * stereo_band_rms, axis=1)))
    meter_audio = audio[-METER_SIZE:]
    rms = np.sqrt(np.mean(meter_audio * meter_audio, axis=0))
    sample_peaks = np.max(np.abs(meter_audio), axis=0)
    true_peaks = true_peak(meter_audio)
    rms_db, sample_peak_db, true_peak_db = map(to_dbfs, (rms, sample_peaks, true_peaks))
    mono_wave, left_wave, right_wave = waveform(audio)
    return {
        "bands": rounded(normalize_db(band_db), 3),
        "bands_dbfs": rounded(band_db, 2),
        "bands_stereo": {"left": rounded(normalize_db(stereo_band_db[:, 0]), 3),
                         "right": rounded(normalize_db(stereo_band_db[:, 1]), 3)},
        "band_edges_hz": rounded(EDGES, 1),
        "wave": rounded(mono_wave, 5),
        "wave_stereo": {"left": rounded(left_wave, 5), "right": rounded(right_wave, 5)},
        "stereo": {
            "levels": rounded(normalize_db(rms_db), 3),
            "peaks": rounded(normalize_db(true_peak_db), 3),
            "sample_peaks": rounded(normalize_db(sample_peak_db), 3),
            "rms_dbfs": rounded(rms_db, 2),
            "sample_peak_dbfs": rounded(sample_peak_db, 2),
            "true_peak_dbfs": rounded(true_peak_db, 2),
        },
        "analysis": {
            "captured_at_ms": round(time.time() * 1000),
            "hop_ms": round(HOP * 1000 / RATE, 2),
            "low_window_ms": round(FFT_SIZE * 1000 / RATE, 2),
            "high_window_ms": round(HIGH_FFT_SIZE * 1000 / RATE, 2),
            "db_floor": DB_FLOOR,
        },
    }

def normalize_text(value):
    return re.sub(r"[^a-z0-9]+", " ", str(value).lower()).strip()

def read_target():
    try:
        with open(TARGET_FILE, "r", encoding="utf-8") as target:
            raw = target.read()
        values = json.loads(raw).get("selectors", [])
    except (OSError, json.JSONDecodeError, AttributeError, TypeError):
        raw, values = "", ["cliamp", "mpv"]
    selectors = []
    for value in values:
        normalized = normalize_text(value)
        if normalized and normalized not in selectors:
            selectors.append(normalized)
        tail = normalize_text(str(value).split(".")[-1])
        if len(tail) >= 3 and tail not in selectors:
            selectors.append(tail)
    return raw, selectors or ["cliamp", "mpv"]

def select_sink_input(selectors):
    try:
        result = subprocess.run(["pactl", "--format=json", "list", "sink-inputs"], capture_output=True, text=True, timeout=1, check=True)
        inputs = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, KeyError, ValueError):
        return None, ""
    best = (0, None, "")
    keys = ("application.name", "application.process.binary", "application.icon_name", "node.name", "media.name", "media.title", "media.artist")
    for item in inputs:
        properties = item.get("properties", {})
        fields = [normalize_text(properties.get(key, "")) for key in keys]
        score = 0
        for selector in selectors:
            for field in fields:
                if not field:
                    continue
                if selector == field:
                    score += 100
                elif len(selector) >= 3 and (selector in field or field in selector):
                    score += 20
        if score > best[0]:
            label = properties.get("application.name") or properties.get("node.name") or ""
            best = score, int(item["index"]), str(label)
    return best[1], best[2]

def recorder(index):
    commands = [
        ["parec", "--raw", "--format=float32le", f"--rate={RATE}", f"--channels={CHANNELS}",
         "--latency-msec=20", "--client-name=CLIamp Spectrum", "--stream-name=Visualizer Analysis",
         "--property=quickshell.privacy.ignore=true", f"--monitor-stream={index}"],
        ["pw-record", "--raw", f"--channels={CHANNELS}", "--format=f32", f"--rate={RATE}",
         "--latency=20ms", "--properties",
         '{"application.name":"CLIamp Spectrum","media.name":"Visualizer Analysis","quickshell.privacy.ignore":"true"}',
         f"--target={index}", "-"],
    ]
    for command in commands:
        try:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            time.sleep(0.03)
            if process.poll() is None:
                return process
        except OSError:
            continue
    return None

def read_frames(process, frames):
    wanted, chunks = frames * CHANNELS * 4, []
    while wanted > 0:
        chunk = process.stdout.read(wanted)
        if not chunk:
            return None
        chunks.append(chunk)
        wanted -= len(chunk)
    return np.frombuffer(b"".join(chunks), dtype=np.float32).reshape(frames, CHANNELS)

def empty_frame(selectors):
    zeros = [0.0] * NUM_BANDS
    floor = [DB_FLOOR] * NUM_BANDS
    return {"bands": zeros, "bands_dbfs": floor, "band_edges_hz": rounded(EDGES, 1), "wave": [],
            "bands_stereo": {"left": zeros, "right": zeros},
            "wave_stereo": {"left": [], "right": []},
            "stereo": {"levels": [0, 0], "peaks": [0, 0], "sample_peaks": [0, 0],
                       "rms_dbfs": [DB_FLOOR, DB_FLOOR], "sample_peak_dbfs": [DB_FLOOR, DB_FLOOR],
                       "true_peak_dbfs": [DB_FLOOR, DB_FLOOR]},
            "source": {"found": False, "selectors": selectors}}

def write_frame(frame):
    temporary = OUT_FILE + ".tmp"
    with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as output:
        json.dump(frame, output, separators=(",", ":"))
    os.replace(temporary, OUT_FILE)

def stop_process(process):
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()

def run():
    process = history = None
    target_revision = None
    stream_index, stream_name, last_resolve = None, "", 0.0
    selectors = ["cliamp", "mpv"]
    def cleanup(_signal, _frame):
        stop_process(process)
        write_frame(empty_frame(selectors))
        sys.exit(0)
    signal.signal(signal.SIGINT, cleanup); signal.signal(signal.SIGTERM, cleanup)
    while True:
        try:
            revision, wanted = read_target()
            now = time.monotonic()
            if revision != target_revision or now - last_resolve >= 1.0:
                index, name = select_sink_input(wanted)
                last_resolve = now
                if revision != target_revision or index != stream_index:
                    stop_process(process)
                    process = history = None
                    stream_index, stream_name, selectors = index, name, wanted
                    target_revision = revision
                    if index is None:
                        write_frame(empty_frame(selectors))
            if stream_index is None:
                time.sleep(0.2)
                continue
            if process is None or process.poll() is not None:
                process, history = recorder(stream_index), None
                if process is None:
                    time.sleep(0.5)
                    continue
            frames = FFT_SIZE if history is None else HOP
            block = read_frames(process, frames)
            if block is None:
                stop_process(process)
                process = history = None
                continue
            if history is None:
                history = block.copy()
            else:
                history[:-HOP], history[-HOP:] = history[HOP:], block
            frame = analyze(history)
            frame["source"] = {"found": True, "index": stream_index, "name": stream_name, "selectors": selectors}
            write_frame(frame)
        except (OSError, ValueError, json.JSONDecodeError, subprocess.SubprocessError):
            time.sleep(0.05)

if __name__ == "__main__":
    run()
