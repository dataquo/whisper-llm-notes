import sys
import os
import pathlib

# Fix for loading Linux PosixPath in PyYAML / OmegaConf checkpoints on Windows
pathlib.PosixPath = pathlib.WindowsPath

import argparse
import torch
import soundfile as sf
from resemble_enhance.enhancer.inference import denoise, enhance

def main():
    parser = argparse.ArgumentParser(description="Resemble Enhance CLI for WHISPER Pipeline")
    parser.add_argument("--input", "-i", required=True, help="Input audio file path")
    parser.add_argument("--output", "-o", required=True, help="Output audio file path")
    parser.add_argument("--denoise_only", action="store_true", help="Run denoise only without bandwidth extension")
    parser.add_argument("--solver", default="midpoint", choices=["midpoint", "rk4", "euler"], help="ODE solver")
    parser.add_argument("--nfe", type=int, default=32, help="Number of function evaluations")
    parser.add_argument("--tau", type=float, default=0.5, help="Prior temperature tau (0.0 to 1.0)")
    parser.add_argument("--device", default=None, help="Device (cuda or cpu)")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input):
        print(f"Error: Input file '{args.input}' does not exist.")
        sys.exit(1)
        
    device = args.device or ("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[Resemble Enhance] Processing: {args.input}")
    print(f"[Resemble Enhance] Device: {device} | Denoise Only: {args.denoise_only} | NFE: {args.nfe} | Solver: {args.solver} | Tau: {args.tau}")
    
    data, sr = sf.read(args.input, dtype="float32")
    
    # Resemble Enhance expects 1D Tensor: [samples]
    if data.ndim == 1:
        dwav = torch.from_numpy(data)
    elif data.ndim == 2:
        # Downmix to mono 1D
        dwav = torch.from_numpy(data.mean(axis=1))
        
    dwav = dwav.to(device)
    
    with torch.no_grad():
        if args.denoise_only:
            enhanced_wav, new_sr = denoise(dwav, sr, device=device)
        else:
            enhanced_wav, new_sr = enhance(
                dwav,
                sr,
                device=device,
                nfe=args.nfe,
                solver=args.solver,
                lambd=0.9,
                tau=args.tau
            )
            
    enhanced_wav = enhanced_wav.cpu().numpy()
    
    out_dir = os.path.dirname(args.output)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)
        
    sf.write(args.output, enhanced_wav, new_sr)
    print(f"[Resemble Enhance] Enhanced audio successfully saved to: {args.output} (Sample Rate: {new_sr} Hz)")

if __name__ == "__main__":
    main()
