import 'dart:io';

import 'package:flutter/material.dart';

import '../services/voice_service.dart';
import 'voice_fab.dart';

class ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final LayerLink layerLink;
  final VoiceService voiceService;
  final List<File> pendingAttachments;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final ValueChanged<String> onVoiceResult;
  final ValueChanged<int> onRemoveAttachment;
  final String Function(String path) guessMime;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.layerLink,
    required this.voiceService,
    required this.pendingAttachments,
    required this.onSend,
    required this.onAttach,
    required this.onVoiceResult,
    required this.onRemoveAttachment,
    required this.guessMime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pendingAttachments.isNotEmpty)
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: pendingAttachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = pendingAttachments[i];
                    final isImage = guessMime(f.path).startsWith('image/');
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isImage)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(f, width: 32, height: 32, fit: BoxFit.cover),
                            )
                          else
                            const Icon(Icons.insert_drive_file, size: 18),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 100),
                            child: Text(
                              f.path.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => onRemoveAttachment(i),
                            child: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            CompositedTransformTarget(
              link: layerLink,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: IconButton(
                        onPressed: onAttach,
                        icon: const Icon(Icons.add),
                        iconSize: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Peça ao PAI...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                        ),
                        style: theme.textTheme.bodyMedium,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 4),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, child) {
                          final hasText = value.text.trim().isNotEmpty;
                          return hasText
                              ? IconButton(
                                  onPressed: onSend,
                                  icon: const Icon(Icons.arrow_upward),
                                  iconSize: 20,
                                  style: IconButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: theme.colorScheme.onPrimary,
                                    minimumSize: const Size(36, 36),
                                    padding: EdgeInsets.zero,
                                  ),
                                )
                              : SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: VoiceFab(
                                    voiceService: voiceService,
                                    onSpeechResult: onVoiceResult,
                                    compact: true,
                                  ),
                                );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
