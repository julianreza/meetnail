# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["faster-whisper"]
# ///
"""Spike: transcribe an Indonesian audio file locally. First run downloads model weights."""

import argparse
import subprocess
import time
from pathlib import Path

import numpy as np
from faster_whisper import WhisperModel

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("audio", type=Path)
parser.add_argument("--model", choices=("base", "small"), default="small")
args = parser.parse_args()

pcm = subprocess.run(
    ["ffmpeg", "-nostdin", "-v", "error", "-i", str(args.audio.resolve()),
     "-ac", "1", "-ar", "16000", "-f", "s16le", "-"],
    check=True, stdout=subprocess.PIPE,
).stdout
if not pcm:
    parser.error("file has no decodable audio")

# ponytail: decode the whole file for this offline spike; use chunks for long meetings.
samples = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768
start = time.monotonic()
model = WhisperModel(args.model, device="cpu", compute_type="int8", cpu_threads=4)
ready = time.monotonic()
segments, _ = model.transcribe(samples, language="id", beam_size=3)
text = " ".join(segment.text.strip() for segment in segments)
print(f"Audio: {len(samples)/16000:.2f}s | Model load: {ready-start:.2f}s | Inference: {time.monotonic()-ready:.2f}s")
print(text)
