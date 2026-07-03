# Security pattern reference corpus

Vendored, read-only reference corpus used to **cross-check and selectively harvest**
security patterns for PAI's own banks. This is NOT loaded at runtime.

## Contents

- `opencode-policy-unsafe-tool-patterns.json` — 255 bash/tool patterns from
  [`opencode-policy`](https://www.npmjs.com/package/opencode-policy) v0.1.4 (MIT).
- `opencode-policy-prompt-injection-patterns.json` — 27 prompt-injection patterns (same source).
- `opencode-policy-LICENSE` — upstream MIT license.

## Why only a curated subset was imported

`opencode-policy` is deliberately aggressive: many of its 255 patterns are noisy or
high-false-positive (`bash -i` blocks any interactive shell, `printenv`/`set`/`export`
blocked as env leaks, `for ...; do ...&; done` blocked as fork bombs, `reversed(` for
"obfuscation"). Importing them wholesale would reintroduce exactly the friction the
automode work is removing, and much of that surface (egress, .env reads, credential
dirs) is already covered by PAI's existing pattern banks.

We imported only **high-severity, low-false-positive catastrophic signatures** that
PAI's banks lacked:

- Crypto miners: `xmrig`, `cpuminer`/`minerd`/`ccminer`/`ethminer`, `stratum+tcp/ssl://`
- Reverse shells: `nc -e`, `socat exec:`, `/dev/tcp` redirects, perl/ruby/php socket shells

These live in `plugins/lib/pai-hooks.lib.js` (`DEFAULT_SECURITY_POLICY_OBJ.bash.blocked`)
and the seed `PAI/DOCUMENTATION/Security/Patterns.example.yaml`, with tests in
`tests/security-pipeline.test.ts` (both "must deny" and "must NOT over-block").

To expand coverage later, mine this corpus again — but keep the selectivity bar high so
automode stays low-friction.
