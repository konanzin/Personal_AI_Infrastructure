import 'package:flutter/material.dart';

import '../providers/opencode_provider.dart';
import 'autocomplete_overlay.dart';

/// Drives the chat input's `/command` and `@file` autocomplete: trigger
/// detection on the text field, server-backed suggestion fetching (with
/// debounce for file search) and the floating overlay anchored to the input.
///
/// Extracted from `chat_screen.dart`; the screen only constructs/disposes it
/// and hands [layerLink] to the input bar.
class ChatAutocompleteController {
  ChatAutocompleteController({
    required this.textController,
    required OpenCodeProvider? Function() provider,
    required BuildContext Function() context,
    required bool Function() mounted,
  })  : _provider = provider,
        _context = context,
        _mounted = mounted {
    textController.addListener(_onTextChanged);
  }

  final TextEditingController textController;
  final OpenCodeProvider? Function() _provider;
  final BuildContext Function() _context;
  final bool Function() _mounted;

  /// Anchor shared with the input bar so the overlay follows it.
  final LayerLink layerLink = LayerLink();

  OverlayEntry? _overlayEntry;
  List<AutocompleteSuggestion> _suggestions = [];
  int _highlight = -1;
  String _trigger = ''; // '/' or '@'
  int _triggerOffset = 0; // cursor offset where trigger started
  List<dynamic>? _cachedCommands;
  int _debounceSeq = 0;

  void dispose() {
    textController.removeListener(_onTextChanged);
    dismiss();
  }

  void _onTextChanged() {
    final text = textController.text;
    final cursor = textController.selection.baseOffset;
    if (cursor < 0) {
      dismiss();
      return;
    }

    // Slash trigger: text starts with "/" and cursor is still in the command word
    if (text.startsWith('/')) {
      final afterSlash = text.substring(1, cursor.clamp(1, text.length));
      if (!afterSlash.contains(' ')) {
        _trigger = '/';
        _triggerOffset = 0;
        _fetchSlashSuggestions(afterSlash);
        return;
      }
    }

    // At trigger: find the last "@" before the cursor with no space between it and cursor
    final textBeforeCursor = text.substring(0, cursor.clamp(0, text.length));
    final atIdx = textBeforeCursor.lastIndexOf('@');
    if (atIdx >= 0) {
      final query = textBeforeCursor.substring(atIdx + 1);
      if (!query.contains(' ')) {
        _trigger = '@';
        _triggerOffset = atIdx;
        _fetchFileSuggestions(query);
        return;
      }
    }

    dismiss();
  }

  Future<void> _fetchSlashSuggestions(String prefix) async {
    final provider = _provider();
    if (provider == null) return;
    _cachedCommands ??= await provider.client.getCommands();
    final cmds = _cachedCommands!;
    final filtered = prefix.isEmpty
        ? cmds
        : cmds.where((c) {
            final name = (c is Map ? c['name'] : '$c') as String? ?? '';
            return name.toLowerCase().startsWith(prefix.toLowerCase());
          }).toList();

    final suggestions = filtered.map((c) {
      final name = c is Map ? c['name'] as String? ?? '' : '$c';
      final desc = c is Map ? c['description'] as String? : null;
      return AutocompleteSuggestion(
        icon: Icons.terminal,
        title: '/$name',
        subtitle: desc,
        insertText: '/$name ',
      );
    }).toList();

    _showSuggestions(suggestions);
  }

  Future<void> _fetchFileSuggestions(String query) async {
    final provider = _provider();
    if (provider == null) return;
    final seq = ++_debounceSeq;
    // Debounce: wait 200ms before hitting the server
    await Future.delayed(const Duration(milliseconds: 200));
    if (seq != _debounceSeq || !_mounted()) return;

    try {
      final files = await provider.client.findFiles(
        query,
        limit: 15,
        directory: provider.directory,
      );
      if (seq != _debounceSeq || !_mounted()) return;

      final suggestions = files.map((path) {
        final isDir = path.endsWith('/');
        return AutocompleteSuggestion(
          icon: isDir ? Icons.folder : Icons.insert_drive_file,
          title: path,
          insertText: '@$path ',
        );
      }).toList();

      _showSuggestions(suggestions);
    } catch (_) {
      dismiss();
    }
  }

  void _showSuggestions(List<AutocompleteSuggestion> suggestions) {
    if (!_mounted()) return;
    _suggestions = suggestions;
    _highlight = suggestions.isNotEmpty ? 0 : -1;
    if (suggestions.isEmpty) {
      dismiss();
      return;
    }
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    } else {
      _overlayEntry = OverlayEntry(
        builder: (_) => Positioned(
          width: 340,
          child: CompositedTransformFollower(
            link: layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, -8),
            followerAnchor: Alignment.bottomLeft,
            targetAnchor: Alignment.topLeft,
            child: AutocompleteOverlay(
              suggestions: _suggestions,
              highlightIndex: _highlight,
              onSelect: _onSuggestionSelected,
            ),
          ),
        ),
      );
      Overlay.of(_context()).insert(_overlayEntry!);
    }
  }

  void _onSuggestionSelected(AutocompleteSuggestion s) {
    final text = textController.text;
    if (_trigger == '/') {
      textController.text = s.insertText;
      textController.selection =
          TextSelection.collapsed(offset: s.insertText.length);
    } else {
      final before = text.substring(0, _triggerOffset);
      final afterCursor = textController.selection.baseOffset < text.length
          ? text.substring(textController.selection.baseOffset)
          : '';
      final newText = '$before${s.insertText}$afterCursor';
      textController.text = newText;
      textController.selection = TextSelection.collapsed(
        offset: before.length + s.insertText.length,
      );
    }
    dismiss();
  }

  void dismiss() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _suggestions = [];
    _highlight = -1;
    _trigger = '';
  }
}
