#!/usr/bin/env python3
"""
dereverb_wpe.py - Statistical dereverberation using Weighted Prediction Error (WPE).
Reduces late reverberation / acoustic reflections in reverberant spaces (e.g. hallways).
"""

import argparse
import sys
import os
import numpy as np
import soundfile as sf
from nara_wpe.wpe import wpe_v8
from nara_wpe.utils import stft, istft


def process_wpe(input_path: str, output_path: str, taps: int = 10, delay: int = 3, iterations: int = 3, stft_size: int = 512, stft_shift: int = 128):
    """
    Applies WPE dereverberation to single-channel audio.
    """
    if not os.path.exists(input_path):
        print(f"Error: Input file '{input_path}' not found.", file=sys.stderr)
        sys.exit(1)

    # 1. Load audio (soundfile loads float32 normalized [-1.0, 1.0])
    audio, sr = sf.read(input_path, dtype="float32")
    if audio.ndim == 1:
        # Convert mono (samples,) to (channels=1, samples)
        audio = audio[np.newaxis, :]
    else:
        # (samples, channels) -> (channels, samples)
        audio = audio.T

    # 2. STFT transformation: stft returns (frames, channels, bins)
    stft_data = stft(audio, size=stft_size, shift=stft_shift)

    # 3. Transpose to (bins, channels, frames) as required by wpe_v8
    Y = stft_data.transpose(2, 1, 0)
    dereverb_stft = wpe_v8(Y, taps=taps, delay=delay, iterations=iterations)

    # 4. Transpose back to (frames, channels, bins) for istft synthesis
    dereverb_audio = istft(dereverb_stft.transpose(2, 1, 0), size=stft_size, shift=stft_shift)

    # Ensure length matches original audio
    target_length = audio.shape[-1]
    if dereverb_audio.shape[-1] > target_length:
        dereverb_audio = dereverb_audio[:, :target_length]
    elif dereverb_audio.shape[-1] < target_length:
        pad_width = target_length - dereverb_audio.shape[-1]
        dereverb_audio = np.pad(dereverb_audio, ((0, 0), (0, pad_width)))

    # Peak normalization to avoid clipping
    peak = np.max(np.abs(dereverb_audio))
    if peak > 0.99:
        dereverb_audio = dereverb_audio / peak * 0.95

    # 5. Save output
    out_dir = os.path.dirname(os.path.abspath(output_path))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    # Mono output: (1, samples) -> (samples,)
    out_mono = dereverb_audio[0]
    sf.write(output_path, out_mono, sr, subtype="PCM_16" if output_path.lower().endswith(".wav") else None)
    print(f"Successfully dereverberated audio saved to: {output_path}")


def main():
    parser = argparse.ArgumentParser(description="WPE Dereverberation for Hallway / Echo Audio")
    parser.add_argument("--input", required=True, help="Path to input audio file")
    parser.add_argument("--output", required=True, help="Path to output dereverberated audio file")
    parser.add_argument("--taps", type=int, default=10, help="Filter taps (default: 10)")
    parser.add_argument("--delay", type=int, default=3, help="Prediction delay (default: 3)")
    parser.add_argument("--iterations", type=int, default=3, help="WPE iterations (default: 3)")
    parser.add_argument("--stft-size", type=int, default=512, help="STFT window size (default: 512)")
    parser.add_argument("--stft-shift", type=int, default=128, help="STFT shift size (default: 128)")

    args = parser.parse_args()
    process_wpe(
        input_path=args.input,
        output_path=args.output,
        taps=args.taps,
        delay=args.delay,
        iterations=args.iterations,
        stft_size=args.stft_size,
        stft_shift=args.stft_shift,
    )


if __name__ == "__main__":
    main()
