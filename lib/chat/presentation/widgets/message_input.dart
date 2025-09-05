import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Provider usage removed from this widget: use ChatInputController for state/actions
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb, debugPrint;
import 'dart:convert';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';
import 'package:ai_chan/shared/widgets/animated_indicators.dart';
import '../controllers/chat_input_controller.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/shared/application/services/file_ui_service.dart';

// Intents para atajos de teclado en escritorio
class SendMessageIntent extends Intent {
  const SendMessageIntent();
}

class InsertNewlineIntent extends Intent {
  const InsertNewlineIntent();
}

class MessageInput extends StatefulWidget {
  final ChatInputController controller;
  final FileUIService fileService;

  const MessageInput({
    super.key,
    required this.controller,
    required this.fileService,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  String? _attachedImagePath;
  String? _attachedImageBase64;
  String? _attachedImageMime;
  final TextEditingController _controller = TextEditingController();
  bool _showEmojiPicker = false;
  final FocusNode _textFieldFocusNode = FocusNode();
  bool _hasRecentEmojis = false;
  final GlobalKey<EmojiPickerState> _emojiPickerKey =
      GlobalKey<EmojiPickerState>();

  Future<void> _updateHasRecentEmojis() async {
    try {
      final recents = await EmojiPickerUtils().getRecentEmojis();
      if (!mounted) return;
      setState(() {
        _hasRecentEmojis = recents.isNotEmpty;
      });
    } catch (_) {
      // ignore errors from the plugin
    }
  }

  @override
  void initState() {
    super.initState();
    // Preconsultar recents para evitar parpadeos la primera vez que se abre el picker
    _updateHasRecentEmojis();
    _textFieldFocusNode.addListener(() {
      if (_textFieldFocusNode.hasFocus && _showEmojiPicker) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
    _controller.addListener(() {
      if (mounted) {
        // Informar al controlador/parent que el usuario está escribiendo
        try {
          widget.controller.onUserTyping?.call(_controller.text);
        } catch (_) {}
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  bool _isMobile(BuildContext context) {
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
                    final filePath = pickedFile.path;
                    final bytes = await widget.fileService.readFileAsBytes(
                      filePath,
                    );
                    if (bytes != null) {
                      final base64img = base64Encode(bytes);
                      final ext = widget.fileService
                          .getFileExtension(filePath)
                          .substring(1)
                          .toLowerCase();
                      final mime = _mimeFromPath(ext);
                      setState(() {
                        _attachedImagePath = filePath;
                        _attachedImageBase64 = base64img;
                        _attachedImageMime = mime;
                      });
                    }
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
                    final filePath = pickedFile.path;
                    final bytes = await widget.fileService.readFileAsBytes(
                      filePath,
                    );
                    if (bytes != null) {
                      final base64img = base64Encode(bytes);
                      final ext = widget.fileService
                          .getFileExtension(filePath)
                          .substring(1)
                          .toLowerCase();
                      final mime = _mimeFromPath(ext);
                      setState(() {
                        _attachedImagePath = filePath;
                        _attachedImageBase64 = base64img;
                        _attachedImageMime = mime;
                      });
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    } else {
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
                    final filePath = result.files.single.path!;
                    final bytes = await widget.fileService.readFileAsBytes(
                      filePath,
                    );
                    if (bytes != null) {
                      final base64img = base64Encode(bytes);
                      final ext = widget.fileService
                          .getFileExtension(filePath)
                          .substring(1)
                          .toLowerCase();
                      final mime = _mimeFromPath(ext);
                      setState(() {
                        _attachedImagePath = filePath;
                        _attachedImageBase64 = base64img;
                        _attachedImageMime = mime;
                      });
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  String _mimeFromPath(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/png';
    }
  }

  Widget _buildImagePreview(String imagePath) {
    return FutureBuilder<List<int>?>(
      future: widget.fileService.readFileAsBytes(imagePath),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.memory(
            Uint8List.fromList(snapshot.data!),
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          );
        }
        return Container(
          width: 56,
          height: 56,
          color: Colors.grey[800],
          child: const Icon(Icons.image, color: Colors.grey),
        );
      },
    );
  }

  void _removeImage() {
    setState(() {
      _attachedImagePath = null;
      _attachedImageBase64 = null;
      _attachedImageMime = null;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final hasImage =
        _attachedImageBase64 != null && _attachedImageBase64!.isNotEmpty;
    if (text.isEmpty && !hasImage) return;

    // Delegate sending to injected controller (parent created it and wired to provider)
    AiImage? imageToSend;
    final String? imageMimeType = _attachedImageMime;
    if (hasImage) {
      final savedPath = await widget.fileService.saveBase64Image(
        _attachedImageBase64!,
        prefix: 'img_user',
      );
      if (savedPath != null) {
        final fileName = widget.fileService.getFileName(savedPath);
        imageToSend = AiImage(url: fileName, base64: _attachedImageBase64!);
      } else {
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
        _attachedImagePath = null;
        _attachedImageBase64 = null;
        _attachedImageMime = null;
      });
    }
    // Delegate to controller
    await widget.controller.scheduleSend(
      text,
      image: imageToSend,
      imageMimeType: imageMimeType,
    );
  }

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
              if (_attachedImagePath != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildImagePreview(_attachedImagePath!),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
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
                inputController: widget.controller,
                focusNode: _textFieldFocusNode,
                showEmojiPicker: _showEmojiPicker,
                attachedImagePath: _attachedImagePath,
                hasImage: _hasImage,
                hasText: _hasText,
                onToggleEmojis: () async {
                  if (_showEmojiPicker) {
                    // Cerrar picker antes de abrir teclado para evitar solapamientos
                    setState(() => _showEmojiPicker = false);
                    // Pequeña espera para que el frame procese el cambio de layout
                    await Future.delayed(const Duration(milliseconds: 50));
                    if (!mounted) return;
                    _textFieldFocusNode.requestFocus();
                  } else {
                    // Ocultar teclado primero y esperar que se cierre antes de mostrar picker
                    FocusScope.of(context).unfocus();
                    await Future.delayed(const Duration(milliseconds: 220));
                    await _updateHasRecentEmojis();
                    if (!mounted) return;
                    setState(() => _showEmojiPicker = true);
                  }
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
            child: Theme(
              // Forzar InputDecorationTheme para que la barra de búsqueda del picker
              // use fondo negro y texto en color secundario. Si la versión del plugin
              // no respeta este Theme para su SearchBar, la alternativa es ocultarla
              // usando Visibility(visible: false) alrededor de la búsqueda dentro
              // del propio paquete (no accesible aquí) o actualizar el paquete.
              data: Theme.of(context).copyWith(
                inputDecorationTheme: const InputDecorationTheme(
                  filled: true,
                  fillColor: Colors.black,
                  hintStyle: TextStyle(color: AppColors.secondary),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                // Forzar tema para la barra de categorías (selector de tipo de emoji)
                bottomNavigationBarTheme: const BottomNavigationBarThemeData(
                  backgroundColor: Colors.black,
                  selectedIconTheme: IconThemeData(color: Colors.white),
                  unselectedIconTheme: IconThemeData(
                    color: AppColors.secondary,
                  ),
                  selectedLabelStyle: TextStyle(color: Colors.white),
                  unselectedLabelStyle: TextStyle(color: AppColors.secondary),
                ),
                primaryColor: AppColors.secondary,
              ),
              child: Stack(
                children: [
                  EmojiPicker(
                    key: _emojiPickerKey,
                    onEmojiSelected: (category, emoji) async {
                      _controller.text += emoji.emoji;
                      _controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: _controller.text.length),
                      );
                      // Registrar en recents para futuras aperturas
                      try {
                        // El API expone addEmojiToRecentlyUsed(key: GlobalKey<EmojiPickerState>, emoji: Emoji)
                        EmojiPickerUtils().addEmojiToRecentlyUsed(
                          key: _emojiPickerKey,
                          emoji: emoji,
                        );
                      } catch (_) {}
                      if (!mounted) return;
                      setState(() {
                        _hasRecentEmojis = true;
                      });
                    },
                    config: Config(
                      height: 280,
                      emojiViewConfig: const EmojiViewConfig(
                        backgroundColor: Colors.black, // negro app
                        gridPadding: EdgeInsets.symmetric(
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
                        recentTabBehavior: _hasRecentEmojis
                            ? RecentTabBehavior.RECENT
                            : RecentTabBehavior.NONE,
                      ),
                      skinToneConfig: const SkinToneConfig(
                        dialogBackgroundColor: Colors.black,
                        indicatorColor: AppColors.secondary,
                      ),
                    ),
                  ),
                  // Overlay negro para cubrir la barra de tipo/categorías / buscador
                  // Si el picker renderiza el buscador fuera del área, extendemos
                  // la overlay hacia abajo con bottom negativo para cubrirlo visualmente.
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 56,
                    child: Container(color: Colors.black),
                  ),
                ],
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
  final String? attachedImagePath;
  final bool hasImage;
  final bool hasText;
  final ChatInputController? inputController;
  final VoidCallback onToggleEmojis;
  final VoidCallback onPickImage;
  final Future<void> Function() onSend;
  final bool isMobile;
  final Icon Function() buildSendIcon;
  final String sendTooltip;
  const _RecordingOrTextBar({
    required this.controller,
    this.inputController,
    required this.focusNode,
    required this.showEmojiPicker,
    required this.attachedImagePath,
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
    // Use inputController streams/actions when available
    final ic = inputController;
    if (ic == null) {
      // Si no hay controlador, mostrar un TextField básico
      return _buildInputRow();
    }

    return StreamBuilder<bool>(
      stream: ic.isRecordingStream,
      initialData: false,
      builder: (ctx, snapRec) {
        final isRec = snapRec.data ?? false;
        if (isRec) {
          return _buildRecordingUI(ic);
        }
        return _buildInputRow();
      },
    );
  }

  Widget _buildInputRow() {
    final textField = _buildTextField();
    return Row(
      children: [
        Expanded(child: textField),
        const SizedBox(width: 6),
        _buildSendButton(),
      ],
    );
  }

  Widget _buildTextField() {
    final field = TextField(
      focusNode: focusNode,
      controller: controller,
      style: const TextStyle(color: AppColors.primary, fontFamily: 'FiraMono'),
      decoration: InputDecoration(
        hintText:
            'Escribe tu mensaje...${attachedImagePath != null ? ' (opcional)' : ''}',
        hintStyle: const TextStyle(color: AppColors.secondary),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.secondary),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
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
    return _wrapWithKeyboardShortcuts(field);
  }

  Widget _buildSendButton() {
    return SizedBox(
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
          await inputController?.startRecording?.call();
        },
      ),
    );
  }

  Widget _buildRecordingUI(ChatInputController ic) {
    return StreamBuilder<List<int>>(
      stream: ic.waveformStream,
      initialData: const <int>[],
      builder: (ctx2, snapW) {
        final waveform = snapW.data ?? const <int>[];
        final raw = waveform;
        debugPrint('[Recording] waveform.length=${raw.length}');
        return StreamBuilder<Duration>(
          stream: ic.elapsedStream,
          initialData: Duration.zero,
          builder: (ctx3, snapE) {
            final elapsed = snapE.data ?? Duration.zero;
            String fmt(Duration d) =>
                '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
            return StreamBuilder<String>(
              stream: ic.liveTranscriptStream,
              initialData: '',
              builder: (ctx4, snapL) {
                final live = snapL.data ?? '';
                return Container(
                  constraints: const BoxConstraints(
                    minHeight: 60,
                    maxHeight: 122,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                          IconButton(
                            tooltip: 'Cancelar',
                            icon: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                            ),
                            onPressed: () async => ic.cancelRecording?.call(),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Row(
                              children: [
                                const BlinkingDot(),
                                const SizedBox(width: 8),
                                Text(
                                  fmt(elapsed),
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: _buildWaveform(raw)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Detener y enviar',
                            icon: const Icon(
                              Icons.stop_circle,
                              color: Colors.redAccent,
                              size: 34,
                            ),
                            onPressed: () async =>
                                ic.stopAndSendRecording?.call(),
                          ),
                        ],
                      ),
                      if (live.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 8,
                            right: 8,
                            top: 4,
                          ),
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
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWaveform(List<int> raw) {
    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double barWidth = 6.0;
          const double gap = 2.0;
          final int maxFit = ((constraints.maxWidth + gap) / (barWidth + gap))
              .floor()
              .clamp(1, 256);
          final int showCount = maxFit;
          List<int> display;
          if (raw.isEmpty) {
            display = List<int>.filled(showCount, 0);
          } else if (raw.length >= showCount) {
            display = raw.sublist(raw.length - showCount);
          } else {
            display = List<int>.generate(showCount, (i) {
              final idx = (i * raw.length / showCount).floor();
              return raw[idx.clamp(0, raw.length - 1)];
            });
          }
          final int count = display.length;
          if (count <= 1) {
            final v = count == 1 ? display.first : 0;
            return Align(
              child: SizedBox(
                width: barWidth,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  height: 4 + (v / 100) * 22,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha((0.55 * 255).round()),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }
          final List<int> toShow = display;
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(toShow.length * 2 - 1, (i) {
              if (i.isEven) {
                final val = toShow[i ~/ 2];
                return SizedBox(
                  width: barWidth,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    height: 4 + (val / 100) * 22,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha((0.55 * 255).round()),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }
              return const SizedBox(width: gap);
            }),
          );
        },
      ),
    );
  }

  /// Crea el wrapper Shortcuts/Actions común para TextField con envío y nueva línea
  Widget _wrapWithKeyboardShortcuts(Widget textField) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): SendMessageIntent(),
        SingleActivator(LogicalKeyboardKey.enter, shift: true):
            InsertNewlineIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SendMessageIntent: CallbackAction<SendMessageIntent>(
            onInvoke: (intent) {
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
        child: textField,
      ),
    );
  }
}
