#!/usr/bin/env bash
set -euo pipefail
umask 077

parent="$HOME/Library/Application Support/Nail"
out="$parent/Speaker Models v1"
if [ -s "$out/segmentation.onnx" ] && [ -s "$out/nemo_en_titanet_small.onnx" ] && [ -d "$out/python/sherpa_onnx" ]; then
    echo "Speaker models already installed: $out"
    exit 0
fi

mkdir -p "$parent"
stage=$(mktemp -d "$parent/.speaker-models.XXXXXX")
trap 'rm -rf "$stage"' EXIT
base=https://github.com/k2-fsa/sherpa-onnx/releases/download
curl -fsSL --retry 2 "$base/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2" -o "$stage/segmentation.tar.bz2"
curl -fsSL --retry 2 "$base/speaker-recongition-models/nemo_en_titanet_small.onnx" -o "$stage/nemo_en_titanet_small.onnx"
(
    cd "$stage"
    printf '%s\n' \
        '24615ee884c897d9d2ba09bb4d30da6bb1b15e685065962db5b02e76e4996488  segmentation.tar.bz2' \
        'ad4a1802485d8b34c722d2a9d04249662f2ece5d28a7a039063ca22f515a789e  nemo_en_titanet_small.onnx' | shasum -a 256 -c -
    tar -xOf segmentation.tar.bz2 sherpa-onnx-pyannote-segmentation-3-0/model.int8.onnx > segmentation.onnx
    rm segmentation.tar.bz2
)
/opt/homebrew/bin/uv pip install --python 3.12 --target "$stage/python" sherpa-onnx==2.0.2
if [ -e "$out" ]; then
    echo "Incomplete install exists at $out; move it aside and rerun." >&2
    exit 1
fi
mv "$stage" "$out"
echo "Installed local speaker models: $out"
