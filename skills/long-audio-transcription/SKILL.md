---
name: long-audio-transcription
description: "Process long audio recordings with normalization, overlapping chunking, Whisper transcription, global timestamp restoration, duplicate removal, and domain terminology prompts."
---

# Long Audio Transcription

## Workflow

1. Probe source audio with ffprobe.
2. Convert to 16 kHz mono PCM WAV with ffmpeg.
3. Apply optional speech enhancement and loudness normalization.
4. Split long recordings into 5-10 minute chunks with 3-5 second overlap.
5. Transcribe chunks using faster-whisper or openai-whisper.
6. Restore original global timestamps.
7. Remove repeated text in overlap regions.
8. Apply only explicit terminology corrections.
9. Export TXT, SRT, JSON, and processing metadata.

## Quality rules

- Keep raw transcription separate from corrected transcription.
- Never invent unclear speech.
- Mark uncertain sections for review.
- Preserve original timeline coverage.

## Typical use

Suitable for meetings, defenses, interviews, lectures, and research discussions containing technical terminology.
