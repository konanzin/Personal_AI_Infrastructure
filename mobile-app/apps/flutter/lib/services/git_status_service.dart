import 'ssh_service.dart';

class GitStatus {
  final String? branch;
  final bool isDirty;
  final int changedFileCount;

  const GitStatus({
    this.branch,
    this.isDirty = false,
    this.changedFileCount = 0,
  });
}

class GitStatusService {
  final SshService _ssh;

  GitStatusService(this._ssh);

  Future<GitStatus> getStatus(String directory) async {
    final escaped = shellEscape(directory);

    String? branch;
    try {
      branch = await _ssh.execute(
          'git -C $escaped rev-parse --abbrev-ref HEAD');
      if (branch == 'HEAD') {
        // Detached HEAD -- show short SHA instead
        branch = await _ssh.execute(
            'git -C $escaped rev-parse --short HEAD');
      }
    } on SshCommandException {
      // Not a git repo or git not installed
      return const GitStatus();
    }

    String porcelain;
    try {
      porcelain = await _ssh.execute(
          'git -C $escaped status --porcelain');
    } on SshCommandException {
      return GitStatus(branch: branch);
    }

    final lines = porcelain.isEmpty
        ? <String>[]
        : porcelain.split('\n').where((l) => l.isNotEmpty).toList();

    return GitStatus(
      branch: branch,
      isDirty: lines.isNotEmpty,
      changedFileCount: lines.length,
    );
  }
}
