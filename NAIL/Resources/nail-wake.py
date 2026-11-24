# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["numpy", "sherpa-onnx==2.0.2"]
# ///
"""Local keyword spotting for the Codex hands-free path."""
import json
import pathlib
import subprocess
import sys
import time

import numpy as np
import sherpa_onnx


def make_spotter(model_dir):
    model_dir = pathlib.Path(model_dir)
    suffix = "epoch-12-avg-2-chunk-16-left-64.int8.onnx"
    return sherpa_onnx.KeywordSpotter(
        tokens=str(model_dir / "tokens.txt"),
        encoder=str(model_dir / f"encoder-{suffix}"),
        decoder=str(model_dir / f"decoder-{suffix}"),
        joiner=str(model_dir / f"joiner-{suffix}"),
        keywords_file=str(model_dir / "keywords.txt"),
        keywords_score=1.0,
        keywords_threshold=0.1,
        num_threads=2,
    )


def detect(spotter, samples):
    stream = spotter.create_stream()
    # Provide brief leading silence so word-initial subword tokens match short calls.
    stream.accept_waveform(16000, np.zeros(3200, dtype=np.float32))
    stream.accept_waveform(16000, samples)
    stream.accept_waveform(16000, np.zeros(10640, dtype=np.float32))
    stream.input_finished()
    while spotter.is_ready(stream):
        spotter.decode_stream(stream)
        if spotter.get_result(stream):
            return True
    return False


def main():
    try:
        spotter = make_spotter(pathlib.Path(__file__).parent / 'wake-model')
    except Exception as exc:
        print(json.dumps({'ready': False, 'error': str(exc)}), flush=True)
        return 1
    print(json.dumps({'ready': True}), flush=True)
    for line in sys.stdin:
        req = None
        try:
            req = json.loads(line)
            started = time.monotonic()
            path = pathlib.Path(req['audio'])
            if not path.is_absolute():
                raise ValueError('audio path must be absolute')
            if req.get('format') == 'pcm16k':
                raw = path.read_bytes()
            else:
                raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 's16le', '-ac', '1', '-ar', '16000', 'pipe:1'], check=True, capture_output=True, timeout=15).stdout
            if len(raw) % 2:
                raise ValueError('invalid PCM data')
            samples = np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768.0
            result = {'id': req.get('id'), 'triggered': detect(spotter, samples), 'detectionMs': round((time.monotonic() - started) * 1000)}
        except Exception as exc:
            result = {'id': req.get('id') if isinstance(req, dict) else None, 'error': str(exc)}
        print(json.dumps(result), flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
