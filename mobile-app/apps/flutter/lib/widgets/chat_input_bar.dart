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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pendingAttachments.isNotEmpty)
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: pendingAttachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = pendingAttachments[i];
                    final isImage = guessMime(f.path).startsWith('image/');
                    return Chip(
                      avatar: isImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(f, width: 32, height: 32, fit: BoxFit.cover))
                          : const Icon(Icons.insert_drive_file, size: 18),
                      label: Text(
                        f.path.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onDeleted: () => onRemoveAttachment(i),
                    );
                  },
                ),
              ),
            Row(
              children: [
                SizedBox(
                  width: 76,
                  child: VoiceFab(
                    voiceService: voiceService,
                    onSpeechResult: onVoiceResult,
                  ),
                ),
                IconButton(
                  onPressed: onAttach,
                  icon: const Icon(Icons.attach_file),
                  color: theme.colorScheme.onSurfaceVariant,
                  iconSize: 22,
                ),
                Expanded(
                  child: CompositedTransformTarget(
                    link: layerLink,
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onSend,
                  icon: const Icon(Icons.send),
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
