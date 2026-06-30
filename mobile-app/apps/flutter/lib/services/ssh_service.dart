import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Formats a host key fingerprint as `<type>:<md5-hex>` (dartssh2 reports
/// the MD5 digest of the host key).
String formatHostKeyFingerprint(String type, Uint8List fingerprint) {
  final hex =
      fingerprint.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$type:$hex';
}

/// Thrown when the remote host key does not match the pinned fingerprint.
class HostKeyMismatchException implements Exception {
  final String expected;
  final String? actual;

  HostKeyMismatchException({required this.expected, this.actual});

  @override
  String toString() =>
      'HostKeyMismatchException: host key changed (expected $expected, '
      'got ${actual ?? 'unknown'})';
}

class SshService {
  SSHClient? _client;
  String? _hostKeyFingerprint;

  bool get isConnected => _client != null;

  /// Fingerprint of the host key seen on the last [connect] attempt.
  String? get hostKeyFingerprint => _hostKeyFingerprint;

  Future<void> connect({
    required String host,
    int port = 22,
    required String username,
    String? privateKeyPem,
    String? password,
    String? expectedHostKeyFingerprint,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    disconnect();
    final identities = privateKeyPem != null && privateKeyPem.trim().isNotEmpty
        ? SSHKeyPair.fromPem(privateKeyPem)
        : const <SSHKeyPair>[];
    final passwordValue =
        password != null && password.isNotEmpty ? password : null;
    if (identities.isEmpty && passwordValue == null) {
      throw StateError('SSH requires a private key or password');
    }

    final pin = expectedHostKeyFingerprint != null &&
            expectedHostKeyFingerprint.isNotEmpty
        ? expectedHostKeyFingerprint
        : null;

    final socket = await SSHSocket.connect(host, port).timeout(timeout);
    _client = SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest:
          passwordValue != null ? () async => passwordValue : null,
      onVerifyHostKey: (type, fingerprint) {
        final value = formatHostKeyFingerprint(type, fingerprint);
        _hostKeyFingerprint = value;
        return pin == null || value == pin;
      },
    );
    try {
      await _client!.authenticated.timeout(timeout);
    } on SSHHostkeyError {
      disconnect();
      if (pin != null && _hostKeyFingerprint != pin) {
        throw HostKeyMismatchException(
            expected: pin, actual: _hostKeyFingerprint);
      }
      rethrow;
    }
  }

  /// Executes a command and returns its stdout. Throws on non-zero exit.
  Future<String> execute(String command) async {
    final client = _client;
    if (client == null) throw StateError('SSH not connected');

    final session = await client.execute(command);
    final stdout = StringBuffer();
    final stderr = StringBuffer();

    final int? exitCode;
    try {
      // Read stdout and stderr concurrently to avoid deadlock when one
      // stream's buffer fills before the other is drained. Output is UTF-8
      // (paths and git output may contain accents); the streaming decoder
      // handles sequences split across chunks.
      await Future.wait([
        session.stdout
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .forEach(stdout.write),
        session.stderr
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .forEach(stderr.write),
      ]);

      // Wait for the process to finish and provide an exit code.
      await session.done;
      exitCode = session.exitCode;
    } finally {
      session.close();
    }

    if (exitCode != null && exitCode != 0) {
      throw SshCommandException(command, exitCode, stderr.toString());
    }
    return stdout.toString().trimRight();
  }

  void disconnect() {
    _client?.close();
    _client = null;
  }
}

class SshCommandException implements Exception {
  final String command;
  final int exitCode;
  final String stderr;

  SshCommandException(this.command, this.exitCode, this.stderr);

  @override
  String toString() =>
      'SshCommandException: command=$command exit=$exitCode stderr=$stderr';
}

/// Shell-safe quoting: wraps value in single quotes, escaping embedded quotes.
String shellEscape(String s) => "'${s.replaceAll("'", r"'\''")}'";

const _remoteOpenCodeLookupScript = r'''
for candidate in "$(command -v opencode 2>/dev/null || true)" "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode" "$HOME/.bun/bin/opencode"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done
printf '%s\n' 'opencode not found' >&2
exit 127
''';

/// Finds OpenCode without mutating PATH, falling back to known install paths.
String remoteOpenCodeLookupCommand() {
  return 'sh -lc ${shellEscape(_remoteOpenCodeLookupScript)}';
}

/// Idempotently installs [authorizedKeysLine] into the remote
/// `~/.ssh/authorized_keys`, creating `~/.ssh` (0700) and the file (0600) if
/// needed. Running it twice with the same key does not duplicate the line.
///
/// The line must be a single trusted line we generated (no newlines); it is
/// passed via a quoted heredoc-free `printf` to avoid any shell interpretation.
String installAuthorizedKeyCommand(String authorizedKeysLine) {
  final line = authorizedKeysLine.trim();
  final script = '''
set -eu
mkdir -p "\$HOME/.ssh"
chmod 700 "\$HOME/.ssh"
ak="\$HOME/.ssh/authorized_keys"
touch "\$ak"
chmod 600 "\$ak"
key=${shellEscape(line)}
if ! grep -qxF "\$key" "\$ak" 2>/dev/null; then
  printf '%s\\n' "\$key" >> "\$ak"
fi
''';
  return 'sh -c ${shellEscape(script)}';
}

const paiDefaultRepositoryUrl =
    'https://github.com/konanzin/Personal_AI_Infrastructure.git';
const paiDefaultRepositoryBranch = 'dori';
const paiDefaultRepositoryDir = r'$HOME/PAI-opencode';

const _installPaiEcosystemScript = r'''
set -eu

log() { printf '[pai-bootstrap] %s\n' "$*"; }
warn() { printf '[pai-bootstrap][warn] %s\n' "$*" >&2; }
die() { printf '[pai-bootstrap][error] %s\n' "$*" >&2; exit "${2:-1}"; }

export PATH="$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.local/bin:$PATH"

repo_url="${PAI_REPO_URL:-https://github.com/konanzin/Personal_AI_Infrastructure.git}"
repo_branch="${PAI_REPO_BRANCH:-dori}"
repo_dir="${PAI_REPO_DIR:-$HOME/PAI-opencode}"

as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
    return $?
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo "$@"
    return $?
  fi
  return 126
}

ensure_base_packages() {
  missing=""
  for cmd in bash git curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing="$missing $cmd"
    fi
  done

  if [ -z "$missing" ]; then
    log "base packages ok"
    return 0
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    die "missing commands:$missing; install bash, git and curl first" 127
  fi

  log "installing base packages:$missing"
  as_root apt-get update ||
    die "root or passwordless sudo is required to install:$missing" 126
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates $missing ||
    die "could not install base packages:$missing" 126
}

ensure_repo() {
  parent="$(dirname "$repo_dir")"
  mkdir -p "$parent"

  if [ -d "$repo_dir/.git" ]; then
    log "updating PAI repository at $repo_dir"
    git -C "$repo_dir" fetch --depth=1 origin "+${repo_branch}:refs/remotes/origin/${repo_branch}" ||
      git -C "$repo_dir" fetch origin "+${repo_branch}:refs/remotes/origin/${repo_branch}" ||
      warn "could not fetch origin/$repo_branch; using current checkout"
    if git -C "$repo_dir" rev-parse --verify "origin/$repo_branch" >/dev/null 2>&1; then
      git -C "$repo_dir" checkout -q -B "$repo_branch" "origin/$repo_branch" ||
        die "could not checkout origin/$repo_branch in $repo_dir" 74
      git -C "$repo_dir" merge --ff-only "origin/$repo_branch" ||
        warn "could not fast-forward $repo_branch; using current checkout"
    fi
  elif [ -e "$repo_dir" ]; then
    die "$repo_dir exists but is not a git repository" 73
  else
    log "cloning PAI repository into $repo_dir"
    git clone --depth=1 --branch "$repo_branch" "$repo_url" "$repo_dir" ||
      { rmdir "$repo_dir" 2>/dev/null || true; git clone "$repo_url" "$repo_dir"; }
  fi

  if [ ! -f "$repo_dir/opencode/install.sh" ]; then
    die "PAI installer not found at $repo_dir/opencode/install.sh" 74
  fi
}

install_pai() {
  log "running PAI installer"
  bash "$repo_dir/opencode/install.sh" --update --no-tts-bootstrap
  export PATH="$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.local/bin:$PATH"

  if ! command -v opencode >/dev/null 2>&1 &&
     [ ! -x "$HOME/.opencode/bin/opencode" ] &&
     [ ! -x "$HOME/.local/bin/opencode" ] &&
     [ ! -x "$HOME/.bun/bin/opencode" ]; then
    die "opencode was not installed by the PAI installer" 127
  fi

  if ! command -v bun >/dev/null 2>&1 && [ ! -x "$HOME/.bun/bin/bun" ]; then
    die "bun was not installed by the PAI installer" 127
  fi

  if [ ! -f "$HOME/.config/opencode/PAI/broker/pulse-broker.ts" ]; then
    die "Pulse Broker files were not installed" 74
  fi

  log "PAI ecosystem installed"
}

ensure_base_packages
ensure_repo
install_pai
''';

/// Installs or updates the full remote PAI/OpenCode ecosystem.
///
/// The command is intentionally idempotent. It guarantees the base OS tools
/// needed by the repo installer, clones/updates the PAI repo, runs
/// `opencode/install.sh --update`, and verifies that OpenCode, Bun, and the
/// Pulse Broker files exist before the mobile bootstrap continues.
String installPaiEcosystemCommand() {
  return 'sh -lc ${shellEscape(_installPaiEcosystemScript)}';
}

const _startPulseBrokerScript = r'''
set -eu

log() { printf '[pai-bootstrap] %s\n' "$*"; }
warn() { printf '[pai-bootstrap][warn] %s\n' "$*" >&2; }
die() { printf '[pai-bootstrap][error] %s\n' "$*" >&2; exit "${2:-1}"; }

export PATH="$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.local/bin:$PATH"

pai_dir="${PAI_DIR:-$HOME/.config/opencode/PAI}"
broker="$pai_dir/broker/pulse-broker.ts"
port="${PULSE_BROKER_PORT:-31337}"
unit_name="pulse-broker.service"
unit_file="$HOME/.config/systemd/user/$unit_name"
state_dir="$HOME/.local/state/pai-mobile"
pid_file="$state_dir/pulse-broker.pid"
log_file="$state_dir/pulse-broker.log"

health() {
  curl -fsS --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1
}

runtime_ready() {
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
  fi
  [ -d "$XDG_RUNTIME_DIR" ] || return 1
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    export DBUS_SESSION_BUS_ADDRESS
  fi
  return 0
}

systemd_available() {
  [ "${PAI_PULSE_NO_SYSTEMD:-0}" = "1" ] && return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  runtime_ready || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

wait_for_health() {
  i=0
  while [ "$i" -lt 20 ]; do
    if health; then
      return 0
    fi
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}

find_bun() {
  if command -v bun >/dev/null 2>&1; then
    command -v bun
    return 0
  fi
  if [ -x "$HOME/.bun/bin/bun" ]; then
    printf '%s\n' "$HOME/.bun/bin/bun"
    return 0
  fi
  return 1
}

write_unit() {
  mkdir -p "$(dirname "$unit_file")"
  cat > "$unit_file" <<EOF
[Unit]
Description=PAI Pulse Broker (notifications fan-out, port $port)
After=network.target

[Service]
Type=simple
Environment=PAI_DIR=$pai_dir
Environment=PULSE_BROKER_PORT=$port
ExecStart="$bun_bin" "$broker" --port "$port"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
}

start_process() {
  mkdir -p "$state_dir"

  if [ -f "$pid_file" ]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      if health; then
        log "Pulse Broker already running pid=$old_pid"
        return 0
      fi
      kill "$old_pid" 2>/dev/null || true
    fi
  fi

  : > "$log_file"
  if command -v setsid >/dev/null 2>&1; then
    setsid "$bun_bin" "$broker" --port "$port" >> "$log_file" 2>&1 < /dev/null &
  else
    nohup "$bun_bin" "$broker" --port "$port" >> "$log_file" 2>&1 < /dev/null &
  fi
  pid="$!"
  printf '%s\n' "$pid" > "$pid_file"

  if wait_for_health; then
    log "Pulse Broker started mode=process pid=$pid port=$port"
    return 0
  fi

  warn "Pulse Broker process did not become healthy"
  tail -n 25 "$log_file" >&2 2>/dev/null || true
  return 1
}

if [ ! -f "$broker" ]; then
  die "Pulse Broker script missing at $broker" 74
fi

bun_bin="$(find_bun)" || die "bun not found; run the PAI installer first" 127

if health; then
  log "Pulse Broker already healthy on port $port"
  exit 0
fi

if systemd_available; then
  write_unit
  systemctl --user daemon-reload || warn "systemctl daemon-reload failed"
  if systemctl --user enable --now "$unit_name"; then
    loginctl enable-linger "$(id -un)" >/dev/null 2>&1 || true
    if wait_for_health; then
      log "Pulse Broker started mode=systemd unit=$unit_name port=$port"
      exit 0
    fi
  fi
  warn "Pulse Broker systemd start failed; trying process fallback"
  journalctl --user -u "$unit_name" -n 25 --no-pager >&2 2>/dev/null || true
fi

start_process
''';

/// Starts the remote Pulse Broker on port 31337 and verifies `/health`.
///
/// It prefers a user systemd service, with a detached process fallback for
/// servers that do not expose a user systemd bus over SSH.
String startPulseBrokerCommand() {
  return 'sh -lc ${shellEscape(_startPulseBrokerScript)}';
}

const paiOpenCodeControllerPath = r'$HOME/.local/bin/pai-opencode';

/// Lifecycle controller installed on the remote machine.
///
/// Supervision is delegated to a systemd user service when available
/// (Restart=always, journald logs, linger across logouts); a supervised
/// background process is the fallback for machines without a user systemd.
/// The bind address is never 0.0.0.0: it resolves to the address the SSH
/// connection arrived on (the same network path the phone uses), then the
/// Tailscale IP, then loopback.
const paiOpenCodeControllerScript = r'''#!/bin/sh
set -u

state_dir="${PAI_OPENCODE_STATE_DIR:-$HOME/.local/state/pai-mobile}"
pid_file="$state_dir/opencode.pid"
log_file="$state_dir/opencode-serve.log"
env_file="$state_dir/opencode.env"
unit_name="pai-opencode.service"
unit_file="$HOME/.config/systemd/user/$unit_name"
host="${OPENCODE_HOST:-}"
port="${OPENCODE_PORT:-4096}"
opencode_bin="${OPENCODE_BIN:-}"
workdir="${OPENCODE_WORKDIR:-$HOME}"
password="${OPENCODE_PASSWORD:-}"

resolve_host() {
  [ -n "$host" ] && return 0
  if [ -n "${SSH_CONNECTION:-}" ]; then
    host="$(printf '%s\n' "$SSH_CONNECTION" | awk '{print $3; exit}')"
  fi
  if [ -z "$host" ] && command -v tailscale >/dev/null 2>&1; then
    host="$(tailscale ip -4 2>/dev/null | head -n 1)"
  fi
  [ -n "$host" ] || host="127.0.0.1"
}

runtime_ready() {
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
  fi
  [ -d "$XDG_RUNTIME_DIR" ] || return 1
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    export DBUS_SESSION_BUS_ADDRESS
  fi
  return 0
}

systemd_available() {
  [ "${PAI_OPENCODE_NO_SYSTEMD:-0}" = "1" ] && return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  runtime_ready || return 1
  systemctl --user show-environment >/dev/null 2>&1
}

read_pid() {
  [ -f "$pid_file" ] || return 1
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  printf '%s\n' "$pid"
}

is_running() {
  pid="$(read_pid)" || return 1
  kill -0 "$pid" 2>/dev/null
}

wait_gone() {
  i=0
  while kill -0 "$1" 2>/dev/null && [ "$i" -lt 20 ]; do
    sleep 0.25
    i=$((i + 1))
  done
  if kill -0 "$1" 2>/dev/null; then
    kill -9 "$1" 2>/dev/null || true
  fi
}

# Stops the legacy pid-file process and any stray `opencode serve` holding
# our port (e.g. left behind by a previous app version), so the unit or the
# fallback process can bind cleanly.
stop_legacy() {
  if is_running; then
    pid="$(read_pid)"
    kill "$pid" 2>/dev/null || true
    wait_gone "$pid"
  fi
  rm -f "$pid_file"
  stray_pid="$(ps -eo pid=,args= 2>/dev/null | awk -v port="$port" '$0 ~ /opencode serve/ && $0 ~ "--port " port { print $1; exit }')"
  if [ -n "$stray_pid" ] && kill -0 "$stray_pid" 2>/dev/null; then
    kill "$stray_pid" 2>/dev/null || true
    wait_gone "$stray_pid"
  fi
}

require_start_inputs() {
  if [ -z "$opencode_bin" ] || [ ! -x "$opencode_bin" ]; then
    printf 'opencode binary is not executable: %s\n' "$opencode_bin" >&2
    return 127
  fi
  if [ ! -d "$workdir" ]; then
    printf 'workdir does not exist: %s\n' "$workdir" >&2
    return 66
  fi
  if [ -z "$password" ] && [ ! -f "$env_file" ]; then
    printf 'OPENCODE_PASSWORD is required\n' >&2
    return 64
  fi
  return 0
}

write_env() {
  umask 077
  printf 'OPENCODE_SERVER_PASSWORD="%s"\n' "$password" > "$env_file"
}

write_unit() {
  mkdir -p "$(dirname "$unit_file")"
  cat > "$unit_file" <<EOF
[Unit]
Description=PAI OpenCode server (managed by pai-mobile)

[Service]
Type=simple
EnvironmentFile=$env_file
WorkingDirectory=$workdir
ExecStart="$opencode_bin" serve --hostname "$host" --port "$port"
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF
}

start_systemd() {
  require_start_inputs || return $?
  resolve_host
  if [ -n "$password" ]; then
    write_env
  fi
  if ! systemctl --user is-active --quiet "$unit_name"; then
    stop_legacy
  fi
  write_unit
  systemctl --user daemon-reload
  systemctl --user enable "$unit_name" >/dev/null 2>&1 || true
  systemctl --user restart "$unit_name"
  loginctl enable-linger "$(id -un)" >/dev/null 2>&1 || true
  i=0
  while [ "$i" -lt 20 ]; do
    if systemctl --user is-active --quiet "$unit_name"; then
      printf 'started mode=systemd host=%s port=%s unit=%s\n' "$host" "$port" "$unit_name"
      return 0
    fi
    sleep 0.5
    i=$((i + 1))
  done
  printf 'opencode failed to start under systemd\n' >&2
  journalctl --user -u "$unit_name" -n 25 --no-pager >&2 2>/dev/null || true
  return 1
}

adopt_existing() {
  existing_pid="$(ps -eo pid=,args= 2>/dev/null | awk -v port="$port" '$0 ~ /opencode serve/ && $0 ~ "--port " port { print $1; exit }')"
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    printf '%s\n' "$existing_pid" > "$pid_file"
    return 0
  fi
  return 1
}

start_process() {
  if is_running; then
    status_server
    return 0
  fi
  if adopt_existing; then
    status_server
    return 0
  fi
  rm -f "$pid_file"

  require_start_inputs || return $?
  if [ -z "$password" ]; then
    printf 'OPENCODE_PASSWORD is required\n' >&2
    return 64
  fi
  resolve_host

  : > "$log_file"
  if command -v setsid >/dev/null 2>&1; then
    OPENCODE_PASSWORD="$password" setsid sh -c 'cd "$1" && export OPENCODE_SERVER_PASSWORD="$OPENCODE_PASSWORD" && unset OPENCODE_PASSWORD && exec "$2" serve --hostname "$3" --port "$4"' pai-opencode "$workdir" "$opencode_bin" "$host" "$port" >> "$log_file" 2>&1 < /dev/null &
  else
    OPENCODE_PASSWORD="$password" sh -c 'cd "$1" && export OPENCODE_SERVER_PASSWORD="$OPENCODE_PASSWORD" && unset OPENCODE_PASSWORD && exec "$2" serve --hostname "$3" --port "$4"' pai-opencode "$workdir" "$opencode_bin" "$host" "$port" >> "$log_file" 2>&1 < /dev/null &
  fi

  pid="$!"
  printf '%s\n' "$pid" > "$pid_file"
  sleep 1

  if is_running; then
    printf 'started mode=process pid=%s host=%s port=%s log=%s\n' "$pid" "$host" "$port" "$log_file"
    return 0
  fi

  rm -f "$pid_file"
  printf 'opencode failed to start; see %s\n' "$log_file" >&2
  return 1
}

start_server() {
  mkdir -p "$state_dir"
  if systemd_available; then
    start_systemd
  else
    start_process
  fi
}

status_server() {
  if [ -f "$unit_file" ] && systemd_available; then
    if systemctl --user is-active --quiet "$unit_name"; then
      printf 'running mode=systemd unit=%s port=%s\n' "$unit_name" "$port"
      return 0
    fi
  fi
  if is_running; then
    printf 'running mode=process pid=%s port=%s log=%s\n' "$(read_pid)" "$port" "$log_file"
    return 0
  fi
  printf 'stopped\n'
  return 3
}

stop_server() {
  if [ -f "$unit_file" ] && systemd_available; then
    systemctl --user disable --now "$unit_name" >/dev/null 2>&1 || true
  fi
  stop_legacy
  printf 'stopped\n'
}

logs_server() {
  lines="$1"
  if [ -f "$unit_file" ] && systemd_available && command -v journalctl >/dev/null 2>&1; then
    journalctl --user -u "$unit_name" -n "$lines" --no-pager 2>/dev/null && return 0
  fi
  if [ -f "$log_file" ]; then
    tail -n "$lines" "$log_file"
  fi
}

case "${1:-status}" in
  start) start_server ;;
  stop) stop_server ;;
  restart) stop_server >/dev/null 2>&1 || true; start_server ;;
  status) status_server ;;
  logs) logs_server "${2:-200}" ;;
  *) printf 'usage: %s {start|stop|restart|status|logs}\n' "$0" >&2; exit 64 ;;
esac
''';

String installPaiOpenCodeControllerCommand() {
  return r'mkdir -p "$HOME/.local/bin" && '
      'printf %s ${shellEscape(paiOpenCodeControllerScript)} > '
      r'"$HOME/.local/bin/pai-opencode" && '
      r'chmod 700 "$HOME/.local/bin/pai-opencode"';
}

String paiOpenCodeControllerCommand(
  String action, {
  String? opencodeBin,
  String? password,
  int? port,
  String? workdir,
}) {
  final assignments = <String>[];
  if (opencodeBin != null) {
    assignments.add('OPENCODE_BIN=${shellEscape(opencodeBin)}');
  }
  if (password != null) {
    assignments.add('OPENCODE_PASSWORD=${shellEscape(password)}');
  }
  if (port != null) {
    assignments.add('OPENCODE_PORT=${shellEscape(port.toString())}');
  }
  if (workdir != null) {
    assignments.add('OPENCODE_WORKDIR=${shellEscape(workdir)}');
  }
  return [
    ...assignments,
    paiOpenCodeControllerPath,
    shellEscape(action),
  ].join(' ');
}
