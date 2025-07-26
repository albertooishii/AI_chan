import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'dart:io';
import 'dart:convert';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../constants/app_colors.dart';
import '../providers/chat_provider.dart';

class MessageInput extends StatefulWidget {
  final void Function(String text)? onSend;
  const MessageInput({super.key, this.onSend});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  File? _attachedImage;
  String? _attachedImageBase64;
  String? _attachedImageMime;
  final TextEditingController _controller = TextEditingController();
  bool _showEmojiPicker = false;
  final FocusNode _textFieldFocusNode = FocusNode();
  @override
  void initState() {
    super.initState();
    _textFieldFocusNode.addListener(() {
      if (_textFieldFocusNode.hasFocus && _showEmojiPicker) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final isMobile =
        kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      final picker = ImagePicker();
      final context = this.context;
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar foto'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                  if (pickedFile != null) {
                    final file = File(pickedFile.path);
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
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de la galería'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                  if (pickedFile != null) {
                    final file = File(pickedFile.path);
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
                },
              ),
            ],
          ),
        ),
      );
    } else {
      // Desktop: solo galería
      showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de la galería'),
                onTap: () async {
                  Navigator.of(ctx).pop();
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
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _attachedImage = null;
      _attachedImageBase64 = null;
      _attachedImageMime = null;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final hasImage = _attachedImageBase64 != null && _attachedImageBase64!.isNotEmpty;
    if (text.isEmpty && !hasImage) return;

    final chatProvider = context.read<ChatProvider>();
    String? imagePath;
    String? imageBase64ToSend = _attachedImageBase64;
    String? imageMimeTypeToSend = _attachedImageMime;
    if (hasImage) {
      final bytes = base64Decode(_attachedImageBase64!);
      final dir = await chatProvider.getLocalImageDir();
      final ext = _attachedImageMime == 'image/jpeg'
          ? 'jpg'
          : _attachedImageMime == 'image/webp'
          ? 'webp'
          : 'png';
      final fileName = 'img_user_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = '${dir.path}/$fileName';
      final file = await File(filePath).writeAsBytes(bytes);
      imagePath = file.path;
    }
    if (mounted) {
      setState(() {
        _controller.clear();
        _attachedImage = null;
        _attachedImageBase64 = null;
        _attachedImageMime = null;
      });
    }
    await chatProvider.sendMessage(
      text,
      imageMimeType: imageMimeTypeToSend,
      imagePath: imagePath,
      imageBase64: imageBase64ToSend,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
                        child: Image.file(_attachedImage!, width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Imagen adjunta',
                          style: TextStyle(color: AppColors.secondary, fontSize: 14),
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
                  Expanded(
                    child: TextField(
                      focusNode: _textFieldFocusNode,
                      controller: _controller,
                      style: const TextStyle(color: AppColors.primary, fontFamily: 'FiraMono'),
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
                          borderSide: BorderSide(color: AppColors.primary, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.black,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        prefixIcon: IconButton(
                          icon: _showEmojiPicker
                              ? const Icon(Icons.close, color: AppColors.secondary)
                              : const Icon(Icons.emoji_emotions_outlined, color: AppColors.secondary),
                          onPressed: () {
                            if (_showEmojiPicker) {
                              // Cerrar emojis: volver a enfocar el TextField y mostrar teclado
                              FocusScope.of(context).requestFocus(_textFieldFocusNode);
                            } else {
                              // Abrir emojis: ocultar teclado
                              FocusScope.of(context).unfocus();
                            }
                            setState(() {
                              _showEmojiPicker = !_showEmojiPicker;
                            });
                          },
                          tooltip: _showEmojiPicker ? 'Cerrar emojis' : 'Emojis',
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_showEmojiPicker)
                              IconButton(
                                icon: const Icon(Icons.backspace_outlined, color: AppColors.secondary),
                                onPressed: () {
                                  final text = _controller.text;
                                  if (text.isNotEmpty) {
                                    final chars = text.characters;
                                    _controller.text = chars.skipLast(1).toString();
                                    _controller.selection = TextSelection.fromPosition(
                                      TextPosition(offset: _controller.text.length),
                                    );
                                  }
                                },
                                tooltip: 'Borrar último carácter',
                              ),
                            IconButton(
                              icon: const Icon(Icons.camera_alt, color: AppColors.secondary),
                              onPressed: _pickImage,
                              tooltip: 'Foto o galería',
                            ),
                          ],
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
        ),
        if (_showEmojiPicker)
          SizedBox(
            height: 280,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                _controller.text += emoji.emoji;
                _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
              },
              config: Config(
                height: 280,
                checkPlatformCompatibility: true,
                viewOrderConfig: ViewOrderConfig(top: EmojiPickerItem.categoryBar, middle: EmojiPickerItem.emojiView),
                emojiViewConfig: EmojiViewConfig(
                  emojiSizeMax: 28,
                  backgroundColor: Colors.black, // negro app
                  gridPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  recentsLimit: 24,
                ),
                categoryViewConfig: CategoryViewConfig(
                  indicatorColor: AppColors.secondary, // magenta
                  iconColor: AppColors.secondary, // magenta
                  iconColorSelected: Colors.white,
                  backspaceColor: AppColors.secondary,
                  backgroundColor: Colors.black, // negro barra
                ),
                skinToneConfig: SkinToneConfig(
                  dialogBackgroundColor: Colors.black,
                  indicatorColor: AppColors.secondary,
                  enabled: true,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
