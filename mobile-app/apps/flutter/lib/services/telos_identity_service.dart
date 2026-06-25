/// Reads the PAI user's name from the server's principal-identity file.
///
/// `/interview` writes `PRINCIPAL_IDENTITY.md` on the OpenCode server; its
/// `- **Name:** <value>` quick-reference line is the friendly name we greet
/// with on the home screen (Gemini-style). Until the interview runs, the file
/// holds the bootstrap placeholder ("User"), which we treat as "no name".
const principalIdentityPath =
    r'~/.config/opencode/PAI/USER/PRINCIPAL_IDENTITY.md';

/// Command to read the identity file; tolerant when it's absent.
String catPrincipalIdentityCommand() =>
    'cat $principalIdentityPath 2>/dev/null || true';

/// Extracts the user's name from PRINCIPAL_IDENTITY.md content, or null when
/// it's missing or still the bootstrap placeholder.
String? parsePrincipalName(String markdown) {
  final match = RegExp(r'-\s*\*\*Name:\*\*\s*(.+)').firstMatch(markdown);
  if (match == null) return null;
  final name = match.group(1)!.trim();
  if (name.isEmpty ||
      name.toLowerCase() == 'user' ||
      name.contains('(interview)')) {
    return null;
  }
  return name;
}

/// First name only, for a Gemini-style "Boa tarde, {first}" greeting.
String firstNameOf(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? fullName.trim() : parts.first;
}
