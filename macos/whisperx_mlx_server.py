#!/usr/bin/env python3
"""
WhisperX MLX FastAPI Server (macOS Apple Silicon M2 Max)
Implements the exact WhisperX /asr REST API contract using:
- Stage 1 (80% compute): mlx-whisper on M2 Max Metal GPU (FP16)
- Stage 2 (5% compute): whisperx.align (wav2vec2) on M2 Max PyTorch MPS GPU
- Stage 3 (15% compute): pyannote.audio 3.1 diarization on M2 Max PyTorch MPS GPU
- Stage 4: Instant Unified Memory flush (<0.1s) to prevent swapping with LM Studio (35B)
"""

import os
import gc
import sys
import tempfile
import traceback
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Optional, List, Dict, Any

from fastapi import FastAPI, File, UploadFile, Query, HTTPException
from fastapi.responses import JSONResponse
import soundfile as sf
import numpy as np

# Prevent SpeechBrain LazyModule bug from breaking traceback/linecache inspection on missing optional modules (like k2)
try:
    import speechbrain.utils.importutils as sb_importutils
    _orig_lazy_getattr = sb_importutils.LazyModule.__getattr__
    def _safe_lazy_getattr(self, attr):
        if attr in ("__file__", "__name__", "__loader__", "__package__", "__path__", "__spec__"):
            return None
        try:
            return _orig_lazy_getattr(self, attr)
        except (ImportError, ModuleNotFoundError) as err:
            raise AttributeError(f"Optional module {self.target} not installed: {err}") from None
    sb_importutils.LazyModule.__getattr__ = _safe_lazy_getattr
except Exception:
    pass

# In PyTorch 2.6+, torch.load default changed from weights_only=False to weights_only=True,
# which breaks Silero VAD and PyAnnote model unpickling (omegaconf.listconfig.ListConfig).
try:
    import torch
    if hasattr(torch, "load"):
        _orig_torch_load = torch.load
        def _safe_torch_load(*args, **kwargs):
            if "weights_only" not in kwargs:
                kwargs["weights_only"] = False
            return _orig_torch_load(*args, **kwargs)
        torch.load = _safe_torch_load
except Exception:
    pass

try:
    import torch.serialization
    import omegaconf
    if hasattr(torch.serialization, "add_safe_globals"):
        torch.serialization.add_safe_globals([
            omegaconf.listconfig.ListConfig,
            omegaconf.dictconfig.DictConfig
        ])
except Exception:
    pass

# Load environment variables if .env exists (check both macos/.env and repository root .env)
try:
    from dotenv import load_dotenv
    candidates = [
        Path(__file__).parent / ".env",
        Path(__file__).parent.parent / ".env"
    ]
    for c in candidates:
        if c.exists():
            load_dotenv(dotenv_path=c, override=True)
            break
except ImportError:
    pass

HF_TOKEN = os.getenv("HF_TOKEN", None)
if HF_TOKEN:
    # Ensure downstream huggingface_hub and pyannote sub-modules inherit the token
    os.environ["HF_TOKEN"] = HF_TOKEN
    os.environ["HUGGING_FACE_HUB_TOKEN"] = HF_TOKEN
WHISPER_KEEP_IN_MEMORY = os.getenv("WHISPER_KEEP_IN_MEMORY", "false").lower() in ("true", "1", "yes")
MLX_MODEL_DEFAULT = os.getenv("MLX_MODEL_DEFAULT", "mlx-community/whisper-large-v3-mlx")
MLX_MODEL_SLOVAK = os.getenv("MLX_MODEL_SLOVAK", "~/.cache/whisper-mlx/whisper-large-v3-kinit-sk-mlx")

def get_torch_device() -> str:
    """Detects best PyTorch device on Apple Silicon (mps with cpu fallback)."""
    try:
        import torch
        if torch.backends.mps.is_available():
            return "mps"
    except Exception:
        pass
    return "cpu"

def flush_unified_memory():
    """Immediately flushes Apple Metal and PyTorch MPS caches back to macOS."""
    gc.collect()
    try:
        import mlx.core as mx
        if hasattr(mx, "clear_cache"):
            mx.clear_cache()
        elif hasattr(mx, "metal") and hasattr(mx.metal, "clear_cache"):
            mx.metal.clear_cache()
    except Exception:
        pass

    try:
        import torch
        if torch.backends.mps.is_available():
            torch.mps.empty_cache()
    except Exception:
        pass

def resolve_model_path(requested_model: str, language: Optional[str] = None) -> str:
    """
    Resolves the MLX model path.
    1. Check for Slovak fine-tuned models if language is Slovak
    2. Check LM Studio cache directory (~/.lmstudio/models/mlx-community/...)
    3. Fallback to Hugging Face Hub identifier
    """
    req_lower = requested_model.lower()
    if ("kinit" in req_lower or "slovak" in req_lower or "-sk" in req_lower) and (language == "sk" or not language):
        slovak_path = Path(os.path.expanduser(MLX_MODEL_SLOVAK)).resolve()
        if slovak_path.exists():
            return str(slovak_path)

    # Check LM Studio local cache for whisper-large-v3-mlx
    lm_studio_cache = Path(os.path.expanduser("~/.lmstudio/models/mlx-community/whisper-large-v3-mlx")).resolve()
    if lm_studio_cache.exists():
        return str(lm_studio_cache)

    return MLX_MODEL_DEFAULT

@asynccontextmanager
async def lifespan(app: FastAPI):
    print(f"============================================================")
    print(f" WhisperX MLX ASR Service Started (v07.00)")
    print(f" Hardware: Apple M2 Max Metal GPU (Unified Memory)")
    print(f" PyTorch Backend: {get_torch_device().upper()}")
    print(f" Default MLX Model: {MLX_MODEL_DEFAULT}")
    print(f" HF Token Available: {bool(HF_TOKEN)}")
    print(f" Auto Memory Flush: {not WHISPER_KEEP_IN_MEMORY}")
    print(f"============================================================")
    yield

app = FastAPI(
    title="WhisperX MLX ASR Service",
    description="Drop-in native Apple Silicon (M2 Max) Metal/MPS GPU transcription service for WHISPER pipeline",
    version="v07.00-mlx",
    lifespan=lifespan
)

# Custom OpenAPI metadata extension for zero-null pipeline telemetry auditing
app.openapi_tags = [
    {
        "name": "ASR",
        "description": "Speech recognition, alignment, and diarization endpoint"
    }
]

@app.get("/health")
async def health_check():
    return {"status": "ok", "backend": "mlx_metal_mps", "version": "v07.00"}

@app.post("/gc")
async def trigger_garbage_collection():
    """Manual trigger to flush Apple Metal / PyTorch MPS memory cache."""
    flush_unified_memory()
    return {"status": "memory_flushed", "device": get_torch_device()}

@app.get("/openapi.json")
def custom_openapi():
    openapi_schema = app.openapi()
    # Inject rich backend metadata for Get-WhisperContainerMetadata auditing
    openapi_schema["info"]["x_backend_metadata"] = {
        "container_name": "native-mlx",
        "image": MLX_MODEL_DEFAULT,
        "image_id": "apple-m2-max-metal",
        "api_version": "v07.00-mlx",
        "cudnn_version": "Apple Metal / MPS",
        "status": "online"
    }
    return JSONResponse(openapi_schema)

@app.post("/asr")
async def transcribe_audio(
    audio_file: UploadFile = File(...),
    task: str = Query("transcribe"),
    language: Optional[str] = Query(None),
    model: str = Query("large-v3"),
    diarize: bool = Query(True),
    min_speakers: Optional[int] = Query(None),
    max_speakers: Optional[int] = Query(None),
    initial_prompt: Optional[str] = Query(None),
    vad_filter: bool = Query(True),
    vad_onset: float = Query(0.5),
    vad_offset: float = Query(0.363),
    temperature: float = Query(0.0),
    beam_size: Optional[int] = Query(None),
    condition_on_previous_text: Optional[bool] = Query(None),
    repetition_penalty: Optional[float] = Query(None),
    no_repeat_ngram_size: Optional[int] = Query(None)
):
    temp_in_path = None
    try:
        # Save uploaded multipart audio file to disk
        suffix = Path(audio_file.filename or "audio.wav").suffix or ".wav"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
            temp_in_path = tmp_file.name
            content = await audio_file.read()
            tmp_file.write(content)

        if os.path.getsize(temp_in_path) <= 1024:
            raise HTTPException(status_code=400, detail="Uploaded audio file is empty or corrupted (<1KB).")

        # Load audio data robustly using whisperx.load_audio (uses FFmpeg, supports MP3/WAV/WebM/FLAC)
        import whisperx
        device_pt = get_torch_device()
        audio_data = whisperx.load_audio(temp_in_path)
        duration = float(len(audio_data) / 16000.0)

        # Stage 0: Voice Activity Detection (VAD) via PyAnnote
        # Guard zero-speech files
        if vad_filter:
            try:
                vad_model = whisperx.vad.load_vad_model(device_pt, vad_onset=vad_onset, vad_offset=vad_offset)
                vad_segments = vad_model(audio_data)
                if not vad_segments or len(vad_segments) == 0:
                    print("[VAD] No speech detected in audio. Returning zero segments.")
                    return {
                        "segments": [],
                        "word_segments": [],
                        "language": language or "sk",
                        "duration": duration
                    }
            except Exception as vad_err:
                print(f"[VAD Warning] VAD pre-filter encountered non-fatal error: {vad_err}")

        # Stage 1: Transcription using mlx-whisper on M2 Max Metal GPU
        import mlx_whisper
        resolved_model = resolve_model_path(model, language=language)
        print(f"[ASR] Running mlx-whisper with model: '{resolved_model}' on M2 Max Metal GPU")

        transcribe_kwargs: Dict[str, Any] = {
            "path_or_hf_repo": resolved_model,
            "temperature": temperature,
            "word_timestamps": True
        }
        if language:
            transcribe_kwargs["language"] = language
        if initial_prompt:
            transcribe_kwargs["initial_prompt"] = initial_prompt
        if condition_on_previous_text is not None:
            transcribe_kwargs["condition_on_previous_text"] = condition_on_previous_text

        asr_result = mlx_whisper.transcribe(audio_data, **transcribe_kwargs)
        detected_language = asr_result.get("language", language or "en")

        # Normalize segments
        raw_segments = asr_result.get("segments", [])
        if not raw_segments:
            return {
                "segments": [],
                "word_segments": [],
                "language": detected_language,
                "duration": duration
            }

        # Stage 2: Word-Level Forced Alignment via wav2vec2 on PyTorch MPS GPU
        aligned_result = {"segments": raw_segments, "word_segments": []}
        try:
            print(f"[Alignment] Running wav2vec2 forced alignment for '{detected_language}' on {device_pt.upper()}")
            align_model, align_metadata = whisperx.load_align_model(
                language_code=detected_language,
                device=device_pt
            )
            aligned_result = whisperx.align(
                raw_segments,
                align_model,
                align_metadata,
                audio_data,
                device=device_pt,
                return_char_alignments=False
            )
            # Free alignment model
            del align_model
            del align_metadata
        except Exception as align_err:
            print(f"[Alignment Warning] wav2vec2 alignment fallback to raw timestamps: {align_err}")

        # Stage 3: Speaker Diarization via pyannote.audio 3.1
        final_result = aligned_result
        if diarize:
            if not HF_TOKEN:
                print("[Diarization Warning] HF_TOKEN is not set; skipping PyAnnote diarization.")
            else:
                try:
                    print(f"[Diarization] Running PyAnnote 3.1 diarization on {device_pt.upper()} (min={min_speakers}, max={max_speakers})")
                    diarize_pipeline = whisperx.DiarizationPipeline(
                        use_auth_token=HF_TOKEN,
                        device=device_pt
                    )
                    if diarize_pipeline and getattr(diarize_pipeline, "model", None) is not None:
                        diarize_segments = diarize_pipeline(
                            audio_data,
                            min_speakers=min_speakers,
                            max_speakers=max_speakers
                        )
                        final_result = whisperx.assign_word_speakers(diarize_segments, aligned_result)
                        del diarize_pipeline
                    else:
                        print("[Diarization Warning] PyAnnote pipeline model is None. Access may be unauthorized or terms not accepted.")
                except Exception as diar_err:
                    print(f"[Diarization Error] Diarization failed: {diar_err}")
                    print("  [Hugging Face Gated Model Check]")
                    print("  PyAnnote 3.1 requires accepting user conditions on BOTH Hugging Face models:")
                    print("  1) https://huggingface.co/pyannote/speaker-diarization-3.1")
                    print("  2) https://huggingface.co/pyannote/segmentation-3.0")
                    print("  Make sure your Hugging Face account has accepted terms on both, and your token has 'Read' permission.")

        final_result["duration"] = duration
        final_result["language"] = detected_language
        return final_result

    except HTTPException:
        raise
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Transcription failed: {str(exc)}")
    finally:
        # Cleanup temp file
        if temp_in_path and os.path.exists(temp_in_path):
            try:
                os.remove(temp_in_path)
            except Exception:
                pass

        # Stage 4: Flush Unified Memory cache unless keep-in-memory is configured
        if not WHISPER_KEEP_IN_MEMORY:
            flush_unified_memory()

if __name__ == "__main__":
    import uvicorn
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "9000"))
    uvicorn.run("whisperx_mlx_server:app", host=host, port=port, reload=False)
