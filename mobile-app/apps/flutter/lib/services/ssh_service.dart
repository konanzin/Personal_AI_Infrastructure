import 'package:dartssh2/dartssh2.dart';

class SshService {
  SSHClient? _client;

  bool get isConnected => _client != null;

  Future<void> connect({
    required String host,
    int port = 22,
    required String username,
    String? privateKeyPem,
    String? password,
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

    final socket = await SSHSocket.connect(host, port);
    _client = SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest:
          passwordValue != null ? () async => passwordValue : null,
    );
    await _client!.authenticated;
  }

  /// Executes a command and returns its stdout. Throws on non-zero exit.
  Future<String> execute(String command) async {
    final client = _client;
    if (client == null) throw StateError('SSH not connected');

    final session = await client.execute(command);
    final stdout = StringBuffer();
    final stderr = StringBuffer();

    // Read stdout and stderr concurrently to avoid deadlock when one
    // stream's buffer fills before the other is drained.
    await Future.wait([
      session.stdout
          .forEach((chunk) => stdout.write(String.fromCharCodes(chunk))),
      session.stderr
          .forEach((chunk) => stderr.write(String.fromCharCodes(chunk))),
    ]);

    // Wait for the process to finish and provide an exit code.
    await session.done;
    final exitCode = session.exitCode;
    session.close();

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

const paiOpenCodeControllerPath = r'$HOME/.local/bin/pai-opencode';

const paiOpenCodeControllerScript = r'''#!/bin/sh
set -u

state_dir="${PAI_OPENCODE_STATE_DIR:-$HOME/.local/state/pai-mobile}"
pid_file="$state_dir/opencode.pid"
log_file="$state_dir/opencode-serve.log"
host="${OPENCODE_HOST:-0.0.0.0}"
port="${OPENCODE_PORT:-4096}"
opencode_bin="${OPENCODE_BIN:-}"
workdir="${OPENCODE_WORKDIR:-$HOME}"
password="${OPENCODE_PASSWORD:-}"

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

adopt_existing() {
  existing_pid="$(ps -eo pid=,args= 2>/dev/null | awk -v port="$port" '$0 ~ /opencode serve/ && $0 ~ "--port " port { print $1; exit }')"
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    mkdir -p "$state_dir"
    printf '%s\n' "$existing_pid" > "$pid_file"
    return 0
  fi
  return 1
}

status_server() {
  if is_running; then
    pid="$(read_pid)"
    printf 'running pid=%s port=%s log=%s\n' "$pid" "$port" "$log_file"
    return 0
  fi
  printf 'stopped\n'
  return 3
}

start_server() {
  mkdir -p "$state_dir"
  if is_running; then
    status_server
    return 0
  fi
  if adopt_existing; then
    status_server
    return 0
  fi
  rm -f "$pid_file"

  if [ -z "$opencode_bin" ] || [ ! -x "$opencode_bin" ]; then
    printf 'opencode binary is not executable: %s\n' "$opencode_bin" >&2
    return 127
  fi
  if [ ! -d "$workdir" ]; then
    printf 'workdir does not exist: %s\n' "$workdir" >&2
    return 66
  fi
  if [ -z "$password" ]; then
    printf 'OPENCODE_PASSWORD is required\n' >&2
    return 64
  fi

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
    printf 'started pid=%s port=%s log=%s\n' "$pid" "$port" "$log_file"
    return 0
  fi

  rm -f "$pid_file"
  printf 'opencode failed to start; see %s\n' "$log_file" >&2
  return 1
}

stop_server() {
  if ! is_running; then
    rm -f "$pid_file"
    printf 'stopped\n'
    return 0
  fi

  pid="$(read_pid)"
  kill "$pid" 2>/dev/null || true
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do
    sleep 0.25
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
  printf 'stopped pid=%s\n' "$pid"
}

case "${1:-status}" in
  start) start_server ;;
  stop) stop_server ;;
  restart) stop_server >/dev/null 2>&1 || true; start_server ;;
  status) status_server ;;
  *) printf 'usage: %s {start|stop|restart|status}\n' "$0" >&2; exit 64 ;;
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
