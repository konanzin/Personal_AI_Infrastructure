# Voice

List, choose, test, and persist the PAI desktop voice used by the optional Pulse
renderer.

## Usage

```text
/voice
/voice on
/voice off
/voice pt-BR-AntonioNeural
/voice test
```

## Description

Uses `~/.config/opencode/PAI/bin/voice-config.sh` to list Edge TTS voices,
enable/disable voice feedback, write the selected voice to
`PAI/USER/Config/voice.env`, and optionally test the configured voice.
