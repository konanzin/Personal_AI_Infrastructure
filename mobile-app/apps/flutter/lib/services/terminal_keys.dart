/// Applies sticky Ctrl/Alt modifiers to a single unit of terminal input,
/// producing the bytes a real terminal would send.
///
/// - Ctrl maps `@`..`_` and `a`..`z` (case-insensitive) to control codes
///   `0x00`..`0x1f` (e.g. `c`/`C` → `0x03`, the SIGINT byte; `[` → `0x1b`).
///   Ctrl is only meaningful for single characters; multi-char input or
///   characters outside the control range pass through unchanged.
/// - Alt prefixes the (possibly Ctrl-transformed) data with ESC (`0x1b`),
///   matching the common "meta sends escape" convention.
///
/// Pure: the caller supplies the modifier state, so this is unit-testable
/// without a widget tree.
String applyTerminalModifiers(
  String data, {
  required bool ctrl,
  required bool alt,
}) {
  var out = data;

  if (ctrl && data.length == 1) {
    final code = data.codeUnitAt(0);
    // Fold lowercase a-z to uppercase so 'c' and 'C' both yield 0x03.
    final upper = (code >= 0x61 && code <= 0x7a) ? code - 0x20 : code;
    // Control range is '@'(0x40)..'_'(0x5f) → 0x00..0x1f.
    if (upper >= 0x40 && upper <= 0x5f) {
      out = String.fromCharCode(upper & 0x1f);
    }
  }

  if (alt) {
    out = '\x1b$out';
  }

  return out;
}
