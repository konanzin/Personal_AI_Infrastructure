#!/usr/bin/env python3
"""Persistent Kokoro TTS speaker for the Pulse Broker desktop renderer.

Reads one utterance per stdin line and speaks it. The ONNX model (~325MB)
is loaded once at startup, so per-utterance latency is synthesis-only.

Run with the python that has kokoro-onnx installed (e.g. the kokoro-tts
pipx venv): renderer-desktop.ts resolves this automatically.

Env:
  KOKORO_MODEL   path to kokoro-v1.0.onnx   (default ~/.local/share/kokoro/kokoro-v1.0.onnx)
  KOKORO_VOICES  path to voices-v1.0.bin    (default ~/.local/share/kokoro/voices-v1.0.bin)
  KOKORO_VOICE   voice name                 (default pf_dora — Brazilian Portuguese)
  KOKORO_LANG    espeak language code       (default pt-br)
  KOKORO_SPEED   speech speed               (default 1.0)
"""

import os
import subprocess
import sys
import tempfile

import soundfile as sf
from kokoro_onnx import Kokoro

HOME = os.path.expanduser("~")
MODEL = os.environ.get("KOKORO_MODEL", f"{HOME}/.local/share/kokoro/kokoro-v1.0.onnx")
VOICES = os.environ.get("KOKORO_VOICES", f"{HOME}/.local/share/kokoro/voices-v1.0.bin")
VOICE = os.environ.get("KOKORO_VOICE", "pf_dora")
LANG = os.environ.get("KOKORO_LANG", "pt-br")
SPEED = float(os.environ.get("KOKORO_SPEED", "1.0"))


def main() -> None:
    kokoro = Kokoro(MODEL, VOICES)
    print(f"[kokoro-say] ready (voice={VOICE}, lang={LANG})", flush=True)

    for line in sys.stdin:
        text = line.strip()
        if not text:
            continue
        try:
            samples, sample_rate = kokoro.create(text, voice=VOICE, lang=LANG, speed=SPEED)
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                sf.write(tmp.name, samples, sample_rate)
                path = tmp.name
            subprocess.run(["paplay", path], check=False)
            os.unlink(path)
        except Exception as exc:  # one bad utterance must not kill the speaker
            print(f"[kokoro-say] error: {exc}", file=sys.stderr, flush=True)


if __name__ == "__main__":
    main()
