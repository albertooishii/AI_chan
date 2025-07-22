import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../constants/app_colors.dart';
import '../providers/chat_provider.dart';

class MessageInput extends StatefulWidget {
  final void Function(String text)? onSend;
  final void Function(File imageFile)? onSendImage;
  const MessageInput({super.key, this.onSend, this.onSendImage});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  File? _attachedImage;
  String? _attachedImageBase64;
  String? _attachedImageMime;
  final TextEditingController _controller = TextEditingController();

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final base64img = base64Encode(bytes);
      final ext = file.path.split('.').last.toLowerCase();
      String mime = 'image/png';
      if (ext == 'jpg' || ext == 'jpeg') mime = 'image/jpeg';
      if (ext == 'webp') mime = 'image/webp';
      setState(() {
        _attachedImage = file;
        _attachedImageBase64 = base64img;
        _attachedImageMime = mime;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _attachedImage = null;
      _attachedImageBase64 = null;
      _attachedImageMime = null;
    });
  }

  void _send() {
    final text = _controller.text.trim();
    final hasImage =
        _attachedImageBase64 != null && _attachedImageBase64!.isNotEmpty;
    if (text.isEmpty && !hasImage) return;

    // Si el padre define onSendImage, usarlo (para compatibilidad)
    if (hasImage && widget.onSendImage != null && (text.isEmpty)) {
      widget.onSendImage!(_attachedImage!);
      _removeImage();
      _controller.clear();
      return;
    }

    // Si hay imagen, enviar ambos (texto + imagen) usando el provider
    if (hasImage) {
      context.read<ChatProvider>().sendMessageWithImage(
        text: text,
        imageBase64: _attachedImageBase64!,
        imageMimeType: _attachedImageMime,
        imagePath: _attachedImage?.path,
      );
      _removeImage();
      _controller.clear();
      return;
    }

    // Solo texto
    if (text.isNotEmpty) {
      if (widget.onSend != null) {
        widget.onSend!(text);
      } else {
        context.read<ChatProvider>().sendMessage(text);
      }
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attachedImage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _attachedImage!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Imagen adjunta',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    onPressed: _removeImage,
                    tooltip: 'Quitar imagen',
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file, color: AppColors.secondary),
                onPressed: _pickImage,
                tooltip: 'Adjuntar imagen',
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontFamily: 'FiraMono',
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Escribe tu mensaje...'
                        '${_attachedImage != null ? ' (opcional)' : ''}',
                    hintStyle: const TextStyle(color: AppColors.secondary),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.secondary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.black,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: AppColors.primary),
                onPressed: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
