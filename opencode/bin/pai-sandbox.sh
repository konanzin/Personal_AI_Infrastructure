#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  pai-sandbox.sh — T1 filesystem sandbox for PAI bash commands
#
#  Wraps a single command string in bubblewrap so the OpenCode
#  allow-by-default bash posture is bounded by the kernel, not
#  only by the regex deny floor in pai-hooks.js:
#
#    - Root filesystem read-only; writes allowed only in the
#      working directory, /tmp, PAI/MEMORY, PAI/logs, and
#      common toolchain caches.
#    - Credential directories (ssh, aws, gnupg, gh, kube, ...)
#      and PAI/USER (life data) are masked with empty tmpfs —
#      unreadable even though the rest of $HOME is visible.
#    - Network stays ON in T1 (dev workflows need it); egress
#      control is the T2 phase. Env vars also pass through.
#
#  T1 scope: this is filesystem confinement. The wrapper FAILS
#  OPEN — if bwrap is missing the command runs unwrapped, which
#  is exactly the pre-sandbox behavior.
#
#  Escalation: when a wrapped command exits nonzero, a stderr
#  hint explains how to rerun outside the sandbox by prefixing
#  `pai-nosandbox ` — that command token is configured as "ask" in
#  opencode.jsonc, so escaping the sandbox always requires a
#  human approval prompt.
#
#  Usage: pai-sandbox.sh '<command string>'
# ═══════════════════════════════════════════════════════════

set -u
CMD="${1:?usage: pai-sandbox.sh '<command string>'}"

# Fail-open: no bwrap → run unwrapped (pre-sandbox behavior).
if ! command -v bwrap >/dev/null 2>&1; then
    exec /bin/bash -c "$CMD"
fi

PAI_DIR="${PAI_DIR:-$HOME/.config/opencode/PAI}"

ARGS=(
    --ro-bind / /
    --dev /dev
    --proc /proc
    --die-with-parent
    --setenv PAI_SANDBOXED 1
)

# Bind order matters: later mounts shadow earlier ones, so rw binds come
# first and secret masks last (protects secrets even when $PWD is $HOME).
rw()   { [ -e "$1" ] && ARGS+=(--bind "$1" "$1"); return 0; }
mask() { [ -e "$1" ] && ARGS+=(--tmpfs "$1"); return 0; }
maskfile() { [ -f "$1" ] && ARGS+=(--ro-bind /dev/null "$1"); return 0; }

# ── Writable surfaces ─────────────────────────────────────
rw /tmp
rw /var/tmp
rw "$PWD"
rw "$PAI_DIR/MEMORY"
rw "$PAI_DIR/logs"
# Toolchain caches (bun/npm/flutter/gradle/android/rust/go/maven/pnpm)
for d in .cache .bun .npm .pub-cache .gradle .android .cargo .rustup .m2 \
         go/pkg .local/state .local/share/pnpm; do
    rw "$HOME/$d"
done

# ── Secret masks (empty tmpfs / null file) ────────────────
for d in .ssh .aws .gnupg .kube .docker .azure \
         .config/gh .config/gcloud; do
    mask "$HOME/$d"
done
mask "$PAI_DIR/USER"
maskfile "$HOME/.netrc"
maskfile "$HOME/.npmrc"
maskfile "$HOME/.cargo/credentials.toml"

bwrap "${ARGS[@]}" /bin/bash -c "$CMD"
rc=$?
if [ $rc -ne 0 ]; then
    echo "[PAI-SANDBOX] exit $rc inside the filesystem sandbox (read-only outside \$PWD; credentials masked; unix sockets like docker unavailable). If the failure is sandbox-caused, rerun prefixed with: pai-nosandbox <command>  — this always triggers a human approval prompt." >&2
fi
exit $rc
