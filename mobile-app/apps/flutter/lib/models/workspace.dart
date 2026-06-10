class Workspace {
  final String machineId;
  final String path;
  final String displayName;
  final String shortPath;
  final bool isFavorite;
  final DateTime? lastUsed;
  final String? gitBranch;
  final bool? isDirty;
  final int? changedFileCount;

  const Workspace({
    required this.machineId,
    required this.path,
    required this.displayName,
    required this.shortPath,
    this.isFavorite = false,
    this.lastUsed,
    this.gitBranch,
    this.isDirty,
    this.changedFileCount,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      machineId: json['machineId'] as String,
      path: json['path'] as String,
      displayName: json['displayName'] as String,
      shortPath: json['shortPath'] as String,
      isFavorite: json['isFavorite'] as bool? ?? false,
      lastUsed: json['lastUsed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastUsed'] as int)
          : null,
      gitBranch: json['gitBranch'] as String?,
      isDirty: json['isDirty'] as bool?,
      changedFileCount: json['changedFileCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'machineId': machineId,
        'path': path,
        'displayName': displayName,
        'shortPath': shortPath,
        'isFavorite': isFavorite,
        if (lastUsed != null) 'lastUsed': lastUsed!.millisecondsSinceEpoch,
        if (gitBranch != null) 'gitBranch': gitBranch,
        if (isDirty != null) 'isDirty': isDirty,
        if (changedFileCount != null) 'changedFileCount': changedFileCount,
      };

  Workspace copyWith({
    String? machineId,
    String? path,
    String? displayName,
    String? shortPath,
    bool? isFavorite,
    DateTime? lastUsed,
    String? gitBranch,
    bool? isDirty,
    int? changedFileCount,
  }) {
    return Workspace(
      machineId: machineId ?? this.machineId,
      path: path ?? this.path,
      displayName: displayName ?? this.displayName,
      shortPath: shortPath ?? this.shortPath,
      isFavorite: isFavorite ?? this.isFavorite,
      lastUsed: lastUsed ?? this.lastUsed,
      gitBranch: gitBranch ?? this.gitBranch,
      isDirty: isDirty ?? this.isDirty,
      changedFileCount: changedFileCount ?? this.changedFileCount,
    );
  }

  /// Derives display name and short path from an absolute path.
  /// If [homeDir] is provided, replaces the prefix with `~`.
  static Workspace fromPath({
    required String machineId,
    required String absolutePath,
    String? homeDir,
    bool isFavorite = false,
  }) {
    final short = (homeDir != null && absolutePath.startsWith(homeDir))
        ? '~${absolutePath.substring(homeDir.length)}'
        : absolutePath;
    final name = absolutePath.split('/').where((s) => s.isNotEmpty).lastOrNull ??
        absolutePath;
    return Workspace(
      machineId: machineId,
      path: absolutePath,
      displayName: name,
      shortPath: short,
      isFavorite: isFavorite,
      lastUsed: DateTime.now(),
    );
  }
}
