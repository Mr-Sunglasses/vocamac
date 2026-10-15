# Speech models

VocaMac runs four on-device speech engines plus an optional Custom Endpoint, and picks among them in **Settings → Speech Model**, where models are grouped by engine. Local engines run on this Mac. Custom Endpoint uploads each recording to the server you configure.

Models download once when you choose them and are cached locally: Whisper and Parakeet from Hugging Face, the specialized models from sherpa-onnx's model releases. Tiny Whisper ships with the app.

## Parakeet — fastest, recommended for dictation

NVIDIA Parakeet TDT models running as CoreML on the Apple Neural Engine (via [FluidAudio](https://github.com/FluidInference/FluidAudio)).

| Model | Size | Speed | Languages |
|-------|------|-------|-----------|
| **Parakeet Ultra** | ~632 MB | ⚡⚡⚡⚡⚡ | Parakeet v3 post-trained by moondream: more accurate at the same speed, same 25 European languages |
| **Parakeet v3** | ~483 MB | ⚡⚡⚡⚡⚡ | 25 European languages + Japanese, auto-detected |
| **Parakeet Unified** | ~614 MB | ⚡⚡⚡⚡⚡ | English only, NVIDIA's newest Parakeet: punctuation, capitals, and numbers written as digits |
| **Parakeet v2** | ~464 MB | ⚡⚡⚡⚡⚡ | English only, highest recall |
| **Parakeet 110M** | ~227 MB | ⚡⚡⚡⚡⚡ | English only, smaller download and faster first load |

## Whisper — widest language coverage

OpenAI Whisper models via WhisperKit's CoreML format. The only engine that supports **translation to English**. Dictionary vocabulary is a recognition hint for Whisper, Apple Speech, and (with the optional vocabulary boost download) Parakeet; every engine gets the spelling fixes after transcription. The app auto-detects your hardware and recommends a variant.

| Model | Parameters | Size | Speed | Quality | Best For |
|-------|-----------|------|-------|---------|----------|
| **Tiny** | 39M | ~0.4 GB | ⚡⚡⚡⚡⚡ | Good | Quick notes, older Macs |
| **Base** | 74M | ~0.8 GB | ⚡⚡⚡⚡ | Better | Daily use on 8GB Macs |
| **Small** | 244M | ~1.5 GB | ⚡⚡⚡ | Great | 16GB+ Apple Silicon |
| **Medium** | 769M | ~2.5 GB | ⚡⚡ | Excellent | 24GB+ for high accuracy |
| **Large v3** | 1550M | ~4.8 GB | ⚡ | Best | Maximum accuracy |
| **Voca Hinglish** | 809M | ~0.8 GB | ⚡⚡⚡ | Best for Hindi | Hindi speech written in Roman script ([Oriserve's Hindi2Hinglish Apex](https://huggingface.co/Oriserve/Whisper-Hindi2Hinglish-Apex) fine-tune of Large v3 Turbo, 8-bit compressed and [hosted by VocaHQ](https://huggingface.co/VocaHQ/whisperkit-coreml)) |

Voca Hinglish always decodes as English, which is how it was trained to write romanized Hindi, so it ignores the language setting.

## Apple Speech — managed by macOS (macOS 26+)

Apple's on-device SpeechAnalyzer engine. Assets are managed by macOS (language packs may download on first use) and are not stored in VocaMac's model folder. Covers roughly 30 locales.

## Specialized (ONNX) — niche needs

Community models via [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx). These run on the **CPU**, so on Apple Silicon prefer Parakeet unless you need one of these specifically.

| Model | Size | Best For |
|-------|------|----------|
| **Moonshine v2 Tiny** | ~60 MB | Very low-RAM Macs, English |
| **Moonshine v2 Base** | ~190 MB | Low-RAM Macs, English |
| **SenseVoice** | ~240 MB | Chinese, Japanese, Korean, Cantonese, English |
| **GigaAM v3** | ~270 MB | Russian, with punctuation |
| **Canary 180M Flash** | ~320 MB | English, Spanish, German, French |
| **Qwen3 ASR 0.6B** | ~973 MB | Accurate transcription across 30 languages and Chinese dialects |

Recordings longer than a model's single-pass limit are split at natural pauses and decoded segment by segment, since these models — unlike Whisper and Parakeet — do not chunk internally.

> **Note:** SenseVoice and Canary fix their language when the model loads, so changing the transcription language reloads the active model. Whisper and Parakeet take the language per transcription.

## Custom Endpoint (optional, remote)

Select Custom Endpoint to upload each recording as a WAV file to a Whisper-compatible server you host (OpenAI audio API or whisper.cpp). This is opt-in and off by default. It is distinct from VocaGateway.

## Why the Whisper engine uses WhisperKit

The Whisper path uses [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) instead of raw whisper.cpp because:

| | WhisperKit | whisper.cpp |
|---|-----------|-------------|
| **Language** | Pure Swift (native) | C++ (requires bridging) |
| **Apple Silicon** | CoreML + Neural Engine | Metal only |
| **SPM Integration** | One-line dependency | Complex vendoring |
| **Model Format** | CoreML (optimized per device) | GGML (generic) |
| **Streaming** | First-class async/await | Manual threading |
| **Quality** | Same OpenAI Whisper models | Same OpenAI Whisper models |
| **Maintenance** | Argmax Inc. (commercial) | Community |

Same accuracy, dramatically better Apple platform integration.

