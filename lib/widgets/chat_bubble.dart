import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:ui'; // <-- Import necesario para ImageFilter.blur
import '../constants/app_colors.dart';
import '../models/message.dart';
import '../main.dart'; // Para navigatorKey
import '../utils/download_image.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  final bool isLastUserMessage;
  const ChatBubble({
    required this.message,
    this.isLastUserMessage = false,
    super.key,
  });

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
    // Solo mostrar imagen si hay imagePath y el archivo existe
    if (message.imagePath != null) {
      final file = File(message.imagePath!);
      if (file.existsSync()) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                showDialog(
                  context: navigatorKey.currentContext!,
                  barrierDismissible: true,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                              child: Container(
                                color: Colors.black.withAlpha(
                                  (0.25 * 255).round(),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.center,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.grab,
                                child: InteractiveViewer(
                                  minScale: 0.8,
                                  maxScale: 4.0,
                                  child: SizedBox(
                                    width: constraints.maxWidth * 0.95,
                                    height: constraints.maxHeight * 0.95,
                                    child: Image.file(
                                      file,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 24,
                              right: 24,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.download,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      onPressed: () async {
                                        final (success, error) =
                                            await downloadImage(file.path);
                                        if (context.mounted) {
                                          if (error != null) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(error),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          } else if (success) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Imagen guardada correctamente.',
                                                ),
                                                backgroundColor:
                                                    AppColors.cyberpunkYellow,
                                              ),
                                            );
                                          } else {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Guardado cancelado por el usuario.',
                                                ),
                                                backgroundColor:
                                                    AppColors.cyberpunkYellow,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      tooltip: 'Guardar en galería',
                                    ),
                                  ),
                                  Material(
                                    color: Colors.transparent,
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      tooltip: 'Cerrar',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
              child: Image.file(
                file,
                fit: BoxFit.cover,
                width: 256,
                height: 256,
              ),
            ),
            if (message.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
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
          ],
        );
      }
    }
    // Si no hay imagen válida, solo mostrar el texto
    return Text(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == MessageSender.user;
    final borderColor = isUser ? AppColors.primary : AppColors.secondary;
    final glowColor = isUser ? AppColors.primary : AppColors.secondary;

    Widget statusWidget = const SizedBox.shrink();
    if (isUser) {
      // Mostrar el icono según el estado real del mensaje, sea el último o no
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
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.imagePath != null)
              _buildImageContent(message, glowColor),
            if (message.imagePath == null)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      cleanText(
                        message.text.isNotEmpty ? message.text : '[NO_REPLY]',
                      ),
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
                  Text(
                    _formatTime(message.dateTime),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  if (isUser) ...[const SizedBox(width: 4), statusWidget],
                ],
              ),
            if (message.imagePath != null && message.text.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                  Text(
                    _formatTime(message.dateTime),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  if (isUser) ...[const SizedBox(width: 4), statusWidget],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
