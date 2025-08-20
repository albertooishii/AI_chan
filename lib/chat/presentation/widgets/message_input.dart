import 'package:ai_chan/shared/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'dart:io';
import 'dart:convert';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import '../../application/providers/chat_provider.dart';
import 'package:ai_chan/core/models.dart';

// Intents para atajos de teclado en escritorio
class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

class InsertNewlineIntent extends Intent {
  const InsertNewlineIntent();
}

class MessageInput extends StatefulWidget {
  final void Function(String text)? onSend;
  final VoidCallback? onRecordAudio;
  const MessageInput({super.key, this.onSend, this.onRecordAudio});

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
  // Eliminado estado local de grabación; se usa ChatProvider.isRecording

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
    _controller.addListener(() {
      setState(() {});
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
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
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
                  final pickedFile = await picker.pickImage(
                    source: ImageSource.camera,
                    imageQuality: 85,
                  );
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
                  final pickedFile = await picker.pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 85,
                  );
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
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.image,
                  );
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
    final hasImage =
        _attachedImageBase64 != null && _attachedImageBase64!.isNotEmpty;
    if (text.isEmpty && !hasImage) return;

    final chatProvider = context.read<ChatProvider>();
    AiImage? imageToSend;
    String? imageMimeType = _attachedImageMime;
    if (hasImage) {
      // Guardar la imagen en local y obtener el nombre real
      final savedPath = await saveBase64ImageToFile(
        _attachedImageBase64!,
        prefix: 'img_user',
      );
      if (savedPath != null) {
        final fileName = savedPath.split('/').last;
        imageToSend = AiImage(url: fileName, base64: _attachedImageBase64!);
      } else {
        // Si falla, usar el nombre generado como antes
        final ext = imageMimeType == 'image/jpeg'
            ? 'jpg'
            : imageMimeType == 'image/webp'
            ? 'webp'
            : 'png';
        final fileName =
            'img_user_${DateTime.now().millisecondsSinceEpoch}.$ext';
        imageToSend = AiImage(url: fileName, base64: _attachedImageBase64!);
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
    await chatProvider.sendMessage(
      text,
      image: imageToSend,
      imageMimeType: imageMimeType,
    );
  }

  // Botón simple (solo enviar texto/imagen)
  bool get _hasText => _controller.text.trim().isNotEmpty;
  bool get _hasImage =>
      _attachedImageBase64 != null && _attachedImageBase64!.isNotEmpty;
  Icon _primaryIcon() => const Icon(Icons.send, color: AppColors.primary);
  String _primaryTooltip() => 'Enviar mensaje';
  Future<void> _onPrimaryPressed() async {
    if (_hasText || _hasImage) await _send();
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
              _RecordingOrTextBar(
                controller: _controller,
                focusNode: _textFieldFocusNode,
                showEmojiPicker: _showEmojiPicker,
                attachedImage: _attachedImage,
                hasImage: _hasImage,
                hasText: _hasText,
                onToggleEmojis: () {
                  if (_showEmojiPicker) {
                    FocusScope.of(context).requestFocus(_textFieldFocusNode);
                  } else {
                    FocusScope.of(context).unfocus();
                  }
                  setState(() => _showEmojiPicker = !_showEmojiPicker);
                },
                onPickImage: _pickImage,
                onSend: _onPrimaryPressed,
                isMobile: isMobile,
                buildSendIcon: _primaryIcon,
                sendTooltip: _primaryTooltip(),
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
                _controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: _controller.text.length),
                );
              },
              config: Config(
                height: 280,
                checkPlatformCompatibility: true,
                viewOrderConfig: ViewOrderConfig(
                  top: EmojiPickerItem.categoryBar,
                  middle: EmojiPickerItem.emojiView,
                ),
                emojiViewConfig: EmojiViewConfig(
                  emojiSizeMax: 28,
                  backgroundColor: Colors.black, // negro app
                  gridPadding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
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

class _RecordingOrTextBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showEmojiPicker;
  final File? attachedImage;
  final bool hasImage;
  final bool hasText;
  final VoidCallback onToggleEmojis;
  final VoidCallback onPickImage;
  final Future<void> Function() onSend;
  final bool isMobile;
  final Icon Function() buildSendIcon;
  final String sendTooltip;
  const _RecordingOrTextBar({
    required this.controller,
    required this.focusNode,
    required this.showEmojiPicker,
    required this.attachedImage,
    required this.hasImage,
    required this.hasText,
    required this.onToggleEmojis,
    required this.onPickImage,
    required this.onSend,
    required this.isMobile,
    required this.buildSendIcon,
    required this.sendTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    if (chat.isRecording) {
      // Barra de grabación
      final waveform = chat.currentWaveform;
      final display = waveform.length > 48
          ? waveform.sublist(waveform.length - 48)
          : waveform;
      final elapsed = chat.recordingElapsed;
      String fmt(Duration d) =>
          '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
      final live = chat.liveTranscript;
      return Container(
        constraints: const BoxConstraints(minHeight: 60, maxHeight: 122),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.redAccent, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Cancelar
                IconButton(
                  tooltip: 'Cancelar',
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: () async => chat.cancelRecording(),
                ),
                const SizedBox(width: 4),
                // Indicador y waveform
                Expanded(
                  child: Row(
                    children: [
                      const _BlinkingDot(),
                      const SizedBox(width: 8),
                      Text(
                        fmt(elapsed),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 28,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: display
                                .map(
                                  (v) => Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        height: 4 + (v / 100) * 22,
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withAlpha(
                                            (0.55 * 255).round(),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Detener / enviar
                IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Detener y enviar',
                  icon: const Icon(
                    Icons.stop_circle,
                    color: Colors.redAccent,
                    size: 34,
                  ),
                  onPressed: () async => chat.stopAndSendRecording(),
                ),
              ],
            ),
            if (live.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    live,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 6),
                child: Text(
                  'Hablando... subtítulos en vivo',
                  style: TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
          ],
        ),
      );
    }

    // Barra de texto normal
    Widget field = TextField(
      focusNode: focusNode,
      controller: controller,
      style: const TextStyle(color: AppColors.primary, fontFamily: 'FiraMono'),
      decoration: InputDecoration(
        hintText:
            'Escribe tu mensaje...${attachedImage != null ? ' (opcional)' : ''}',
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        prefixIcon: IconButton(
          icon: showEmojiPicker
              ? const Icon(Icons.close, color: AppColors.secondary)
              : const Icon(
                  Icons.emoji_emotions_outlined,
                  color: AppColors.secondary,
                ),
          onPressed: onToggleEmojis,
          tooltip: showEmojiPicker ? 'Cerrar emojis' : 'Emojis',
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.camera_alt, color: AppColors.secondary),
          onPressed: onPickImage,
          tooltip: 'Foto o galería',
        ),
      ),
      // En móvil mantenemos botón "enviar" del teclado; en desktop/web usamos newline para gestionar atajos manualmente
      textInputAction: isMobile
          ? TextInputAction.send
          : TextInputAction.newline,
      onSubmitted: (_) async {
        if (!isMobile) {
          return; // Desktop/web: envío sólo vía shortcut Enter sin Shift
        }
        if (controller.text.trim().isNotEmpty || hasImage) {
          await onSend();
        }
      },
      keyboardType: TextInputType.multiline,
      minLines: 1,
      maxLines: 8,
    );
    // Atajos activos en todas las plataformas (teclado físico / desktop / web / móvil con teclado).
    field = Shortcuts(
      // Usamos SingleActivator para distinguir explícitamente Enter sin Shift vs Shift+Enter
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.enter):
            const SendMessageIntent(),
        const SingleActivator(LogicalKeyboardKey.enter, shift: true):
            const InsertNewlineIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SendMessageIntent: CallbackAction<SendMessageIntent>(
            onInvoke: (intent) {
              // Evitar enviar si está vacío y sin imagen
              if (controller.text.trim().isEmpty && !hasImage) return null;
              onSend();
              return null;
            },
          ),
          InsertNewlineIntent: CallbackAction<InsertNewlineIntent>(
            onInvoke: (intent) {
              final sel = controller.selection;
              final start = sel.start >= 0 ? sel.start : controller.text.length;
              final end = sel.end >= 0 ? sel.end : controller.text.length;
              final newText = controller.text.replaceRange(start, end, '\n');
              controller.text = newText;
              controller.selection = TextSelection.collapsed(offset: start + 1);
              return null;
            },
          ),
        },
        child: field,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: field),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: hasText || hasImage
                ? buildSendIcon()
                : const Icon(Icons.mic, color: AppColors.secondary),
            tooltip: hasText || hasImage ? sendTooltip : 'Grabar nota de voz',
            onPressed: () async {
              if (hasText || hasImage) {
                await onSend();
                return;
              }
              await chat.startRecording();
            },
          ),
        ),
      ],
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
