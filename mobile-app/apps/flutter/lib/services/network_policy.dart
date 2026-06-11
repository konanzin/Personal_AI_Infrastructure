/// Cleartext (http://) is only acceptable toward the private overlay network.
///
/// Android's network_security_config cannot express IP ranges, and the app's
/// normal use is `http://<tailnet-ip>:4096`, so the platform manifest keeps
/// cleartext enabled and this policy enforces the actual boundary: plain HTTP
/// is allowed only to loopback, RFC1918, CGNAT (Tailscale 100.64/10),
/// link-local/ULA IPv6, and private-mesh hostnames (*.ts.net, *.local,
/// *.internal, bare single-label names). Anything else must use https.
library;

String? cleartextViolation(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null; // unparseable: not ours to judge
  if (uri.scheme != 'http' && uri.scheme != 'ws') return null;
  if (isPrivateHost(uri.host)) return null;
  return 'Plain HTTP to "${uri.host}" is blocked: use https:// or a private '
      'address (tailnet/LAN/localhost).';
}

bool isPrivateHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h == '::1') return true;
  // Single-label hostnames (MagicDNS short names, mDNS) and private suffixes.
  if (!h.contains('.') && !h.contains(':')) return true;
  if (h.endsWith('.ts.net') ||
      h.endsWith('.local') ||
      h.endsWith('.internal') ||
      h.endsWith('.lan') ||
      h.endsWith('.home.arpa')) {
    return true;
  }

  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
      .firstMatch(h);
  if (v4 != null) {
    final a = int.parse(v4.group(1)!);
    final b = int.parse(v4.group(2)!);
    if (a == 127 || a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT / Tailscale
    if (a == 169 && b == 254) return true; // link-local
    return false;
  }

  // IPv6 literals (Uri.host strips the brackets).
  if (h.contains(':')) {
    return h.startsWith('fe80:') || // link-local
        h.startsWith('fc') ||
        h.startsWith('fd'); // ULA fc00::/7
  }

  return false;
}
