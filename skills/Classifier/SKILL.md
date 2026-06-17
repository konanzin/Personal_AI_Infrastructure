---
name: Classifier
description: "Sets or updates the PAI prompt-classifier model for this machine — the model that classifies each prompt's mode/tier. Discovers the real available models with `opencode models` (one provider/model per line), asks the principal which to use and whether to run the LLM classifier or the local heuristic, then writes ~/.config/opencode/PAI/USER/Config/classifier.json. The PAI hooks plugin reads that file hot (mtime-cached) so the change applies with no server restart. Server precedence is env var > this file > built-in default, so a PAI_CLASSIFIER_* env var still wins for debug/offline runs. The same file is writable per-machine from the PAI Mobile app, so phone and CLI changes touch one config. USE WHEN /classifier, set the classifier model, change the classification model, which model classifies my prompts, switch classifier to <model>, turn the LLM classifier on/off, use heuristic classifier only. NOT FOR the full onboarding interview (use Interview/​/interview), editing TELOS or preferences, or choosing the main chat/build model (that is opencode.jsonc `model`)."
---

# Classifier — set the prompt-classifier model

A focused, one-purpose flow: choose which model PAI uses to classify each prompt's
mode/tier, and whether to run the LLM classifier at all. Writes a single config file
the runtime reads hot.

## Workflow

### Step 1 — Discover the real models

Run the CLI — it lists exactly the models the principal has configured/authenticated,
one `provider/model` per line. Never invent or guess model IDs.

```bash
opencode models
```

Use `opencode models <provider>` to filter (e.g. `opencode models kimi-for-coding`).
Present the actual list. If the principal already has a classifier set, read the
current value first so you can show it:

```bash
cat ~/.config/opencode/PAI/USER/Config/classifier.json 2>/dev/null || echo '(none — using server default)'
```

### Step 2 — Ask, one question at a time

1. "Which model should classify your prompts? Pick one from the list (as
   `provider/model`), or say 'default' to keep the built-in
   `opencode/deepseek-v4-flash-free`."
2. "Run the LLM classifier, or just the local heuristic? The heuristic is instant and
   free; the LLM is more accurate but costs one call per prompt."

Don't dump both at once. Confirm the choice back in the principal's own words.

### Step 3 — Write the config

Write `~/.config/opencode/PAI/USER/Config/classifier.json` with only the fields the
principal chose. Merge — don't clobber unrelated keys if the file already exists.

```json
{ "model": "kimi-for-coding/k2p6", "useLLM": true }
```

- `model` — a `provider/model` string from Step 1. Omit (or pick 'default') to fall
  back to the built-in default.
- `useLLM` — `true` to run the LLM classifier, `false` for the heuristic only.

The PAI hooks plugin reads this file with an mtime cache, so the change is **live on
the next prompt — no server restart**. Precedence on the server is
`env var > this file > built-in default`.

### Step 4 — Confirm

Voice-confirm the change, e.g.:

```bash
(curl -s --max-time 2 -X POST http://localhost:31337/notify \
  -H "Content-Type: application/json" \
  -d '{"message": "Classifier set to kimi-for-coding/k2p6 — live now.", "language": "en-US"}' \
  > /dev/null 2>&1 || true) &
```

## Rules

- **Real models only.** Always source names from `opencode models`; never guess.
- **One question at a time.** Model first, then the LLM/heuristic toggle.
- **Merge, don't clobber.** Preserve any other keys already in `classifier.json`.
- **No restart talk.** The file is read hot; don't tell the principal to restart.
- **Don't touch the chat model.** This sets the *classifier* model only, not the main
  `model` in `opencode.jsonc`.

## Related

- `/interview` — full onboarding; its closing step offers this same classifier choice.
- PAI Mobile machine editor — writes the same `classifier.json` per-machine over SSH.
