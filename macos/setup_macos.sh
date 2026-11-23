#!/usr/bin/env bash
# ==============================================================================
# setup_macos.sh - Automated Setup for WHISPER on macOS Apple Silicon (M2 Max)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== WHISPER v07.00: macOS Apple Silicon Setup (M2 Max) ==="

# 1. Check Homebrew prerequisites
echo "[1/6] Checking system tools (brew, ffmpeg, pwsh, python)..."
if ! command -v brew &>/dev/null; then
    echo "ERROR: Homebrew is required. Install from https://brew.sh" >&2
    exit 1
fi

for tool in ffmpeg pwsh python3; do
    if ! command -v "$tool" &>/dev/null; then
        echo "Installing missing dependency: $tool via Homebrew..."
        brew install "$tool"
    else
        echo "  [OK] $tool is installed."
    fi
done

# 2. Check or create .env with Hugging Face Token
echo "[2/6] Configuring Hugging Face token for PyAnnote 3.1..."
ENV_FILE="${SCRIPT_DIR}/.env"
ROOT_ENV_FILE="${REPO_ROOT}/.env"

# Auto-detect .env from root repository or macos directory
if [ -f "$ROOT_ENV_FILE" ] && [ ! -f "$ENV_FILE" ]; then
    echo "  [OK] Found existing .env in repository root. Copying to macos/.env..."
    cp "$ROOT_ENV_FILE" "$ENV_FILE"
fi

# If .env exists, load any exported variables
if [ -f "$ENV_FILE" ]; then
    set +u
    set -a
    source "$ENV_FILE" 2>/dev/null || true
    set +a
    set -u
fi

if [ ! -f "$ENV_FILE" ]; then
    if [ -n "${HF_TOKEN:-}" ]; then
        cat <<EOF > "$ENV_FILE"
# Hugging Face Token for gated pyannote/speaker-diarization-3.1 model
HF_TOKEN=${HF_TOKEN}
HOST=0.0.0.0
PORT=9000
WHISPER_KEEP_IN_MEMORY=false
MLX_MODEL_DEFAULT=mlx-community/whisper-large-v3-mlx
MLX_MODEL_SLOVAK=~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx
EOF
        echo "  [OK] Created macos/.env using active HF_TOKEN environment variable."
    else
        cat <<'EOF' > "$ENV_FILE"
# Hugging Face Token for gated pyannote/speaker-diarization-3.1 model
# Extract from your Windows Docker container or visit https://huggingface.co/settings/tokens
HF_TOKEN=hf_your_token_here

# Server host & port configuration
HOST=0.0.0.0
PORT=9000

# Unified Memory management
# Set to false (default) to unload models and flush Metal/MPS cache after each transcription (<0.1s)
WHISPER_KEEP_IN_MEMORY=false

# Default MLX Whisper model for English, Czech, and multilingual profiles
MLX_MODEL_DEFAULT=mlx-community/whisper-large-v3-mlx

# Local Slovak fine-tuned MLX model path (converted by convert_kinit_sk_to_mlx.py)
MLX_MODEL_SLOVAK=~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx
EOF
        echo "  [ACTION REQUIRED] Created macos/.env template."
        echo "  Please edit macos/.env and paste your HF_TOKEN (or extract from Windows Portainer)."
    fi
else
    echo "  [OK] macos/.env is present and configured."
fi

# 3. Create Python 3.11 virtual environment
VENV_DIR="${SCRIPT_DIR}/.venv"
echo "[3/6] Setting up Python virtual environment in ${VENV_DIR}..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

source "${VENV_DIR}/bin/activate"
pip install --upgrade pip setuptools wheel

# 4. Install MLX + PyTorch (MPS) + WhisperX dependencies
echo "[4/6] Installing dependencies (mlx-whisper, torch with MPS, whisperx, pyannote)..."
pip install -r "${SCRIPT_DIR}/requirements-macos.txt"

# 5. Convert Slovak model to Apple MLX format
echo "[5/6] Preparing Slovak model (kinit/whisper-large-v3-sk) for MLX Metal GPU..."
python3 "${SCRIPT_DIR}/convert_kinit_sk_to_mlx.py" || {
    echo "Notice: Slovak model conversion skipped or deferred. Baseline large-v3 will be used."
}

# 6. Configure config.local.json for macOS
echo "[6/6] Checking repository configuration..."
LOCAL_CONFIG="${REPO_ROOT}/config/config.local.json"
MAC_CONFIG_EXAMPLE="${REPO_ROOT}/config/config.local.macos.json.example"

if [ ! -f "$LOCAL_CONFIG" ] && [ -f "$MAC_CONFIG_EXAMPLE" ]; then
    cp "$MAC_CONFIG_EXAMPLE" "$LOCAL_CONFIG"
    echo "  [OK] Initialized config/config.local.json from macOS template."
else
    echo "  [OK] config/config.local.json is already present."
fi

echo ""
echo "=============================================================================="
echo " Setup Complete! To start the native M2 Max GPU Whisper service on port 9000:"
echo "=============================================================================="
echo "  source ${VENV_DIR}/bin/activate"
echo "  python ${SCRIPT_DIR}/whisperx_mlx_server.py"
echo ""
echo "Then in another terminal, run your normal batch transcription:"
echo "  pwsh -File ./src/_MASTER_WHISPER.ps1 -InputFolder ~/Recordings -SkipDJI"
echo "=============================================================================="
