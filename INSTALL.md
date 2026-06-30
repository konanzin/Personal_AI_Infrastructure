# Install PAI for OpenCode

## Prerequisites

- `git`
- `curl`

`opencode`, `bun`, and the managed Edge TTS Python dependency are now **bootstrapped automatically** by the installer when missing. Use `--no-bootstrap` if you want strict/offline installation instead.

## Update Existing Install

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

## Fresh Install From This Repo

```bash
cd ~/PAI-opencode
./opencode/install.sh
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

Strict mode (do not auto-install dependencies):

```bash
./opencode/install.sh --no-bootstrap
```

## What The Installer Updates / Bootstraps

- `~/.config/opencode/plugins/pai-hooks.js`
- `~/.config/opencode/plugins/lib/pai-hooks.lib.js`
- `~/.config/opencode/plugins/lib/mode-classifier.lib.js`
- `~/.config/opencode/agents/*.md`
- `~/.config/opencode/commands/*.md`
- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/PAI/bin/*.sh`
- PAI metadata files from `opencode/config/`
- `opencode` binary when missing
- `bun` runtime when missing
- Edge TTS managed venv at `~/.config/opencode/tts-venv`, unless `--no-tts-bootstrap` is used

## Pulse Scope

This installer ships both the **Pulse scaffold** and the lean optional **Pulse Broker**:

- `~/.config/opencode/PAI/PULSE/PULSE.toml`
- related docs and directory structure
- `~/.config/opencode/PAI/broker/` with the Bun broker, desktop renderer, Edge TTS speaker, and systemd user service template
- `~/.config/opencode/tts-venv` with the `edge-tts` Python package, unless `--no-bootstrap` or `--no-tts-bootstrap` is used

It does **not** provision or require the upstream desktop Pulse daemon. A missing or stopped broker on `localhost:31337` is therefore **not** treated as an installation failure for this branch.

It also removes the obsolete `~/.config/opencode/plugins/pai-hooks.lib.js` root copy because OpenCode auto-discovers root plugin files.

## Preserved Data

The installer does not intentionally delete installed `USER` or `MEMORY` data. Update mode creates a timestamped backup of `~/.config/opencode/PAI` before writing files.

## Validate

Expected successful state:

```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

The validator currently checks 112 structural points and then runs the behavioral suite (109 checks, including promise-integrity checks, the Edge TTS provider dependency, and the `/voice` helper) and the E2E suite (11 scenarios). Its Pulse checks validate installed scaffold/broker assets and desktop voice readiness, not a live daemon.

## Pulse Broker (optional runtime)

The installer ships the **Pulse Broker** to `~/.config/opencode/PAI/broker/` — a small Bun daemon that tails `MEMORY/OBSERVABILITY/notifications.jsonl` (see `opencode/docs/NOTIFICATIONS_STREAM.md`) and fans events out to identified renderers over SSE on port 31337, with `/health` and an upstream-compatible `/notify`. It is **optional**: a missing/stopped broker is not an install failure; agents' health-gated voice curls simply stay silent.

```bash
# Run ad hoc
bun ~/.config/opencode/PAI/broker/pulse-broker.ts

# Or as a user service
cp ~/.config/opencode/PAI/broker/pulse-broker.service.template ~/.config/systemd/user/pulse-broker.service
systemctl --user daemon-reload && systemctl --user enable --now pulse-broker

# Watch/listen from any terminal
bun ~/.config/opencode/PAI/broker/renderer-desktop.ts --tts

# List and persist the desktop voice
~/.config/opencode/PAI/bin/voice-config.sh list pt-BR
~/.config/opencode/PAI/bin/voice-config.sh set pt-BR-AntonioNeural
~/.config/opencode/PAI/bin/voice-config.sh off
~/.config/opencode/PAI/bin/voice-config.sh on
```

### Desktop voice (Edge TTS)

The desktop renderer's `--tts` uses the bundled Edge TTS speaker by default. It
uses the managed Python venv at `~/.config/opencode/tts-venv`, generates MP3
files in `/tmp`, and plays them with `ffplay` or `mpg123` (`afplay` on macOS).
The normal installer prepares that venv up front. `--no-tts-bootstrap` skips
only this desktop voice dependency, which is useful for mobile-only remote
bootstraps. If you install with `--no-bootstrap`/`--no-tts-bootstrap` or delete
the venv later, the speaker can still auto-install on first use unless
`PAI_EDGE_TTS_AUTO_INSTALL=false` is set.

```bash
bun ~/.config/opencode/PAI/broker/renderer-desktop.ts --tts
```

Useful overrides:

```bash
PAI_EDGE_TTS_VOICE_PT_BR=pt-BR-AntonioNeural
PAI_EDGE_TTS_VOICE_EN_US=en-US-AvaNeural
PAI_EDGE_TTS_RATE=+15%
PAI_EDGE_TTS_VOLUME=+0%
PAI_EDGE_TTS_AUTO_INSTALL=false
PAI_AUDIO_PLAYER_CMD="/custom/player"
```

Persistent voice choices and on/off state are saved in
`~/.config/opencode/PAI/USER/Config/voice.env`. Use `/voice` inside OpenCode
for an assisted flow that lists voices, saves the selected one, or toggles voice
feedback with `/voice on` and `/voice off`.

Set `PULSE_TTS_CMD` to replace Edge TTS entirely with a long-running command
that reads one plain-text utterance per stdin line:

```bash
PULSE_TTS_CMD="/path/to/speaker" bun ~/.config/opencode/PAI/broker/renderer-desktop.ts --tts
```

## Path Migration

Upstream PAI was built for Claude Code and hardcodes `~/.claude/` across vendored skills and docs. The installer rewrites those to `~/.config/opencode/` in the **installed copies** (`patch_installed_paths` step). Files in the repo stay pristine so diffs against upstream remain clean; only the installed tree is patched. `~/.config/opencode/PAI/bin/` scripts are excluded (they are repo-native and scan for leftover legacy paths themselves).
