import 'package:ai_chan/utils/image_utils.dart';

import 'expandable_image_dialog.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'dart:io';
import '../constants/app_colors.dart';
import '../models/message.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final bool isLastUserMessage;
  const ChatBubble({required this.message, this.isLastUserMessage = false, super.key});

  String cleanText(String text) {
    String cleaned = text.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
    cleaned = cleaned.replaceAll(RegExp(r'\\(?!n|\")'), '');
    cleaned = cleaned.replaceAll(r'\\', '');
    return cleaned;
  }

  String _formatTime(DateTime dateTime) {
    return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildImageContent(Message message, Color glowColor) {
    final imageUrl = message.image?.url;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final fileName = imageUrl.split('/').last;
      return FutureBuilder<Directory>(
        future: getLocalImageDir(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
            final absPath = '${snapshot.data!.path}/$fileName';
            final file = File(absPath);
            if (file.existsSync()) {
              final isUser = message.sender == MessageSender.user;
              return Row(
                mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      return GestureDetector(
                        onTap: () {
                          final chatProvider = context.read<ChatProvider>();
                          final images = chatProvider.messages
                              .where(
                                (m) => m.isImage && m.image != null && m.image!.url != null && m.image!.url!.isNotEmpty,
                              )
                              .toList();
                          final idx = images.indexWhere((m) => m.image?.url == imageUrl);
                          if (idx != -1) {
                            ExpandableImageDialog.show(context, images, idx);
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(file, fit: BoxFit.cover, width: 256, height: 256),
                        ),
                      );
                    },
                  ),
                ],
              );
            }
          }
          return const SizedBox.shrink();
        },
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == MessageSender.user;
    final borderColor = isUser ? AppColors.primary : AppColors.secondary;
    final glowColor = isUser ? AppColors.primary : AppColors.secondary;

    Widget statusWidget = const SizedBox.shrink();
    if (isUser) {
      IconData icon;
      Color color;
      switch (message.status) {
        case MessageStatus.sending:
          icon = Icons.access_time;
          color = Colors.grey;
          break;
        case MessageStatus.sent:
          icon = Icons.check;
          color = Colors.grey;
          break;
        case MessageStatus.delivered:
          icon = Icons.done_all;
          color = Colors.grey;
          break;
        case MessageStatus.read:
          icon = Icons.done_all;
          color = AppColors.cyberpunkYellow;
          break;
      }
      statusWidget = Icon(icon, size: 16, color: color);
    }

    final shouldShowText = message.text.isNotEmpty && message.text.trim() != '[NO_REPLY]';
    final hasImage = message.image != null && message.image!.url != null && message.image!.url!.isNotEmpty;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: glowColor.withAlpha((0.4 * 255).round()),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: hasImage
                ? (isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start)
                : CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImage) ...[_buildImageContent(message, glowColor), if (shouldShowText) const SizedBox(height: 8)],
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!hasImage)
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: MarkdownGenerator().buildWidgets(
                          cleanText(message.text.isNotEmpty ? message.text : '[NO_REPLY]'),
                        ),
                      ),
                    )
                  else if (shouldShowText)
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: MarkdownGenerator().buildWidgets(cleanText(message.text)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Text(_formatTime(message.dateTime), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  if (isUser) ...[const SizedBox(width: 4), statusWidget],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
