import '../main.dart';
import 'package:flutter/material.dart';
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
    if (message.imagePath != null) {
      final file = File(message.imagePath!);
      if (file.existsSync()) {
        final isUser = message.sender == MessageSender.user;
        return Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                showDialog(
                  context: navigatorKey.currentContext!,
                  builder: (context) {
                    return Dialog(
                      backgroundColor: Colors.transparent,
                      child: InteractiveViewer(
                        child: ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(file)),
                      ),
                    );
                  },
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(file, fit: BoxFit.cover, width: 256, height: 256),
              ),
            ),
          ],
        );
      }
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

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
        child: IntrinsicWidth(
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
              crossAxisAlignment: message.imagePath != null
                  ? (isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start)
                  : CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.imagePath != null) ...[
                  _buildImageContent(message, glowColor),
                  if (message.text.isNotEmpty) const SizedBox(height: 8),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (message.imagePath == null)
                      Flexible(
                        child: Text(
                          cleanText(message.text.isNotEmpty ? message.text : '[NO_REPLY]'),
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'FiraMono',
                            fontSize: 16,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: glowColor.withAlpha((0.5 * 255).round()),
                                blurRadius: 2,
                                offset: const Offset(0.5, 0.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (message.text.isNotEmpty)
                      Flexible(
                        child: Text(
                          cleanText(message.text),
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'FiraMono',
                            fontSize: 16,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: glowColor.withAlpha((0.5 * 255).round()),
                                blurRadius: 2,
                                offset: const Offset(0.5, 0.5),
                              ),
                            ],
                          ),
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
      ),
    );
  }
}
