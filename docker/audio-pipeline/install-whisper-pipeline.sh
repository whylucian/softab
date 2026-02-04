#!/bin/bash
#
# Whisper Pipeline Installer (Self-contained)
# Builds the Docker image and creates a runner script
#
# Usage: ./install-whisper-pipeline.sh [INSTALL_DIR]
#        Default INSTALL_DIR: ~/whisper-pipeline
#

set -e

# Convert to absolute path
INSTALL_DIR="${1:-$HOME/whisper-pipeline}"
mkdir -p "$INSTALL_DIR"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"

echo "=== Whisper Pipeline Installer ==="
echo "Install directory: $INSTALL_DIR"
echo ""

# Create the Dockerfile
echo "=== Creating Dockerfile ==="
cat > "$INSTALL_DIR/Dockerfile" << 'DOCKERFILE_EOF'
# Optimized Audio Pipeline: VAD + Whisper + Pyannote
# Single container with ROCm 6.2 (pyannote) + Vulkan whisper.cpp
FROM localhost/softab:pyannote-rocm62-gfx1151

LABEL maintainer="softab"
LABEL description="Optimized audio pipeline: Silero VAD + Whisper.cpp Vulkan + Pyannote"

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV HSA_ENABLE_SDMA=0
ENV PYTORCH_HIP_ALLOC_CONF="backend:native,expandable_segments:True"
ENV AMD_VULKAN_ICD=RADV

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git wget curl \
    libvulkan-dev vulkan-tools mesa-vulkan-drivers \
    glslang-tools glslc \
    ffmpeg libsndfile1 \
    python3-pip python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip3 install --no-cache-dir --break-system-packages \
    silero-vad soundfile pandas

# Build whisper.cpp with Vulkan backend
WORKDIR /opt
RUN git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git && \
    cd whisper.cpp && \
    cmake -B build -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON && \
    cmake --build build -j$(nproc) && \
    cp build/bin/whisper-cli /usr/local/bin/ && \
    cp build/bin/whisper-bench /usr/local/bin/ && \
    find build -name "*.so*" -exec cp {} /usr/local/lib/ \; && \
    ldconfig && \
    rm -rf /opt/whisper.cpp

# Create pipeline script
COPY <<'PIPELINE_SCRIPT' /usr/local/bin/audio-pipeline
#!/usr/bin/env python3
"""Audio Pipeline: VAD + Whisper + Pyannote"""
import argparse, json, os, subprocess, sys, tempfile, time
from pathlib import Path
import torch
import soundfile as sf

def run_vad(audio_path, output_dir):
    print("=== Stage 1: Voice Activity Detection (Silero) ===")
    t0 = time.time()
    model, utils = torch.hub.load('snakers4/silero-vad', 'silero_vad', force_reload=False, trust_repo=True)
    get_speech_timestamps, _, read_audio, _, _ = utils
    wav = read_audio(audio_path, sampling_rate=16000)
    speech_timestamps = get_speech_timestamps(wav, model, sampling_rate=16000)
    elapsed = time.time() - t0
    total_speech = sum((ts['end'] - ts['start']) / 16000 for ts in speech_timestamps)
    print(f"  Time: {elapsed:.2f}s, Segments: {len(speech_timestamps)}, Speech: {total_speech:.1f}s")
    return speech_timestamps, elapsed

def run_whisper(audio_path, model_path, output_dir):
    print("\n=== Stage 2: Transcription (Whisper.cpp Vulkan) ===")
    t0 = time.time()
    output_base = Path(output_dir) / "whisper_output"
    output_json = output_base.with_suffix(".json")
    cmd = ["whisper-cli", "-m", model_path, "-f", audio_path, "-of", str(output_base),
           "-oj", "-l", "en", "--max-len", "1", "--print-progress", "false"]
    print(f"  Model: {model_path}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = time.time() - t0
    if result.returncode != 0:
        print(f"  Error: whisper-cli returned {result.returncode}")
        for line in result.stderr.split('\n')[:5]:
            if line.strip(): print(f"    {line.strip()}")
    for line in result.stderr.split('\n'):
        if 'total time' in line: print(f"  Whisper: {line.strip()}")
    whisper_segments, transcript = [], ""
    if output_json.exists():
        with open(output_json) as f:
            whisper_data = json.load(f)
        for item in whisper_data.get('transcription', []):
            ts = item.get('timestamps', {})
            text = item.get('text', '').strip()
            if text:
                def parse_ts(s):
                    p = s.replace(',', ':').split(':')
                    return int(p[0])*3600 + int(p[1])*60 + int(p[2]) + int(p[3])/1000
                whisper_segments.append({'start': parse_ts(ts.get('from', '00:00:00,000')),
                                         'end': parse_ts(ts.get('to', '00:00:00,000')), 'text': text})
        transcript = ' '.join(s['text'] for s in whisper_segments)
    print(f"  Time: {elapsed:.2f}s, Segments: {len(whisper_segments)}")
    print(f"  Transcript: {transcript[:100]}..." if len(transcript) > 100 else f"  Transcript: {transcript}")
    return whisper_segments, transcript, elapsed

def run_pyannote(audio_path, output_dir):
    print("\n=== Stage 3: Speaker Diarization (Pyannote) ===")
    t0 = time.time()
    import huggingface_hub
    _orig = huggingface_hub.hf_hub_download
    def _patched(*args, **kwargs):
        if 'use_auth_token' in kwargs: kwargs['token'] = kwargs.pop('use_auth_token')
        return _orig(*args, **kwargs)
    huggingface_hub.hf_hub_download = _patched
    _orig2 = huggingface_hub.snapshot_download
    def _patched2(*args, **kwargs):
        if 'use_auth_token' in kwargs: kwargs['token'] = kwargs.pop('use_auth_token')
        return _orig2(*args, **kwargs)
    huggingface_hub.snapshot_download = _patched2
    from pyannote.audio import Pipeline
    print("  Loading pipeline...")
    pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
    pipeline.to(torch.device("cuda"))
    print("  Running diarization...")
    diarization = pipeline(audio_path)
    elapsed = time.time() - t0
    segments = [{"start": t.start, "end": t.end, "speaker": s} for t, _, s in diarization.itertracks(yield_label=True)]
    print(f"  Time: {elapsed:.2f}s, Speakers: {len(set(s['speaker'] for s in segments))}, Segments: {len(segments)}")
    return segments, elapsed

def merge_results(whisper_segments, transcript, diarization_segments, audio_duration):
    def get_speaker(t):
        for seg in diarization_segments:
            if seg["start"] <= t <= seg["end"]: return seg["speaker"]
        min_dist, nearest = float('inf'), None
        for seg in diarization_segments:
            dist = min(abs(t - seg["start"]), abs(t - seg["end"]))
            if dist < min_dist and dist < 0.5: min_dist, nearest = dist, seg["speaker"]
        return nearest or (diarization_segments[0]["speaker"] if diarization_segments else "SPEAKER_00")
    merged = [{"start": round(s["start"], 3), "end": round(s["end"], 3), "text": s["text"],
               "speaker": get_speaker((s["start"] + s["end"]) / 2)} for s in whisper_segments]
    return {"transcript": transcript, "speakers": list(set(s["speaker"] for s in diarization_segments)) if diarization_segments else [],
            "segments": merged, "audio_duration": audio_duration}

def main():
    parser = argparse.ArgumentParser(description="Audio Pipeline: VAD + Whisper + Pyannote")
    parser.add_argument("audio", help="Path to audio file")
    parser.add_argument("-m", "--model", default="/models/ggml-large-v3.bin", help="Whisper model path")
    parser.add_argument("-o", "--output", help="Output JSON file")
    parser.add_argument("--skip-vad", action="store_true")
    parser.add_argument("--skip-whisper", action="store_true")
    parser.add_argument("--skip-pyannote", action="store_true")
    args = parser.parse_args()
    if not os.path.exists(args.audio): print(f"Error: {args.audio} not found"); sys.exit(1)
    if not args.skip_pyannote and not os.environ.get("HF_TOKEN"): print("Warning: HF_TOKEN not set")
    audio_info = sf.info(args.audio)
    audio_duration = audio_info.duration
    print(f"Audio: {args.audio}\nDuration: {audio_duration:.1f}s\nSample rate: {audio_info.samplerate}\n")
    with tempfile.TemporaryDirectory() as tmpdir:
        times = {}
        vad_segments, times['vad'] = run_vad(args.audio, tmpdir) if not args.skip_vad else (None, 0)
        if not args.skip_whisper:
            whisper_segments, transcript, times['whisper'] = run_whisper(args.audio, args.model, tmpdir)
        else: whisper_segments, transcript, times['whisper'] = [], "", 0
        diarization, times['pyannote'] = run_pyannote(args.audio, tmpdir) if not args.skip_pyannote else ([], 0)
        result = merge_results(whisper_segments, transcript, diarization, audio_duration)
        result['timings'] = times
        result['total_time'] = sum(times.values())
        result['realtime_factor'] = audio_duration / result['total_time'] if result['total_time'] > 0 else 0
        print(f"\n{'='*50}\nSUMMARY\n{'='*50}")
        print(f"Audio: {audio_duration:.1f}s | VAD: {times['vad']:.2f}s | Whisper: {times['whisper']:.2f}s | Pyannote: {times['pyannote']:.2f}s")
        print(f"Total: {result['total_time']:.2f}s | Realtime: {result['realtime_factor']:.1f}x")
        if args.output:
            with open(args.output, 'w') as f: json.dump(result, f, indent=2)
            print(f"\nResults saved to: {args.output}")
        else:
            print("\nSegments:")
            for seg in diarization[:5]: print(f"  [{seg['start']:.1f}s - {seg['end']:.1f}s] {seg['speaker']}")
            if len(diarization) > 5: print(f"  ... and {len(diarization) - 5} more")

if __name__ == "__main__": main()
PIPELINE_SCRIPT
RUN chmod +x /usr/local/bin/audio-pipeline

WORKDIR /workspace
ENTRYPOINT ["audio-pipeline"]
CMD ["--help"]
DOCKERFILE_EOF

# Build the Docker image
echo "=== Building Docker image ==="
cd "$INSTALL_DIR"

podman build \
    --security-opt seccomp=unconfined \
    --security-opt label=disable \
    -t whisper-pipeline:latest \
    -f Dockerfile .

echo ""
echo "=== Creating runner script ==="

# Create the runner script (whisperx-compatible interface)
cat > "$INSTALL_DIR/whisper-pipeline.sh" << 'RUNNER_SCRIPT'
#!/bin/bash
#
# Whisper Pipeline - Drop-in replacement for whisperx
# Supports same CLI arguments as whisperx for compatibility
#
# Usage: whisper-pipeline.sh <audio_file> [OPTIONS]
#

set -e

# Defaults
LANGUAGE="en"
MODEL="large-v3"
OUTPUT_DIR=""
DIARIZE=false
HF_TOKEN="${HF_TOKEN:-}"
IMAGE_NAME="${WHISPER_PIPELINE_IMAGE:-localhost/whisper-pipeline:latest}"
WHISPER_MODEL_PATH="${WHISPER_MODEL:-/models/whisper/ggml-large-v3.bin}"

# Parse whisperx-compatible arguments
AUDIO_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --language|-l) LANGUAGE="$2"; shift 2 ;;
        --model) MODEL="$2"; shift 2 ;;
        --output_dir) OUTPUT_DIR="$2"; shift 2 ;;
        --diarize) DIARIZE=true; shift ;;
        --hf_token) HF_TOKEN="$2"; shift 2 ;;
        --compute_type|--threads|--batch|--print_progress)
            shift 2 ;;  # Ignored for compatibility
        --help|-h)
            cat << EOF
Whisper Pipeline - GPU-accelerated transcription with speaker diarization
Drop-in replacement for whisperx

Usage: $(basename "$0") <audio_file> [OPTIONS]

Options:
  --language LANG      Language code (default: en)
  --model MODEL        Model name (default: large-v3)
  --output_dir DIR     Output directory (default: same as input)
  --diarize            Enable speaker diarization (always on)
  --hf_token TOKEN     HuggingFace token (or set HF_TOKEN env var)
  --help               Show this help

Ignored (for compatibility): --compute_type, --threads, --batch, --print_progress

Examples:
  whisper-pipeline.sh audio.wav --language en --model large-v3 --diarize
  whisper-pipeline.sh meeting.m4a --output_dir ./transcripts --hf_token \$HF_TOKEN
EOF
            exit 0 ;;
        -*) shift ;;  # Ignore unknown options for compatibility
        *)
            if [[ -z "$AUDIO_FILE" ]]; then
                AUDIO_FILE="$1"
            fi
            shift ;;
    esac
done

# Validate
[[ -z "$AUDIO_FILE" ]] && { echo "Error: No audio file specified"; exit 1; }
[[ ! -f "$AUDIO_FILE" ]] && { echo "Error: File not found: $AUDIO_FILE"; exit 1; }
[[ -z "$HF_TOKEN" ]] && { echo "Error: HF_TOKEN not set (use --hf_token or HF_TOKEN env var)"; exit 1; }

# Set output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR=$(dirname "$(realpath "$AUDIO_FILE")")
fi
mkdir -p "$OUTPUT_DIR"

# Map model name to path
case "$MODEL" in
    large-v3|large) WHISPER_MODEL_PATH="/models/whisper/ggml-large-v3.bin" ;;
    base|base.en) WHISPER_MODEL_PATH="/models/ggml-base.en.bin" ;;
    *) WHISPER_MODEL_PATH="/models/whisper/ggml-${MODEL}.bin" ;;
esac

# Get paths
AUDIO_FILE_ABS=$(realpath "$AUDIO_FILE")
AUDIO_DIR=$(dirname "$AUDIO_FILE_ABS")
AUDIO_NAME=$(basename "$AUDIO_FILE_ABS")
BASE_NAME="${AUDIO_NAME%.*}"
OUTPUT_DIR_ABS=$(realpath "$OUTPUT_DIR")

# Convert to WAV if needed
WAV_FILE="$AUDIO_FILE_ABS"
CLEANUP_WAV=false
if [[ ! "$AUDIO_FILE" =~ \.wav$ ]]; then
    echo "Converting to WAV..."
    WAV_FILE="$OUTPUT_DIR_ABS/${BASE_NAME}.wav"
    ffmpeg -i "$AUDIO_FILE_ABS" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE" -y 2>/dev/null
    AUDIO_DIR=$(dirname "$WAV_FILE")
    AUDIO_NAME=$(basename "$WAV_FILE")
    CLEANUP_WAV=true
fi

# Run the pipeline
echo "Transcribing: $AUDIO_FILE"
echo "Model: $WHISPER_MODEL_PATH"
echo "Output: $OUTPUT_DIR"

podman run --rm -t \
    --device=/dev/kfd --device=/dev/dri --ipc=host \
    --security-opt seccomp=unconfined --security-opt label=disable \
    -e HF_TOKEN="$HF_TOKEN" \
    -e PYTHONUNBUFFERED=1 \
    -v /data/models:/models:ro \
    -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
    -v "$AUDIO_DIR:/input:ro" \
    -v "$OUTPUT_DIR_ABS:/output" \
    "$IMAGE_NAME" \
    "/input/$AUDIO_NAME" -m "$WHISPER_MODEL_PATH" -o "/output/${BASE_NAME}.json"

# Generate TXT and SRT from JSON
JSON_FILE="$OUTPUT_DIR_ABS/${BASE_NAME}.json"
if [[ -f "$JSON_FILE" ]]; then
    echo "Generating output files..."
    python3 << PYEOF
import json
with open("$JSON_FILE") as f: data = json.load(f)
segments = data.get("segments", [])

# TXT with speaker labels (whisperx format)
with open("$OUTPUT_DIR_ABS/${BASE_NAME}.txt", "w") as f:
    for seg in segments:
        speaker = seg.get("speaker", "UNKNOWN")
        text = seg.get("text", "").strip()
        if text:
            f.write(f"[{speaker}]: {text}\n")

# SRT with timestamps
def fmt(s):
    h, m, sec = int(s//3600), int((s%3600)//60), int(s%60)
    return f"{h:02d}:{m:02d}:{sec:02d},{int((s-int(s))*1000):03d}"

with open("$OUTPUT_DIR_ABS/${BASE_NAME}.srt", "w") as f:
    for i, seg in enumerate(segments, 1):
        text = seg.get("text", "").strip()
        if not text: continue
        f.write(f"{i}\n{fmt(seg['start'])} --> {fmt(seg['end'])}\n[{seg.get('speaker','UNKNOWN')}] {text}\n\n")

print(f"Created: ${BASE_NAME}.json, ${BASE_NAME}.txt, ${BASE_NAME}.srt")
PYEOF
fi

# Cleanup temp wav
[[ "$CLEANUP_WAV" == "true" ]] && rm -f "$WAV_FILE"

echo "Done!"
RUNNER_SCRIPT

chmod +x "$INSTALL_DIR/whisper-pipeline.sh"

# Create rebuild script
cat > "$INSTALL_DIR/rebuild.sh" << 'REBUILD'
#!/bin/bash
cd "$(dirname "$0")"
podman build --security-opt seccomp=unconfined --security-opt label=disable -t whisper-pipeline:latest -f Dockerfile .
REBUILD
chmod +x "$INSTALL_DIR/rebuild.sh"

# Create config template
cat > "$INSTALL_DIR/config.env" << 'CONFIG'
# Whisper Pipeline Configuration
export WHISPER_PIPELINE_IMAGE="localhost/whisper-pipeline:latest"
export GDRIVE_FOLDER_IN="gd:/Modern Success/Weekly Coaching Calls/"
export GDRIVE_FOLDER_OUT="gd:/Modern Success/Audio"
export WHISPER_MODEL="/models/whisper/ggml-large-v3.bin"
export HF_TOKEN=""  # Required - get from https://huggingface.co/settings/tokens
CONFIG

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Files created in $INSTALL_DIR:"
echo "  whisper-pipeline.sh  - Main runner"
echo "  config.env           - Configuration"
echo "  Dockerfile           - For rebuilding"
echo "  rebuild.sh           - Rebuild script"
echo ""
echo "Usage:"
echo "  1. Edit config.env and set HF_TOKEN"
echo "  2. source $INSTALL_DIR/config.env"
echo "  3. $INSTALL_DIR/whisper-pipeline.sh /path/to/audio.wav"
echo ""
echo -e "\033[0;32mDone!\033[0m"
