import 'package:flutter/material.dart';

import '../models/chat_event.dart';
import '../l10n/app_localizations.dart';

/// Card que exibe uma pergunta (question) do agente PAI.
///
/// Suporta múltiplas questões com opções de:
/// - Múltipla escolha (CheckboxListTile)
/// - Única escolha (RadioListTile)
/// - Resposta customizada (TextField)
class QuestionCard extends StatefulWidget {
  final QuestionRequest request;
  final ValueChanged<List<List<String>>> onReply;
  final VoidCallback onReject;

  const QuestionCard({
    super.key,
    required this.request,
    required this.onReply,
    required this.onReject,
  });

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  /// Respostas selecionadas por questão.
  ///
  /// Cada índice externo corresponde a uma [QuestionInfo].
  /// Cada índice interno contém as labels selecionadas.
  late final List<List<String>> _selectedAnswers;

  /// Controllers para campos customizados (uma por questão).
  late final List<TextEditingController> _customControllers;

  @override
  void initState() {
    super.initState();
    _selectedAnswers = List.generate(
      widget.request.questions.length,
      (_) => <String>[],
    );
    _customControllers = List.generate(
      widget.request.questions.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final controller in _customControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    // Pode submeter se todas as questões tiverem ao menos uma resposta
    // OU se a questão não tiver opções (só custom)
    for (var i = 0; i < widget.request.questions.length; i++) {
      final q = widget.request.questions[i];
      final hasSelection = _selectedAnswers[i].isNotEmpty;
      final hasCustom = q.custom && _customControllers[i].text.trim().isNotEmpty;
      final hasOptions = q.options.isNotEmpty;

      if (hasOptions && !hasSelection && !hasCustom) {
        return false;
      }
      if (!hasOptions && q.custom && !hasCustom) {
        return false;
      }
    }
    return true;
  }

  void _onSubmit() {
    final answers = <List<String>>[];
    for (var i = 0; i < widget.request.questions.length; i++) {
      final q = widget.request.questions[i];
      final selected = List<String>.from(_selectedAnswers[i]);

      // Adiciona resposta customizada se existir
      if (q.custom) {
        final customText = _customControllers[i].text.trim();
        if (customText.isNotEmpty) {
          selected.add(customText);
        }
      }

      answers.add(selected);
    }
    widget.onReply(answers);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: help icon + "Question"
            Row(
              children: [
                Icon(Icons.help_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.question,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Questões
            ...widget.request.questions.asMap().entries.expand((entry) {
              final index = entry.key;
              final q = entry.value;
              return _buildQuestion(index, q, theme);
            }),

            const SizedBox(height: 16),

            // Bottom buttons: Cancel e Answer
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onReject,
                    child: Text(AppLocalizations.of(context)!.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _onSubmit : null,
                    child: Text(AppLocalizations.of(context)!.answer),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildQuestion(int index, QuestionInfo q, ThemeData theme) {
    final widgets = <Widget>[
      if (q.header.isNotEmpty)
        Text(
          q.header,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      if (q.header.isNotEmpty) const SizedBox(height: 4),
      Text(
        q.question,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
    ];

    if (q.multiple) {
      // Múltipla escolha: CheckboxListTile
      widgets.addAll(
        q.options.map((option) {
          final isSelected = _selectedAnswers[index].contains(option.label);
          return CheckboxListTile(
            value: isSelected,
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _selectedAnswers[index].add(option.label);
                } else {
                  _selectedAnswers[index].remove(option.label);
                }
              });
            },
            title: Text(option.label),
            subtitle: option.description.isNotEmpty
                ? Text(
                    option.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : null,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: EdgeInsets.zero,
          );
        }),
      );
    } else {
      // Única escolha: RadioListTile dentro de RadioGroup
      final groupValue = _selectedAnswers[index].isNotEmpty
          ? _selectedAnswers[index].first
          : null;
      widgets.add(
        RadioGroup<String>(
          groupValue: groupValue,
          onChanged: (value) {
            setState(() {
              if (value != null) {
                _selectedAnswers[index] = [value];
              }
            });
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: q.options.map((option) {
              return RadioListTile<String>(
                value: option.label,
                title: Text(option.label),
                subtitle: option.description.isNotEmpty
                    ? Text(
                        option.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
              );
            }).toList(),
          ),
        ),
      );
    }

    // Campo customizado
    if (q.custom) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        TextField(
          controller: _customControllers[index],
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.customAnswerHint,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );
    }

    // Separador entre questões (exceto na última)
    if (index < widget.request.questions.length - 1) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(const Divider());
      widgets.add(const SizedBox(height: 8));
    }

    return widgets;
  }
}
