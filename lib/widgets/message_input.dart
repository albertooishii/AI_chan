import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'dart:io';
import 'dart:convert';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../constants/app_colors.dart';
import '../providers/chat_provider.dart';
import '../models/image.dart' as ai_image;
import '../utils/image_utils.dart';

// Intents para atajos de teclado en escritorio
class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

class InsertNewlineIntent extends Intent {
  const InsertNewlineIntent();
}

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

  bool _isMobile(BuildContext context) {
    // Nativo: Android/iOS -> móvil
    // Web: si la ventana es "pequeña" (lado corto < 600), tratamos como móvil
    final isNativeMobile =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (isNativeMobile) return true;
    if (kIsWeb) {
      final shortest = MediaQuery.of(context).size.shortestSide;
      return shortest < 600;
    }
    return false;
  }

  Future<void> _pickImage() async {
    final isMobile = _isMobile(context);
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
    ai_image.Image? imageToSend;
    String? imageMimeType = _attachedImageMime;
    if (hasImage) {
      // Guardar la imagen en local y obtener el nombre real
      final savedPath = await saveBase64ImageToFile(_attachedImageBase64!, prefix: 'img_user');
      if (savedPath != null) {
        final fileName = savedPath.split('/').last;
        imageToSend = ai_image.Image(url: fileName, base64: _attachedImageBase64!);
      } else {
        // Si falla, usar el nombre generado como antes
        final ext = imageMimeType == 'image/jpeg'
            ? 'jpg'
            : imageMimeType == 'image/webp'
            ? 'webp'
            : 'png';
        final fileName = 'img_user_${DateTime.now().millisecondsSinceEpoch}.$ext';
        imageToSend = ai_image.Image(url: fileName, base64: _attachedImageBase64!);
      }
    }
    if (mounted) {
      setState(() {
        _controller.clear();
        _attachedImage = null;
        _attachedImageBase64 = null;
        _attachedImageMime = null;
      });
    }
    await chatProvider.sendMessage(text, image: imageToSend, imageMimeType: imageMimeType);
  }

  @override
  Widget build(BuildContext context) {
    // Desktop: Linux/Windows/macOS; Mobile: Android/iOS y Web "pequeño" (lado corto < 600)
    final bool isMobile = _isMobile(context);
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        Widget field = TextField(
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
                                  FocusScope.of(context).requestFocus(_textFieldFocusNode);
                                } else {
                                  FocusScope.of(context).unfocus();
                                }
                                setState(() {
                                  _showEmojiPicker = !_showEmojiPicker;
                                });
                              },
                              tooltip: _showEmojiPicker ? 'Cerrar emojis' : 'Emojis',
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.camera_alt, color: AppColors.secondary),
                              onPressed: _pickImage,
                              tooltip: 'Foto o galería',
                            ),
                          ),
                          // En móvil, Enter inserta salto; en escritorio gestionamos con Shortcuts
                          onSubmitted: isMobile ? null : null,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          minLines: 1,
                          maxLines: 8,
                        );
                        if (isMobile) return field;
                        return Shortcuts(
                          shortcuts: <LogicalKeySet, Intent>{
                            LogicalKeySet(LogicalKeyboardKey.enter): const SendMessageIntent(),
                            LogicalKeySet(LogicalKeyboardKey.shift, LogicalKeyboardKey.enter):
                                const InsertNewlineIntent(),
                          },
                          child: Actions(
                            actions: <Type, Action<Intent>>{
                              SendMessageIntent: CallbackAction<SendMessageIntent>(
                                onInvoke: (intent) {
                                  _send();
                                  return null;
                                },
                              ),
                              InsertNewlineIntent: CallbackAction<InsertNewlineIntent>(
                                onInvoke: (intent) {
                                  final sel = _controller.selection;
                                  final start = sel.start >= 0 ? sel.start : _controller.text.length;
                                  final end = sel.end >= 0 ? sel.end : _controller.text.length;
                                  final newText = _controller.text.replaceRange(start, end, '\n');
                                  _controller.text = newText;
                                  _controller.selection = TextSelection.collapsed(offset: start + 1);
                                  return null;
                                },
                              ),
                            },
                            child: field,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.send, color: AppColors.primary),
                        onPressed: _send,
                      ),
                    ),
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
