import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // <-- Import necesario para ImageFilter.blur
import '../constants/app_colors.dart';
import '../models/message.dart';
import '../main.dart'; // Para navigatorKey
import '../utils/download_image.dart';

class ChatBubble extends StatelessWidget {
  final Message message;
  const ChatBubble({required this.message, super.key});

  String cleanText(String text) {
    String cleaned = text.replaceAll(r'\n', '\n').replaceAll(r'\"', '"');
    cleaned = cleaned.replaceAll(RegExp(r'\\(?!n|\")'), '');
    cleaned = cleaned.replaceAll(r'\\', '');
    return cleaned;
  }

  Widget _buildImageContent(Message message, Color glowColor) {
    // Si hay imagePath y el archivo existe, mostrarlo. Si no, usar base64 si está disponible.
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
                                        // Guardar en Descargas solo en Android
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
    // Si no hay archivo, usar base64 si está disponible
    if (message.imageBase64 != null) {
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
                                  child: Image.memory(
                                    base64Decode(message.imageBase64!),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 24,
                            right: 24,
                            child: Material(
                              color: Colors.transparent,
                              child: IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                onPressed: () => Navigator.of(context).pop(),
                                tooltip: 'Cerrar',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
            child: Image.memory(
              base64Decode(message.imageBase64!),
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
        child: _buildImageContent(message, glowColor),
      ),
    );
  }
}
