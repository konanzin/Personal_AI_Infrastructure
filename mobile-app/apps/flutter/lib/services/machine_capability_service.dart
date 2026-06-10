import '../models/machine.dart';
import 'git_status_service.dart';
import 'pai_agent_client.dart';
import 'ssh_service.dart';

/// Capability probe result for a machine.
enum MachineHealth {
  /// OpenCode + PAI agent online
  full,
  /// OpenCode online, no agent
  partial,
  /// Unreachable
  offline,
}

/// Provides machine capabilities with graceful fallback:
/// 1. PAI Agent HTTP API (if available)
/// 2. SSH (if configured)
/// 3. Disabled gracefully
class MachineCapabilityService {
  final Machine machine;
  final PaiAgentClient? _agent;
  SshService? _ssh;

  MachineCapabilityService(this.machine)
      : _agent = machine.paiAgentUrl != null
            ? PaiAgentClient(baseUrl: machine.paiAgentUrl!)
            : null;

  Future<MachineHealth> checkHealth() async {
    final agentOk = _agent != null && await _agent.isAvailable();
    if (agentOk) return MachineHealth.full;

    // Try SSH as basic connectivity check
    if (machine.ssh != null) {
      try {
        final ssh = SshService();
        await ssh.connect(
          host: machine.ssh!.host,
          port: machine.ssh!.port,
          username: machine.ssh!.username,
          privateKeyPem: machine.ssh!.privateKey,
          password: machine.ssh!.password,
        );
        ssh.disconnect();
        return MachineHealth.partial;
      } catch (_) {
        return MachineHealth.offline;
      }
    }

    return MachineHealth.partial;
  }

  Future<GitStatus> getGitStatus(String directory) async {
    // Try agent first
    if (_agent != null) {
      try {
        return await _agent.getGitStatus(directory);
      } catch (_) {}
    }

    // Fallback to SSH
    if (machine.ssh != null) {
      final ssh = await _connectSsh();
      if (ssh != null) {
        try {
          return await GitStatusService(ssh).getStatus(directory);
        } finally {
          ssh.disconnect();
        }
      }
    }

    return const GitStatus();
  }

  Future<List<String>> discoverWorkspaces() async {
    if (_agent != null) {
      try {
        return await _agent.discoverWorkspaces();
      } catch (_) {}
    }
    return [];
  }

  Future<SshService?> _connectSsh() async {
    final ssh = machine.ssh;
    if (ssh == null) return null;
    try {
      _ssh = SshService();
      await _ssh!.connect(
        host: ssh.host,
        port: ssh.port,
        username: ssh.username,
        privateKeyPem: ssh.privateKey,
        password: ssh.password,
      );
      return _ssh;
    } catch (_) {
      _ssh?.disconnect();
      _ssh = null;
      return null;
    }
  }

  void dispose() {
    _agent?.close();
    _ssh?.disconnect();
  }
}
