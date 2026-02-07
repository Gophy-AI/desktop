# Gophy Desktop

AI-powered call assistant for macOS — real-time transcription, contextual suggestions, document RAG, meeting recording, and automation.

## Requirements

- macOS 14.4+ (for ProcessTap system audio capture)
- Apple Silicon (M1+) — required for on-device MLX inference
- ~12GB disk space for all default models

## Build & Run

```bash
cd desktop
swift build
swift test
```

## Architecture

Swift 6 strict concurrency with actor-based engine isolation. Hybrid local/cloud AI — on-device MLX models as primary, cloud providers (Anthropic, OpenAI) as fallback.

### Engines

| Engine | Purpose | Default Model |
|--------|---------|---------------|
| TranscriptionEngine | Speech-to-text | WhisperKit large-v3-turbo (1.5GB) |
| TextGenerationEngine | Summaries, suggestions, tool calling | Qwen2.5 7B / Qwen3 8B 4-bit |
| OCREngine | Image & PDF text extraction | Qwen2.5-VL 7B 4-bit (5.3GB) |
| EmbeddingEngine | Semantic search vectors | Multilingual E5 Small (0.47GB) |

All engines support swapping to cloud providers per-capability via the Provider Registry.

## Features

### Real-Time Meeting Transcription

- Concurrent microphone + system audio capture
- Per-speaker transcription with diarization (FluidAudio)
- Voice Activity Detection with configurable sensitivity
- System audio via ProcessTap API (no Screen Recording permission needed)
- Language detection and configurable language hints

### Contextual Suggestions

- Auto-generated every 30 seconds during meetings
- Uses recent transcript + RAG context from documents and past meetings
- Streaming token display in suggestion panel

### Document Management & RAG

- **Supported formats**: PDF, TXT, Markdown, PNG, JPG
- OCR for scanned PDFs and images via vision language models
- Automatic chunking (configurable size/overlap) and embedding indexing
- Vector similarity search via sqlite-vec
- Scoped queries: all content, meetings only, documents only, or specific items

### Meeting Recording & Playback

- Full session lifecycle: idle → recording → completed
- Audio waveform timeline with speaker diarization overlay
- Transcript-synchronized playback
- Export transcripts with speaker labels and timestamps
- Import audio files or transcripts for processing

### Google Calendar Integration

- OAuth 2.0 authentication with secure Keychain storage
- Incremental sync with sync tokens
- Auto-start recording when calendar meetings begin (configurable lead time)
- Write meeting summaries back to calendar event descriptions
- Fallback to local EventKit calendar

### Automations

- **Voice commands**: Regex-based pattern detection with cooldown
- **Keyboard shortcuts**: System-level per-meeting activation
- **Tool calling pipeline**: Multi-turn LLM orchestration with tool execution
- **Action tiers**: allow (auto-execute), confirm (ask user), review (show details)
- **Undo stack**: Per-meeting tool execution history with rollback
- **Built-in tools**: remember, take_note, search_knowledge, generate_summary

### Chat

- RAG-powered Q&A across meetings and documents
- Scoped context (specific meeting, document, or all)
- Conversation history per meeting
- Streaming responses

### Model Management

- Dynamic model registry: curated + all models from MLXLLM, MLXVLM, MLXEmbedders registries
- Per-task model selection (STT, text generation, OCR, embedding)
- Download progress tracking with disk space validation
- Browse, download, delete, and switch models from the UI

## Cloud Providers

| Provider | Capabilities |
|----------|-------------|
| Anthropic (Claude) | Text generation, vision/OCR |
| OpenAI-compatible | Text generation, embeddings, STT |

API keys are stored in macOS Keychain. Each capability (text, embedding, STT, vision) can independently use local or cloud.

## Data Storage

- **Database**: SQLite via GRDB with migrations
- **Vector search**: sqlite-vec extension for dense embeddings
- **Models**: `~/Library/Application Support/Gophy/models/`
- **Recordings**: `~/Library/Application Support/Gophy/recordings/`

## Dependencies

| Package | Purpose |
|---------|---------|
| mlx-swift-lm (vendored) | LLM, VLM, and embedding inference |
| WhisperKit | Speech-to-text |
| GRDB.swift | SQLite database |
| GTMAppAuth / AppAuth | Google OAuth |
| MacPaw/OpenAI | OpenAI API client |
| SwiftAnthropic | Anthropic API client |
| DSWaveformImage | Audio waveform visualization |

## Project Structure

```
desktop/
├── Sources/Gophy/
│   ├── Audio/          # Mic capture, system audio, VAD, mixer, diarization
│   ├── Automations/    # Voice commands, keyboard triggers, tool calling
│   ├── Calendar/       # Google Calendar sync, EventKit, writeback
│   ├── Data/           # Database, repositories, document processor
│   ├── Engines/        # Transcription, OCR, text gen, embedding, mode controller
│   ├── Models/         # Model registry, definitions, download manager
│   ├── Providers/      # Cloud provider abstractions (Anthropic, OpenAI)
│   ├── Services/       # Storage, crash reporter, keychain, HF downloader
│   └── Views/          # SwiftUI views, settings, onboarding
├── Resources/          # App icon, entitlements, Info.plist
└── vendor/mlx-swift-lm/ # Vendored MLX Swift with local patches
```
