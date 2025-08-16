import 'expandable_image_dialog.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'dart:io';
import '../constants/app_colors.dart';
import '../models/message.dart';
import 'audio_message_player.dart';

class ChatBubble extends StatelessWidget {
  Widget _buildBubbleContent({
    required Widget child,
    required bool useIntrinsicWidth,
    required bool isUser,
    required Color borderColor,
    required Color glowColor,
    EdgeInsetsGeometry? padding,
  }) {
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      padding: padding ?? const EdgeInsets.all(14),
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
      child: child,
    );
    if (useIntrinsicWidth) {
      return IntrinsicWidth(child: bubble);
    } else {
      return bubble;
    }
  }

  final Message message;
  final bool isLastUserMessage;
  final Directory? imageDir;
  const ChatBubble({required this.message, this.isLastUserMessage = false, this.imageDir, super.key});

  String cleanText(String text) {
    String cleaned = text.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
    cleaned = cleaned.replaceAll(RegExp(r'\\(?!n|\")'), '');
    cleaned = cleaned.replaceAll(r'\\', '');

    // Remover contenido entre [call] y [/call] si existe
    if (cleaned.contains('[call]') && cleaned.contains('[/call]')) {
      cleaned = cleaned.replaceAll(RegExp(r'\[call\].*?\[\/call\]', dotAll: true), '');
    }

    return cleaned;
  }

  String _formatTime(DateTime dateTime) {
    return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildImageContent(Message message, Color glowColor) {
    final imageUrl = message.image?.url;
    if (imageUrl != null && imageUrl.isNotEmpty && imageDir != null) {
      final fileName = imageUrl.split('/').last;
      final absPath = '${imageDir!.path}/$fileName';
      final file = File(absPath);
      if (file.existsSync()) {
        return Center(
          child: Builder(
            builder: (context) {
              return GestureDetector(
                onTap: () {
                  final chatProvider = context.read<ChatProvider>();
                  final images = chatProvider.messages
                      .where((m) => m.isImage && m.image != null && m.image!.url != null && m.image!.url!.isNotEmpty)
                      .toList();
                  final idx = images.indexWhere((m) => m.image?.url == imageUrl);
                  if (idx != -1) {
                    ExpandableImageDialog.show(context, images, idx, imageDir: imageDir);
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(file, fit: BoxFit.cover, width: 256, height: 256),
                ),
              );
            },
          ),
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
    final txtLower = message.text.trimLeft().toLowerCase();
    // Detectar tag de audio en formato [audio]...[/audio] o apertura sola
    final openTag = '[audio]';
    final closeTag = '[/audio]';
    // Sólo marcar como nota de voz si contiene apertura Y cierre exactos
    final isVoiceNoteTag = txtLower.contains(openTag) && txtLower.contains(closeTag);

    Widget statusWidget = const SizedBox.shrink();
    if (isUser) {
      IconData icon;
      Color color;
      switch (message.status) {
        case MessageStatus.sending:
          icon = Icons.access_time; // esperando envío / sin red todavía
          color = Colors.grey;
          break;
        case MessageStatus.sent:
          icon = Icons.check; // enviado a la API
          color = Colors.grey;
          break;
        case MessageStatus.read:
          icon = Icons.done_all; // IA ya respondió
          color = AppColors.cyberpunkYellow;
          break;
        case MessageStatus.failed:
          icon = Icons.error_outline; // fallo de red/envío
          color = Colors.redAccent;
          break;
      }
      statusWidget = Icon(icon, size: 16, color: color);
    }

    // Ocultar texto si es audio o si está marcado como nota de voz (etiqueta previa a generación de TTS)
    final shouldShowText = !message.isAudio && message.text.trim().isNotEmpty && !isVoiceNoteTag;
    final hasImage = message.image != null && message.image!.url != null && message.image!.url!.isNotEmpty;
    final hasAudio = message.isAudio && (message.audioPath != null && message.audioPath!.isNotEmpty);
    final isVoiceCallSummary = message.isVoiceCallSummary;

    Widget bubbleContent;
    bool useIntrinsicWidth = false;
    EdgeInsetsGeometry padding = const EdgeInsets.all(14);
    if (hasImage) {
      final isShortText = !shouldShowText || (shouldShowText && message.text.length < 80);
      useIntrinsicWidth = isShortText;
      padding = isShortText ? const EdgeInsets.all(6) : const EdgeInsets.all(14);
      bubbleContent = Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImageContent(message, glowColor),
          if (shouldShowText) ...[
            const SizedBox(height: 8),
            ...MarkdownGenerator().buildWidgets(cleanText(message.text)),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 8),
              Text(_formatTime(message.dateTime), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              if (isUser) ...[const SizedBox(width: 4), statusWidget],
              if (isUser && message.status == MessageStatus.failed) ...[
                const SizedBox(width: 6),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                  tooltip: 'Reintentar',
                  onPressed: () {
                    try {
                      context.read<ChatProvider>().retryLastFailedMessage(onError: (e) {});
                    } catch (_) {}
                  },
                ),
              ],
            ],
          ),
        ],
      );
    } else if (hasAudio) {
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              AudioMessagePlayer(message: message, width: 180),
              if (isUser && message.status == MessageStatus.sending)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(
                              (isUser ? AppColors.primary : AppColors.secondary).withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (shouldShowText) ...[
            const SizedBox(height: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [...MarkdownGenerator().buildWidgets(cleanText(message.text))],
              ),
            ),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 8),
              Text(_formatTime(message.dateTime), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              if (isUser) ...[const SizedBox(width: 4), statusWidget],
              if (isUser && message.status == MessageStatus.failed) ...[
                const SizedBox(width: 6),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                  tooltip: 'Reintentar',
                  onPressed: () {
                    try {
                      context.read<ChatProvider>().retryLastFailedMessage(onError: (e) {});
                    } catch (_) {}
                  },
                ),
              ],
            ],
          ),
        ],
      );
    } else if (isVoiceNoteTag) {
      // Placeholder mientras se genera/adjunta el audio de una nota de voz de la IA
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 180,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: glowColor, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: glowColor, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 12,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.grey[850],
                      valueColor: AlwaysStoppedAnimation(glowColor.withValues(alpha: 0.55)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 8),
              Text(_formatTime(message.dateTime), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              if (isUser) ...[const SizedBox(width: 4), statusWidget],
              if (isUser && message.status == MessageStatus.failed) ...[
                const SizedBox(width: 6),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                  tooltip: 'Reintentar',
                  onPressed: () {
                    try {
                      context.read<ChatProvider>().retryLastFailedMessage(onError: (e) {});
                    } catch (_) {}
                  },
                ),
              ],
            ],
          ),
        ],
      );
    } else if (isVoiceCallSummary) {
      // Mensaje de resumen de llamada de voz
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado de llamada
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_made, color: isUser ? AppColors.primary : AppColors.secondary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Llamada realizada',
                style: TextStyle(
                  color: isUser ? AppColors.primary : AppColors.secondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Duración
          if (message.callDuration != null)
            Text('Duración: ${message.formattedCallDuration}', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          const SizedBox(height: 8),
          // Contenido del resumen
          if (shouldShowText && message.text.isNotEmpty) ...[
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [...MarkdownGenerator().buildWidgets(cleanText(message.text))],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Tiempo
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 8),
              Text(_formatTime(message.dateTime), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              if (isUser) ...[const SizedBox(width: 4), statusWidget],
              if (isUser && message.status == MessageStatus.failed) ...[
                const SizedBox(width: 6),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                  tooltip: 'Reintentar',
                  onPressed: () {
                    try {
                      context.read<ChatProvider>().retryLastFailedMessage(onError: (e) {});
                    } catch (_) {}
                  },
                ),
              ],
            ],
          ),
        ],
      );
    } else {
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [...MarkdownGenerator().buildWidgets(cleanText(message.text.isNotEmpty ? message.text : ''))],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 8),
              Text(_formatTime(message.dateTime), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              if (isUser) ...[const SizedBox(width: 4), statusWidget],
              if (isUser && message.status == MessageStatus.failed) ...[
                const SizedBox(width: 6),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
                  tooltip: 'Reintentar',
                  onPressed: () {
                    try {
                      context.read<ChatProvider>().retryLastFailedMessage(onError: (e) {});
                    } catch (_) {}
                  },
                ),
              ],
            ],
          ),
        ],
      );
    }
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: _buildBubbleContent(
        child: bubbleContent,
        useIntrinsicWidth: useIntrinsicWidth,
        isUser: isUser,
        borderColor: borderColor,
        glowColor: glowColor,
        padding: padding,
      ),
    );
  }
}
