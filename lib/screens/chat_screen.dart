import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/voice_call_chat.dart';
import '../widgets/typing_animation.dart';
import '../constants/app_colors.dart';
import '../utils/dialog_utils.dart';
import '../models/ai_chan_profile.dart';
import '../widgets/expandable_image_dialog.dart';
import '../models/imported_chat.dart';
import '../models/message.dart';
import '../models/image.dart' as ai_image;
import '../utils/chat_json_utils.dart' as chat_json_utils;
import 'gallery_screen.dart';
import '../utils/image_utils.dart';

class ChatScreen extends StatefulWidget {
  final AiChanProfile bio;
  final String aiName;
  final Future<void> Function()? onClearAllDebug;
  final Future<void> Function(ImportedChat importedChat)? onImportJson;

  const ChatScreen({super.key, required this.bio, required this.aiName, this.onClearAllDebug, this.onImportJson});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Future<void> _showImportDialog(ChatProvider chatProvider) async {
    if (!mounted) return;
    final (jsonStr, error) = await chat_json_utils.ChatJsonUtils.importJsonFile();
    if (!mounted) return;
    if (error != null) {
      _showErrorDialog(error);
      return;
    }
    if (jsonStr != null && jsonStr.trim().isNotEmpty) {
      try {
        final imported = await chatProvider.importAllFromJsonAsync(jsonStr);
        if (widget.onImportJson != null && imported != null) {
          await widget.onImportJson!.call(imported);
        } else {
          if (mounted) setState(() {});
          _showImportSuccessSnackBar();
        }
      } catch (e) {
        if (!mounted) return;
        _showErrorDialog('Error al importar:\n$e');
      }
    }
  }

  Future<String?> _showModelSelectionDialog(List<String> models, String? initialModel) async {
    if (!mounted) return null;
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Seleccionar modelo', style: TextStyle(color: AppColors.primary)),
        content: models.isEmpty
            ? const Text('No se encontraron modelos disponibles.', style: TextStyle(color: AppColors.primary))
            : SizedBox(
                width: 350,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // Grupo Gemini
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Gemini',
                        style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    ...models
                        .where((m) => m.toLowerCase().contains('gemini') || m.toLowerCase().contains('imagen-'))
                        .map(
                          (m) => RadioListTile<String>(
                            value: m,
                            groupValue: initialModel,
                            onChanged: (val) => Navigator.of(ctx).pop(val),
                            title: Text(m, style: const TextStyle(color: AppColors.primary)),
                            activeColor: AppColors.secondary,
                          ),
                        ),
                    const Divider(color: AppColors.secondary, thickness: 1, height: 24),
                    // Grupo OpenAI
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'OpenAI',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    ...models
                        .where((m) => m.toLowerCase().startsWith('gpt-'))
                        .map(
                          (m) => RadioListTile<String>(
                            value: m,
                            groupValue: initialModel,
                            onChanged: (val) => Navigator.of(ctx).pop(val),
                            title: Text(m, style: const TextStyle(color: AppColors.primary)),
                            activeColor: AppColors.secondary,
                          ),
                        ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            child: const Text('Cancelar', style: TextStyle(color: AppColors.primary)),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  void _setSelectedModel(String? selected, String? current, ChatProvider chatProvider) {
    if (!mounted) return;
    if (selected != null && selected != current) {
      chatProvider.selectedModel = selected;
      setState(() {});
    }
  }

  void _showImportSuccessSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Chat importado correctamente.', style: TextStyle(color: AppColors.primary)),
        backgroundColor: AppColors.cyberpunkYellow,
      ),
    );
  }

  void _showExportDialog(String jsonStr) {
    if (!mounted) return;
    String previewJson = jsonStr;
    try {
      final decoded = json.decode(jsonStr);
      previewJson = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text('Exportar chat (.json)', style: TextStyle(color: AppColors.secondary)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: FocusScope(
              canRequestFocus: false,
              child: SelectableText(
                previewJson,
                style: const TextStyle(color: AppColors.primary, fontSize: 13),
                textAlign: TextAlign.left,
                focusNode: FocusNode(canRequestFocus: false),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Guardar como...', style: TextStyle(color: AppColors.secondary)),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final chatProvider = context.read<ChatProvider>();
              final importedChat = ImportedChat(
                profile: chatProvider.onboardingData,
                messages: chatProvider.messages,
                events: chatProvider.events,
              );
              final (success, error) = await chat_json_utils.ChatJsonUtils.saveJsonFile(importedChat);
              if (!mounted) return;
              if (error != null) {
                _showErrorDialog(error);
              } else if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Archivo guardado correctamente.'),
                    backgroundColor: AppColors.cyberpunkYellow,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAppearanceRegeneratedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Apariencia IA regenerada y reemplazada.', style: TextStyle(color: Colors.black87)),
        backgroundColor: AppColors.cyberpunkYellow,
      ),
    );
  }

  bool _loadingModels = false;

  void _showErrorDialog(String error) {
    if (!mounted) return;
    showErrorDialog(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final aiName = widget.aiName;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.primary,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.black,
        title: Row(
          children: [
            if (chatProvider.onboardingData.avatar != null &&
                chatProvider.onboardingData.avatar!.url != null &&
                chatProvider.onboardingData.avatar!.url!.isNotEmpty)
              FutureBuilder<Directory>(
                future: getLocalImageDir(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                    // Siempre usar solo el nombre de archivo, sin ruta
                    final avatarFilename = chatProvider.onboardingData.avatar!.url!.split('/').last;
                    final absPath = '${snapshot.data!.path}/$avatarFilename';
                    return GestureDetector(
                      onTap: () {
                        // Solo mostrar el avatar en el visor, sin navegar a otras imágenes
                        final avatarFilename = chatProvider.onboardingData.avatar!.url!.split('/').last;
                        final avatarMessage = Message(
                          image: ai_image.Image(
                            url: avatarFilename,
                            base64: chatProvider.onboardingData.avatar?.base64,
                            seed: chatProvider.onboardingData.avatar?.seed,
                            prompt: chatProvider.onboardingData.avatar?.prompt,
                          ),
                          text: '',
                          sender: MessageSender.ia,
                          isImage: true,
                          dateTime: DateTime.now(),
                        );
                        ExpandableImageDialog.show(context, [avatarMessage], 0);
                      },
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: FileImage(File(absPath)),
                      ),
                    );
                  }
                  return const CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.secondary,
                    child: Icon(Icons.person, color: AppColors.primary),
                  );
                },
              ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                aiName,
                style: const TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.secondary),
            tooltip: 'Llamada de voz',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => VoiceCallChat()));
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.primary),
            itemBuilder: (context) => [
              // Galería primero
              PopupMenuItem<String>(
                value: 'gallery',
                child: Row(
                  children: const [
                    Icon(Icons.photo_library, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Ver galería de fotos', style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
              // Seleccionar modelo
              PopupMenuItem<String>(
                enabled: !_loadingModels,
                value: 'select_model',
                child: Row(
                  children: [
                    const Icon(Icons.memory, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _loadingModels ? 'Cargando modelos...' : 'Seleccionar modelo',
                      style: const TextStyle(color: AppColors.primary),
                    ),
                    Builder(
                      builder: (context) {
                        final defaultModel = 'gpt-4.1-mini';
                        final selected = chatProvider.selectedModel ?? defaultModel;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            selected,
                            style: const TextStyle(color: AppColors.secondary, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              // Exportar chat
              PopupMenuItem<String>(
                value: 'export_json',
                child: Row(
                  children: const [
                    Icon(Icons.save_alt, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Exportar chat (JSON)', style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
              // Importar chat
              PopupMenuItem<String>(
                value: 'import_json',
                child: Row(
                  children: const [
                    Icon(Icons.file_open, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Importar chat (JSON)', style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              // Debug: regenerar apariencia
              PopupMenuItem<String>(
                value: 'regenAppearance',
                child: Row(
                  children: const [
                    Icon(Icons.refresh, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Regenerar apariencia IA (debug)', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
              // Debug: borrar todo
              PopupMenuItem<String>(
                value: 'clear_debug',
                child: Row(
                  children: const [
                    Icon(Icons.delete_forever, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Borrar todo (debug)', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
            onSelected: (value) async {
              if (value == 'gallery') {
                final images = chatProvider.messages
                    .where((m) => m.isImage && m.image != null && m.image!.url != null && m.image!.url!.isNotEmpty)
                    .toList();
                if (!mounted) return;
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => GalleryScreen(images: images)));
              } else if (value == 'export_json') {
                try {
                  final jsonStr = await chatProvider.exportAllToJson();
                  if (!mounted) return;
                  _showExportDialog(jsonStr);
                } catch (e) {
                  debugPrint('[AI-chan] Error al exportar biografía: $e, valor=${chatProvider.onboardingData}');
                  if (!mounted) return;
                  _showErrorDialog(e.toString());
                }
              } else if (value == 'import_json') {
                await _showImportDialog(chatProvider);
              } else if (value == 'regenAppearance') {
                final bio = chatProvider.onboardingData;
                try {
                  final result = await chatProvider.iaAppearanceGenerator.generateAppearancePromptWithImage(bio);
                  if (!mounted) return;
                  final newBio = AiChanProfile(
                    personality: bio.personality,
                    biography: bio.biography,
                    userName: bio.userName,
                    aiName: bio.aiName,
                    userBirthday: bio.userBirthday,
                    aiBirthday: bio.aiBirthday,
                    appearance: result['appearance'] as Map<String, dynamic>? ?? <String, dynamic>{},
                    avatar: result['avatar'],
                    timeline: bio.timeline, // timeline SIEMPRE al final
                  );
                  chatProvider.onboardingData = newBio;
                  chatProvider.saveAll();
                  setState(() {});
                  _showAppearanceRegeneratedSnackBar();
                } catch (e) {
                  if (!mounted) return;
                  _showErrorDialog('Error al regenerar apariencia:\n$e');
                }
              } else if (value == 'clear_debug') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    title: const Text('Borrar todo (debug)', style: TextStyle(color: Colors.redAccent)),
                    content: const Text(
                      '¿Seguro que quieres borrar absolutamente todos los datos de la app? Esta acción no se puede deshacer.',
                      style: TextStyle(color: AppColors.primary),
                    ),
                    actions: [
                      TextButton(
                        child: const Text('Cancelar', style: TextStyle(color: AppColors.primary)),
                        onPressed: () => Navigator.of(ctx).pop(false),
                      ),
                      TextButton(
                        child: const Text('Borrar todo (debug)', style: TextStyle(color: Colors.redAccent)),
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ],
                  ),
                );
                if (!mounted) return;
                if (confirm == true) {
                  try {
                    if (widget.onClearAllDebug != null) {
                      await widget.onClearAllDebug?.call();
                      if (!mounted) return;
                    }
                  } catch (e) {
                    if (!mounted) return;
                    _showErrorDialog(e.toString());
                  }
                }
              } else if (value == 'select_model') {
                if (_loadingModels) return;
                setState(() => _loadingModels = true);
                List<String> models = [];
                try {
                  models = await chatProvider.getAllModels();
                } catch (e) {
                  if (!mounted) return;
                  _showErrorDialog('Error al obtener modelos:\n$e');
                  setState(() => _loadingModels = false);
                  return;
                }
                setState(() => _loadingModels = false);
                if (!mounted) return;
                final current = chatProvider.selectedModel;
                final defaultModel = 'gpt-4.1-mini';
                final initialModel =
                    current ??
                    (models.contains(defaultModel) ? defaultModel : (models.isNotEmpty ? models.first : null));
                final selected = await _showModelSelectionDialog(models, initialModel);
                _setSelectedModel(selected, current, chatProvider);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                itemCount: chatProvider.messages.length,
                itemBuilder: (context, index) {
                  final filteredMessages = chatProvider.messages
                      .where((m) => m.sender != MessageSender.system)
                      .toList();
                  final reversedMessages = filteredMessages.reversed.toList();
                  final message = reversedMessages[index];
                  // Solo el último mensaje del usuario (más reciente) debe tener isLastUserMessage = true
                  bool isLastUserMessage = false;
                  if (message.sender == MessageSender.user) {
                    // Busca el primer mensaje user en la lista invertida (el más reciente)
                    isLastUserMessage = !reversedMessages.skip(index + 1).any((m) => m.sender == MessageSender.user);
                  }
                  return ChatBubble(message: message, isLastUserMessage: isLastUserMessage);
                },
              ),
            ),
            if (chatProvider.isSendingImage)
              Padding(
                padding: const EdgeInsets.only(left: 12.0, bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withAlpha((0.18 * 255).round()),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.secondary.withAlpha((0.12 * 255).round()),
                            blurRadius: 8.0,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.photo_camera, color: AppColors.secondary, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Enviando imagen...',
                            style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.w500, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else if (chatProvider.isTyping)
              Padding(
                padding: const EdgeInsets.only(left: 12.0, bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha((0.18 * 255).round()),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withAlpha((0.12 * 255).round()),
                            blurRadius: 8.0,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.keyboard_alt, color: AppColors.primary, size: 22),
                          const SizedBox(width: 10),
                          const TypingAnimation(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            MessageInput(
              onSend: (text) {
                chatProvider.sendMessage(text, onError: (error) => _showErrorDialog(error));
              },
            ),
          ],
        ),
      ),
    );
  }
}
