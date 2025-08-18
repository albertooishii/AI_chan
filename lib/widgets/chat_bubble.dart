import 'expandable_image_dialog.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'dart:io';
import '../constants/app_colors.dart';
import 'package:ai_chan/core/models/index.dart';
// import 'audio_message_player.dart'; // reemplazado por versión con subtítulos
import 'audio_message_player_with_subs.dart';

class ChatBubble extends StatelessWidget {
  // ===== Helpers de UI reutilizables para reducir duplicación =====
  Widget _footerRow({
    required BuildContext context,
    required Message message,
    required bool isUser,
    required Widget statusWidget,
    bool showRetry = true,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(width: 8),
        Text(_formatTime(message.dateTime), style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        if (isUser) ...[
          const SizedBox(width: 4),
          statusWidget,
          if (showRetry && message.status == MessageStatus.failed) ...[
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
      ],
    );
  }

  List<Widget> _buildMarkdownBlocks(String text) {
    if (text.trim().isEmpty) return const [];
    return MarkdownGenerator().buildWidgets(cleanText(text));
  }

  Widget _callHeader({
    required bool isUser,
    required bool isSummary,
    required bool isPlaceholder,
    CallStatus? callStatus,
  }) {
    String title;
    IconData icon;
    Color color = isUser ? AppColors.primary : AppColors.secondary;
    switch (callStatus) {
      case CallStatus.placeholder:
        title = isUser ? 'Llamando…' : 'Llamada entrante';
        icon = isUser ? Icons.call_made : Icons.call_received;
        break;
      case CallStatus.completed:
        title = isUser ? 'Llamada realizada' : 'Llamada recibida';
        icon = isUser ? Icons.call_made : Icons.call_received;
        break;
      case CallStatus.rejected:
        title = 'Llamada rechazada';
        icon = Icons.call_end;
        color = Colors.redAccent;
        break;
      case CallStatus.missed:
        title = 'Llamada no contestada';
        icon = Icons.call_missed;
        color = Colors.orangeAccent;
        break;
      case CallStatus.canceled:
        title = 'Llamada cancelada';
        icon = Icons.call_end;
        color = Colors.deepOrangeAccent;
        break;
      case null:
        if (isPlaceholder) {
          title = isUser ? 'Llamando…' : 'Llamada recibida';
          icon = isUser ? Icons.call_made : Icons.call_received;
        } else {
          title = isUser ? 'Llamada realizada' : 'Llamada recibida';
          icon = isUser ? Icons.call_made : Icons.call_received;
        }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ],
    );
  }

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
    // Detectar tag de audio en formato [audio]...[/audio] con contenido no vacío
    final openTag = '[audio]';
    final closeTag = '[/audio]';
    int openIdx = txtLower.indexOf(openTag);
    int closeIdx = openIdx >= 0 ? txtLower.indexOf(closeTag, openIdx + openTag.length) : -1;
    // Solo consideramos placeholder de nota de voz pendiente para mensajes del asistente.
    // Si el usuario escribe manualmente [audio]...[/audio] se mostrará como texto normal (NO barra de carga).
    bool isVoiceNoteTag = false;
    if (message.sender == MessageSender.assistant && openIdx >= 0 && closeIdx > openIdx) {
      final inner = message.text.substring(openIdx + openTag.length, closeIdx).trim();
      if (inner.isNotEmpty) isVoiceNoteTag = true;
    }

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
    final bool isCallPlaceholder =
        message.callStatus == CallStatus.placeholder || message.text.trim() == '[call][/call]';
    final callStatus = message.callStatus;

    Widget bubbleContent;
    bool useIntrinsicWidth = false;
    EdgeInsetsGeometry padding = const EdgeInsets.all(14);
    if (hasImage && hasAudio) {
      // Caso combinado: imagen + nota de voz
      final showCaption = message.text.trim().isNotEmpty && !isVoiceNoteTag; // ignorar isAudio para caption
      final isShortCaption = !showCaption || (showCaption && message.text.length < 80);
      useIntrinsicWidth = isShortCaption;
      padding = isShortCaption ? const EdgeInsets.all(6) : const EdgeInsets.all(14);
      bubbleContent = Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImageContent(message, glowColor),
          const SizedBox(height: 8),
          Stack(
            children: [
              AudioMessagePlayerWithSubs(message: message, width: 200),
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
          if (showCaption) ...[const SizedBox(height: 8), ...MarkdownGenerator().buildWidgets(cleanText(message.text))],
          _footerRow(context: context, message: message, isUser: isUser, statusWidget: statusWidget),
        ],
      );
    } else if (hasImage) {
      final isShortText = !shouldShowText || (shouldShowText && message.text.length < 80);
      useIntrinsicWidth = isShortText;
      padding = isShortText ? const EdgeInsets.all(6) : const EdgeInsets.all(14);
      bubbleContent = Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildImageContent(message, glowColor),
          if (shouldShowText) ...[const SizedBox(height: 8), ..._buildMarkdownBlocks(message.text)],
          _footerRow(context: context, message: message, isUser: isUser, statusWidget: statusWidget),
        ],
      );
    } else if (hasAudio) {
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              // Usar reproductor con subtítulos flotantes reutilizando efecto cyberpunk
              AudioMessagePlayerWithSubs(message: message, width: 180),
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
          _footerRow(context: context, message: message, isUser: isUser, statusWidget: statusWidget),
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
          _footerRow(context: context, message: message, isUser: isUser, statusWidget: statusWidget),
        ],
      );
    } else if (isVoiceCallSummary) {
      // Mensaje de resumen de llamada de voz
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _callHeader(isUser: isUser, isSummary: true, isPlaceholder: false, callStatus: callStatus),
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
                children: [..._buildMarkdownBlocks(message.text)],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _footerRow(context: context, message: message, isUser: isUser, statusWidget: statusWidget),
        ],
      );
    } else if (isCallPlaceholder ||
        callStatus == CallStatus.rejected ||
        callStatus == CallStatus.missed ||
        callStatus == CallStatus.canceled) {
      // Placeholder o estados de llamada sin resumen
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _callHeader(
            isUser: isUser,
            isSummary: false,
            isPlaceholder: isCallPlaceholder,
            callStatus: callStatus ?? (isCallPlaceholder ? CallStatus.placeholder : null),
          ),
          const SizedBox(height: 6),
          _footerRow(context: context, message: message, isUser: isUser, statusWidget: statusWidget, showRetry: false),
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
              children: [..._buildMarkdownBlocks(message.text.isNotEmpty ? message.text : '')],
            ),
          ),
          _footerRow(context: context, message: message, isUser: isUser, statusWidget: statusWidget),
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
