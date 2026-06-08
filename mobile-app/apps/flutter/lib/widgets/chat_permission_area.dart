import 'package:flutter/material.dart';

import '../models/chat_event.dart';
import 'permission_card.dart';
import 'question_card.dart';

/// Area that displays pending permission requests and questions.
class ChatPermissionArea extends StatelessWidget {
  final List<PermissionRequest> pendingPermissions;
  final List<QuestionRequest> pendingQuestions;
  final void Function(String id, PermissionReply reply) onPermissionReply;
  final void Function(String id, List<List<String>> answers) onQuestionReply;
  final void Function(String id) onQuestionReject;

  const ChatPermissionArea({
    super.key,
    required this.pendingPermissions,
    required this.pendingQuestions,
    required this.onPermissionReply,
    required this.onQuestionReply,
    required this.onQuestionReject,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingPermissions.isEmpty && pendingQuestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...pendingPermissions.map((req) => PermissionCard(
              request: req,
              onReply: (reply) => onPermissionReply(req.id, reply),
            )),
            ...pendingQuestions.map((req) => QuestionCard(
              request: req,
              onReply: (answers) => onQuestionReply(req.id, answers),
              onReject: () => onQuestionReject(req.id),
            )),
          ],
        ),
      ),
    );
  }
}
