import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';

/// Widget that renders a fenced code block with syntax highlighting,
/// language label, and copy-to-clipboard button.
class CodeBlockWidget extends StatelessWidget {
  final String code;
  final String language;

  const CodeBlockWidget({
    super.key,
    required this.code,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final highlightTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    // O fundo do bloco segue o fundo do tema de syntax para o código não
    // parecer um retângulo de outra paleta dentro do card.
    final codeBackground = highlightTheme['root']?.backgroundColor ??
        theme.colorScheme.surfaceContainerHighest;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: language label + copy button, kept as short as its
          // content — just the chip/icon plus a little breathing room.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Language label
                if (language.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      language,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Copy button
                IconButton(
                  onPressed: () => _copyToClipboard(context),
                  icon: const Icon(Icons.copy, size: 14),
                  color: theme.colorScheme.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  tooltip: 'Copy',
                ),
              ],
            ),
          ),

          // Divider
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),

          // Syntax-highlighted code
          Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: _buildHighlightView(highlightTheme),
            ),
          ),
        ],
      ),
    );
  }

  static const _maxHighlightLength = 5000;

  Widget _buildHighlightView(Map<String, TextStyle> highlightTheme) {
    final trimmed = code.trimRight();

    if (trimmed.length > _maxHighlightLength) {
      return _plainText(trimmed, highlightTheme);
    }

    try {
      final widget = HighlightView(
        trimmed,
        language: language.isNotEmpty ? language : 'plaintext',
        theme: highlightTheme,
        padding: EdgeInsets.zero,
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
        ),
      );

      return widget;
    } catch (_) {
      return _plainText(trimmed, highlightTheme);
    }
  }

  static Widget _plainText(String text, Map<String, TextStyle> highlightTheme) {
    return SelectableText(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 1.5,
        color: highlightTheme['root']?.color ?? const Color(0xffabb2bf),
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied!'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

