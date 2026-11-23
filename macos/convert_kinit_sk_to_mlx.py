#!/usr/bin/env python3
"""
Converts the fine-tuned Slovak Whisper model (kinit/whisper-large-v3-sk) into Apple MLX FP16 format
for native M2 Max GPU inference.

Target output directory: ~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx
"""

import os
import sys
import argparse
from pathlib import Path

def convert_model(source_repo: str, output_dir: str, dtype: str = "float16"):
    dest = Path(os.path.expanduser(output_dir)).resolve()
    
    if dest.exists() and (dest / "weights.npz").exists():
        print(f"[OK] Converted MLX model already exists at: {dest}")
        return str(dest)
    
    dest.mkdir(parents=True, exist_ok=True)
    print(f"--- Converting '{source_repo}' to Apple MLX format ({dtype}) ---")
    print(f"Target location: {dest}")
    
    try:
        # Check if mlx_whisper.convert is available
        import subprocess
        cmd = [
            sys.executable,
            "-m",
            "mlx_whisper.convert",
            "--hf-repo",
            source_repo,
            "-o",
            str(dest),
            "--dtype",
            dtype,
        ]
        print(f"Executing: {' '.join(cmd)}")
        result = subprocess.run(cmd, check=True)
        if result.returncode == 0:
            print(f"[SUCCESS] Model converted successfully to: {dest}")
            return str(dest)
    except Exception as e:
        print(f"[ERROR] Failed to convert model via mlx_whisper.convert: {e}", file=sys.stderr)
        print("Falling back to Hugging Face Hub direct download for base MLX weights...", file=sys.stderr)
        return None

def main():
    parser = argparse.ArgumentParser(description="Convert Slovak Whisper model to Apple MLX format")
    parser.add_argument(
        "--source",
        default="kinit/whisper-large-v3-sk",
        help="Source Hugging Face repo (default: kinit/whisper-large-v3-sk)",
    )
    parser.add_argument(
        "--output",
        default="~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx",
        help="Output directory (default: ~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx)",
    )
    parser.add_argument(
        "--dtype",
        default="float16",
        choices=["float16", "float32", "bfloat16"],
        help="Target data type (default: float16)",
    )
    args = parser.parse_args()

    result = convert_model(source_repo=args.source, output_dir=args.output, dtype=args.dtype)
    if not result:
        sys.exit(1)

if __name__ == "__main__":
    main()
