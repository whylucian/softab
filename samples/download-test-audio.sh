#!/bin/bash
# Download or generate test audio samples for whisper benchmarks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="${SCRIPT_DIR}/test_audio.wav"

log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }
log_fail() { echo "[FAIL] $1"; }

# Option 1: Download a public domain audio sample
# LibriVox has public domain audiobooks
download_librivox() {
    log_info "Downloading LibriVox sample (~5 min of speech)..."

    # This is a chapter from a public domain audiobook
    # "The Art of War" read by a volunteer - clear English speech
    local url="https://ia800204.us.archive.org/18/items/art_of_war_librivox/art_of_war_01_sun_tzu_64kb.mp3"
    local mp3_file="${SCRIPT_DIR}/temp_audio.mp3"

    if command -v wget &> /dev/null; then
        wget -q "$url" -O "$mp3_file"
    elif command -v curl &> /dev/null; then
        curl -sL "$url" -o "$mp3_file"
    else
        log_fail "Neither wget nor curl available"
        return 1
    fi

    if [ ! -f "$mp3_file" ]; then
        log_fail "Download failed"
        return 1
    fi

    # Convert to WAV (16kHz mono, required by whisper)
    if command -v ffmpeg &> /dev/null; then
        log_info "Converting to WAV (16kHz mono)..."
        # Take first 5 minutes
        ffmpeg -y -i "$mp3_file" -ar 16000 -ac 1 -t 300 "$TARGET_FILE" 2>/dev/null
        rm -f "$mp3_file"
    else
        log_fail "ffmpeg not available for conversion"
        rm -f "$mp3_file"
        return 1
    fi

    if [ -f "$TARGET_FILE" ]; then
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TARGET_FILE" 2>/dev/null)
        log_success "Downloaded: $TARGET_FILE (${duration}s)"
        return 0
    fi

    return 1
}

# Option 2: Generate synthetic speech using espeak
generate_synthetic() {
    log_info "Generating synthetic speech with espeak..."

    if ! command -v espeak &> /dev/null && ! command -v espeak-ng &> /dev/null; then
        log_fail "espeak not available"
        return 1
    fi

    local espeak_cmd="espeak-ng"
    command -v espeak-ng &> /dev/null || espeak_cmd="espeak"

    # Generate 5 minutes of speech by repeating text
    local text_file="${SCRIPT_DIR}/temp_text.txt"

    # Create varied text for realistic transcription testing
    cat > "$text_file" << 'EOF'
The quick brown fox jumps over the lazy dog.
Pack my box with five dozen liquor jugs.
How vexingly quick daft zebras jump.
The five boxing wizards jump quickly.
Sphinx of black quartz, judge my vow.
Two driven jocks help fax my big quiz.
The jay, pig, fox, zebra and my wolves quack.
Blowzy red vixens fight for a quick jump.
EOF

    # Repeat the text file content multiple times
    local full_text=""
    for i in {1..50}; do
        full_text+=$(cat "$text_file")
        full_text+=$'\n'
    done

    echo "$full_text" | $espeak_cmd -v en-us -s 150 -w "${SCRIPT_DIR}/temp_speech.wav" --stdin 2>/dev/null

    if [ -f "${SCRIPT_DIR}/temp_speech.wav" ]; then
        # Convert to 16kHz mono, trim to 5 minutes
        if command -v ffmpeg &> /dev/null; then
            ffmpeg -y -i "${SCRIPT_DIR}/temp_speech.wav" -ar 16000 -ac 1 -t 300 "$TARGET_FILE" 2>/dev/null
            rm -f "${SCRIPT_DIR}/temp_speech.wav"
        else
            mv "${SCRIPT_DIR}/temp_speech.wav" "$TARGET_FILE"
        fi
    fi

    rm -f "$text_file"

    if [ -f "$TARGET_FILE" ]; then
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TARGET_FILE" 2>/dev/null || echo "unknown")
        log_success "Generated: $TARGET_FILE (${duration}s)"
        return 0
    fi

    return 1
}

# Option 3: Use existing file if provided
use_existing() {
    local source_file=$1

    if [ ! -f "$source_file" ]; then
        log_fail "File not found: $source_file"
        return 1
    fi

    log_info "Converting provided file to whisper format..."

    if command -v ffmpeg &> /dev/null; then
        # Convert to 16kHz mono WAV, take first 5 minutes
        ffmpeg -y -i "$source_file" -ar 16000 -ac 1 -t 300 "$TARGET_FILE" 2>/dev/null

        if [ -f "$TARGET_FILE" ]; then
            local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TARGET_FILE" 2>/dev/null)
            log_success "Converted: $TARGET_FILE (${duration}s)"
            return 0
        fi
    else
        log_fail "ffmpeg required for conversion"
        return 1
    fi

    return 1
}

# Main
main() {
    if [ -f "$TARGET_FILE" ]; then
        local duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$TARGET_FILE" 2>/dev/null)
        log_info "Test audio already exists: $TARGET_FILE (${duration}s)"
        read -p "Replace? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    # If a file is provided as argument, use it
    if [ -n "$1" ]; then
        use_existing "$1" && exit 0
    fi

    # Try download first, fall back to synthetic
    log_info "Attempting to download public domain audio sample..."
    if download_librivox; then
        exit 0
    fi

    log_warn "Download failed, trying synthetic generation..."
    if generate_synthetic; then
        exit 0
    fi

    log_fail "Could not create test audio. Options:"
    echo "  1. Install ffmpeg and retry"
    echo "  2. Install espeak-ng for synthetic speech"
    echo "  3. Provide your own audio: $0 /path/to/audio.mp3"
    exit 1
}

main "$@"
