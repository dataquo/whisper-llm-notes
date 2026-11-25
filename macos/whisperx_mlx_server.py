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
# which breaks Silero VAD and PyAnnote model unpickling (omegaconf.base.ContainerMetadata, ListConfig).
try:
    import torch
    if hasattr(torch, "load"):
        _orig_torch_load = torch.load
        def _safe_torch_load(*args, **kwargs):
            # Always force weights_only=False for trusted local checkpoints and models
            kwargs["weights_only"] = False
            return _orig_torch_load(*args, **kwargs)
        torch.load = _safe_torch_load
except Exception:
    pass

try:
    import torch.serialization
    import omegaconf
    if hasattr(torch.serialization, "add_safe_globals"):
        safe_classes = [
            omegaconf.listconfig.ListConfig,
            omegaconf.dictconfig.DictConfig
        ]
        for attr in ("ContainerMetadata", "Node", "Metadata"):
            if hasattr(omegaconf, "base") and hasattr(omegaconf.base, attr):
                safe_classes.append(getattr(omegaconf.base, attr))
        for attr in ("AnyNode", "StringNode", "IntegerNode", "BooleanNode", "FloatNode"):
            if hasattr(omegaconf, "nodes") and hasattr(omegaconf.nodes, attr):
                safe_classes.append(getattr(omegaconf.nodes, attr))
        torch.serialization.add_safe_globals(safe_classes)
except Exception:
    pass

# Load environment variables: inspect both repository root .env and macos/.env
env_source = None
try:
    from dotenv import dotenv_values, load_dotenv
    root_env = (Path(__file__).parent.parent / ".env").resolve()
    macos_env = (Path(__file__).parent / ".env").resolve()

    # Determine which file has the most valid non-placeholder HF_TOKEN
    chosen_file = None
    candidate_tokens = {}

    for cand in (macos_env, root_env):
        if cand.exists():
            vals = dotenv_values(cand)
            tok = (vals.get("HF_TOKEN") or "").strip().strip("'\"")
            if tok:
                candidate_tokens[cand] = tok

    # Pick candidate that is not placeholder 'hf_your_token_here'
    for cand, tok in candidate_tokens.items():
        if tok and not tok.startswith("hf_your_token") and len(tok) > 15:
            chosen_file = cand
            break

    if not chosen_file and candidate_tokens:
        chosen_file = list(candidate_tokens.keys())[0]

    if chosen_file:
        load_dotenv(dotenv_path=chosen_file, override=True)
        env_source = str(chosen_file)
    elif macos_env.exists():
        load_dotenv(dotenv_path=macos_env, override=True)
        env_source = str(macos_env)
    elif root_env.exists():
        load_dotenv(dotenv_path=root_env, override=True)
        env_source = str(root_env)
except ImportError:
    pass

HF_TOKEN = os.getenv("HF_TOKEN", None)
if HF_TOKEN:
    # Clean whitespace and accidental surrounding quotes
    HF_TOKEN = HF_TOKEN.strip().strip("'\"")
    # Ensure downstream huggingface_hub and pyannote sub-modules inherit the token
    os.environ["HF_TOKEN"] = HF_TOKEN
    os.environ["HUGGING_FACE_HUB_TOKEN"] = HF_TOKEN
    try:
        from huggingface_hub import login
        login(token=HF_TOKEN, add_to_git_credential=False)
    except Exception:
        pass
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
    masked_tok = f"{HF_TOKEN[:7]}...{HF_TOKEN[-4:]}" if (HF_TOKEN and len(HF_TOKEN) > 12) else ("None" if not HF_TOKEN else "Invalid")
    source_label = Path(env_source).name if env_source else "environment"
    print(f"============================================================")
    print(f" WhisperX MLX ASR Service Started (v07.02)")
    print(f" Hardware: Apple M2 Max Metal GPU (Unified Memory)")
    print(f" PyTorch Backend: {get_torch_device().upper()}")
    print(f" Default MLX Model: {MLX_MODEL_DEFAULT}")
    print(f" HF Token: {masked_tok} (from {source_label})")
    print(f" Auto Memory Flush: {not WHISPER_KEEP_IN_MEMORY}")
    if HF_TOKEN:
        try:
            from huggingface_hub import HfApi
            api = HfApi(token=HF_TOKEN)
            user_info = api.whoami()
            username = user_info.get("name") or user_info.get("fullname") or "authenticated"
            print(f" HF Account: @{username}")
            for repo in ["pyannote/speaker-diarization-3.1", "pyannote/segmentation-3.0"]:
                try:
                    api.model_info(repo)
                    print(f"   [Gated Model Access OK] {repo}")
                except Exception as m_err:
                    print(f"   [Gated Model Access DENIED] {repo} -> {m_err}")
        except Exception as hf_err:
            print(f" [HF Token Auth Failed] {hf_err}")
    print(f"============================================================")
    yield

app = FastAPI(
    title="WhisperX MLX ASR Service",
    description="Drop-in native Apple Silicon (M2 Max) Metal/MPS GPU transcription service for WHISPER pipeline",
    version="v07.02-mlx",
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
                # Pass temp_in_path or waveform tensor dict that pyannote expects (not bare numpy array)
                try:
                    vad_segments = vad_model(temp_in_path)
                except Exception:
                    vad_segments = vad_model({"waveform": torch.from_numpy(audio_data).unsqueeze(0), "sample_rate": 16000})

                def _get_seg_duration(s):
                    if isinstance(s, dict):
                        return float(s.get('end', 0) - s.get('start', 0))
                    elif isinstance(s, (tuple, list)):
                        if len(s) >= 2 and isinstance(s[0], (int, float)) and isinstance(s[1], (int, float)):
                            return float(s[1] - s[0])
                        elif len(s) >= 1 and hasattr(s[0], 'start') and hasattr(s[0], 'end'):
                            return float(s[0].end - s[0].start)
                    elif hasattr(s, 'start') and hasattr(s, 'end'):
                        return float(s.end - s.start)
                    elif hasattr(s, 'duration'):
                        return float(s.duration)
                    return 0.0

                total_speech = sum(_get_seg_duration(seg) for seg in vad_segments) if vad_segments else 0.0
                if not vad_segments or len(vad_segments) == 0 or total_speech < 0.5:
                    print(f"[VAD] No speech detected in audio (active speech: {total_speech:.2f}s). Returning zero segments.")
                    return {
                        "segments": [],
                        "word_segments": [],
                        "language": language or "en",
                        "duration": duration
                    }
            except Exception as vad_err:
                print(f"[VAD Warning] VAD pre-filter encountered non-fatal error: {vad_err}")

        # Stage 1: Transcription using mlx-whisper on M2 Max Metal GPU
        import inspect
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

        # Anti-hallucination guard:
        # Default condition_on_previous_text to False when not explicitly provided.
        # When True, any hallucination on silence/noise (e.g. "Thank you.") cascades into an unbreakable infinite loop.
        if condition_on_previous_text is not None:
            transcribe_kwargs["condition_on_previous_text"] = condition_on_previous_text
        else:
            transcribe_kwargs["condition_on_previous_text"] = False

        sig = inspect.signature(mlx_whisper.transcribe)
        if "hallucination_silence_threshold" in sig.parameters:
            transcribe_kwargs["hallucination_silence_threshold"] = 2.0
        if "no_speech_threshold" in sig.parameters:
            transcribe_kwargs["no_speech_threshold"] = 0.6

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

            # Prune silent hallucinated segments (e.g. "Thank you.", "Thanks for watching")
            # where forced alignment failed (backtrack failed / empty words) or no_speech_prob is high
            HALLUCINATION_PATTERNS = {
                "thank you", "thank you.", "thank you very much", "thanks for watching",
                "thanks for watching.", "thank you for watching", "thank you for watching.",
                "subtitles by the amara.org community", "bye", "bye."
            }
            cleaned_segments = []
            for seg in aligned_result.get("segments", []):
                t_clean = seg.get("text", "").strip().lower()
                if not t_clean:
                    continue
                is_known_hallucination = t_clean in HALLUCINATION_PATTERNS
                words_list = seg.get("words", [])
                has_aligned_words = bool(words_list and any("word" in w for w in words_list))
                no_speech = seg.get("no_speech_prob", 0.0) > 0.4
                if is_known_hallucination and (not has_aligned_words or no_speech):
                    print(f"[ASR Filter] Pruned silent hallucination segment: '{seg.get('text')}'")
                    continue
                cleaned_segments.append(seg)
            aligned_result["segments"] = cleaned_segments
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
                    dp_kwargs = {"device": device_pt}
                    dp_sig = inspect.signature(whisperx.DiarizationPipeline.__init__)
                    if "token" in dp_sig.parameters:
                        dp_kwargs["token"] = HF_TOKEN
                    elif "use_auth_token" in dp_sig.parameters:
                        dp_kwargs["use_auth_token"] = HF_TOKEN
                    else:
                        dp_kwargs["use_auth_token"] = HF_TOKEN

                    diarize_pipeline = whisperx.DiarizationPipeline(**dp_kwargs)
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
