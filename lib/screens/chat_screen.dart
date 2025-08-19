import 'package:ai_chan/core/config.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/constants/voices.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'dart:io';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../utils/locale_utils.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/voice_call_chat.dart';
import '../widgets/typing_animation.dart';
import '../constants/app_colors.dart';
import '../utils/dialog_utils.dart';
import '../widgets/expandable_image_dialog.dart';
// model imports covered by core barrel
import 'package:ai_chan/core/models.dart';
import '../utils/chat_json_utils.dart' as chat_json_utils;
import 'gallery_screen.dart';
import '../utils/image_utils.dart';
import 'calendar_screen.dart';
import '../services/google_speech_service.dart';
import '../utils/log_utils.dart';

class ChatScreen extends StatefulWidget {
  final AiChanProfile bio;
  final String aiName;
  final Future<void> Function()? onClearAllDebug;
  final Future<void> Function(ImportedChat importedChat)? onImportJson;

  const ChatScreen({super.key, required this.bio, required this.aiName, this.onClearAllDebug, this.onImportJson});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// (Clase ThreeDotsIndicator movida al final del archivo para claridad)

class _ChatScreenState extends State<ChatScreen> {
  Directory? _imageDir;
  bool _isRegeneratingAppearance = false; // Muestra spinner en avatar durante la regeneración
  List<Map<String, dynamic>> _fetchedGoogleVoices = [];
  bool _loadingGoogleVoices = false;

  @override
  void initState() {
    super.initState();
    getLocalImageDir().then((dir) {
      if (mounted) setState(() => _imageDir = dir);
    });
    _maybeFetchGoogleVoices();
  }

  Future<void> _maybeFetchGoogleVoices() async {
    if (!GoogleSpeechService.isConfigured) return;
    if (_loadingGoogleVoices) return;
    setState(() => _loadingGoogleVoices = true);
    try {
      // Determinar idiomas del usuario y de la IA
      final userCountry = widget.bio.userCountryCode;
      List<String> userLangCodes = [];
      if (userCountry != null && userCountry.trim().isNotEmpty) {
        userLangCodes = LocaleUtils.officialLanguageCodesForCountry(userCountry.trim().toUpperCase());
      }

      final aiCountry = widget.bio.aiCountryCode;
      List<String> aiLangCodes = [];
      if (aiCountry != null && aiCountry.trim().isNotEmpty) {
        aiLangCodes = LocaleUtils.officialLanguageCodesForCountry(aiCountry.trim().toUpperCase());
      }

      final voices = await GoogleSpeechService.voicesForUserAndAi(userLangCodes, aiLangCodes);
      if (mounted) setState(() => _fetchedGoogleVoices = voices);
    } finally {
      if (mounted) setState(() => _loadingGoogleVoices = false);
    }
  }

  Future<void> _showImportDialog(ChatProvider chatProvider) async {
    if (!mounted) return;
    final ctx = context;
    final (jsonStr, error) = await chat_json_utils.ChatJsonUtils.importJsonFile();
    if (!ctx.mounted) return;
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

  Future<String?> _showModelSelectionDialog(BuildContext ctx, List<String> models, String? initialModel) async {
    if (!ctx.mounted) return null;
    return await showDialog<String>(
      context: ctx,
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
                        'Google',
                        style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    ...models
                        .where((m) => m.toLowerCase().contains('gemini') || m.toLowerCase().contains('imagen-'))
                        .map(
                          (m) => ListTile(
                            title: Text(m, style: const TextStyle(color: AppColors.primary)),
                            trailing: initialModel == m
                                ? const Icon(Icons.radio_button_checked, color: AppColors.secondary)
                                : const Icon(Icons.radio_button_off, color: AppColors.primary),
                            onTap: () => Navigator.of(ctx).pop(m),
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
                          (m) => ListTile(
                            title: Text(m, style: const TextStyle(color: AppColors.primary)),
                            trailing: initialModel == m
                                ? const Icon(Icons.radio_button_checked, color: AppColors.secondary)
                                : const Icon(Icons.radio_button_off, color: AppColors.primary),
                            onTap: () => Navigator.of(ctx).pop(m),
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Chat importado correctamente.', style: TextStyle(color: AppColors.primary)),
        backgroundColor: AppColors.cyberpunkYellow,
      ),
    );
  }

  void _showExportDialog(BuildContext ctx, String jsonStr) {
    if (!mounted) return;
    String previewJson = jsonStr;
    try {
      final decoded = json.decode(jsonStr);
      previewJson = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}
    showDialog(
      context: ctx,
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

  void _showAppearanceRegeneratedSnackBarWith(BuildContext ctx) {
    if (!mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
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

  void _showErrorDialogWith(BuildContext ctx, String error) {
    if (!mounted) return;
    showErrorDialog(ctx, error);
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final aiName = widget.aiName;
    // Detectar llamada entrante pendiente y abrir pantalla si aún no está abierta
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navCtx = context;
      final navigator = Navigator.of(navCtx);
      if (chatProvider.hasPendingIncomingCall) {
        // Abrir VoiceCallChat en modo incoming solo si no hay ya otra ruta de llamada
        final alreadyOpen = navigator.widget is VoiceCallChat; // heurístico simple
        if (!alreadyOpen) {
          final existing = navCtx.read<ChatProvider>();
          navigator.push(
            MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(value: existing, child: const VoiceCallChat(incoming: true)),
            ),
          );
        }
      }
    });
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
            if (_isRegeneratingAppearance)
              // Spinner en lugar del avatar mientras se regenera
              const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.secondary,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              )
            else if (chatProvider.onboardingData.avatar != null &&
                chatProvider.onboardingData.avatar!.url != null &&
                chatProvider.onboardingData.avatar!.url!.isNotEmpty)
              (_imageDir != null)
                  ? GestureDetector(
                      onTap: () {
                        final avatarFilename = chatProvider.onboardingData.avatar!.url!.split('/').last;
                        final avatarMessage = Message(
                          image: AiImage(
                            url: avatarFilename,
                            seed: chatProvider.onboardingData.avatar?.seed,
                            prompt: chatProvider.onboardingData.avatar?.prompt,
                          ),
                          text: '',
                          sender: MessageSender.assistant,
                          isImage: true,
                          dateTime: DateTime.now(),
                        );
                        ExpandableImageDialog.show(context, [avatarMessage], 0, imageDir: _imageDir);
                      },
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: FileImage(
                          File('${_imageDir!.path}/${chatProvider.onboardingData.avatar!.url!.split('/').last}'),
                        ),
                      ),
                    )
                  : const CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.secondary,
                      child: Icon(Icons.person, color: AppColors.primary),
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
              final existing = context.read<ChatProvider>();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(value: existing, child: const VoiceCallChat()),
                ),
              );
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
              // Abrir calendario (opción normal, arriba de debug)
              PopupMenuItem<String>(
                value: 'calendar',
                child: Row(
                  children: const [
                    Icon(Icons.calendar_month, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Abrir calendario', style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
              // (Eliminado) Selector de países
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
                        final defaultModel = Config.getDefaultTextModel();
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
              // Seleccionar proveedor de audio
              PopupMenuItem<String>(
                value: 'select_audio_provider',
                child: Row(
                  children: [
                    const Icon(Icons.speaker, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Sistema de voz', style: TextStyle(color: AppColors.primary)),
                    FutureBuilder<String>(
                      future: _loadActiveAudioProvider(),
                      builder: (context, snapshot) {
                        final provider = snapshot.data ?? 'google';
                        final displayName = provider == 'google' ? 'GOOGLE' : provider.toUpperCase();
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            displayName,
                            style: const TextStyle(color: AppColors.secondary, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Seleccionar voz para llamadas / TTS
              PopupMenuItem<String>(
                value: 'select_voice',
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Seleccionar voz', style: TextStyle(color: AppColors.primary)),
                    FutureBuilder<String?>(
                      future: _loadActiveVoice(),
                      builder: (context, snap) {
                        final v = snap.data;
                        if (v == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            v,
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
              final ctx = context;
              if (value == 'gallery') {
                final images = chatProvider.messages
                    .where((m) => m.isImage && m.image != null && m.image!.url != null && m.image!.url!.isNotEmpty)
                    .toList();
                if (!ctx.mounted) return;
                Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => GalleryScreen(images: images)));
              } else if (value == 'calendar') {
                final existing = ctx.read<ChatProvider>();
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeNotifierProvider.value(value: existing, child: const CalendarScreen()),
                  ),
                );
              } else if (value == 'export_json') {
                final ctx = context; // capturar contexto antes de await
                try {
                  final jsonStr = await chatProvider.exportAllToJson();
                  if (!ctx.mounted) return;
                  _showExportDialog(ctx, jsonStr);
                } catch (e) {
                  Log.e('Error al exportar biografía', tag: 'CHAT_SCREEN', error: e);
                  if (!ctx.mounted) return;
                  _showErrorDialogWith(ctx, e.toString());
                }
              } else if (value == 'import_json') {
                await _showImportDialog(chatProvider);
              } else if (value == 'regenAppearance') {
                final ctx = context; // capturar contexto antes de awaits
                final bio = chatProvider.onboardingData;
                if (mounted) setState(() => _isRegeneratingAppearance = true);
                try {
                  final result = await chatProvider.iaAppearanceGenerator.generateAppearancePromptWithImage(bio);
                  if (!ctx.mounted) return;
                  final newBio = AiChanProfile(
                    biography: bio.biography,
                    userName: bio.userName,
                    aiName: bio.aiName,
                    userBirthday: bio.userBirthday,
                    aiBirthday: bio.aiBirthday,
                    appearance: result['appearance'] as Map<String, dynamic>? ?? <String, dynamic>{},
                    avatar: result['avatar'] as AiImage?,
                    timeline: bio.timeline, // timeline SIEMPRE al final
                  );
                  chatProvider.onboardingData = newBio;
                  chatProvider.saveAll();
                  setState(() {});
                  _showAppearanceRegeneratedSnackBarWith(ctx);
                } catch (e) {
                  if (!ctx.mounted) return;
                  final choice = await showDialog<String>(
                    context: ctx,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: Colors.black,
                      title: const Text(
                        'No se pudo regenerar la apariencia',
                        style: TextStyle(color: AppColors.secondary),
                      ),
                      content: SingleChildScrollView(
                        child: Text(e.toString(), style: const TextStyle(color: AppColors.primary)),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop('cancel'),
                          child: const Text('Cerrar', style: TextStyle(color: AppColors.primary)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop('retry'),
                          child: const Text('Reintentar', style: TextStyle(color: AppColors.secondary)),
                        ),
                      ],
                    ),
                  );
                  if (!ctx.mounted) return;
                  if (choice == 'retry') {
                    // Un reintento directo
                    try {
                      final result = await chatProvider.iaAppearanceGenerator.generateAppearancePromptWithImage(bio);
                      if (!ctx.mounted) return;
                      final newBio = AiChanProfile(
                        biography: bio.biography,
                        userName: bio.userName,
                        aiName: bio.aiName,
                        userBirthday: bio.userBirthday,
                        aiBirthday: bio.aiBirthday,
                        appearance: result['appearance'] as Map<String, dynamic>? ?? <String, dynamic>{},
                        avatar: result['avatar'] as AiImage?,
                        timeline: bio.timeline,
                      );
                      chatProvider.onboardingData = newBio;
                      chatProvider.saveAll();
                      setState(() {});
                      _showAppearanceRegeneratedSnackBarWith(ctx);
                    } catch (e2) {
                      if (!mounted) return;
                      _showErrorDialogWith(ctx, 'Error al regenerar apariencia (reintento):\n$e2');
                    }
                  }
                } finally {
                  if (mounted) setState(() => _isRegeneratingAppearance = false);
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
                      if (!ctx.mounted) return;
                    }
                  } catch (e) {
                    if (!ctx.mounted) return;
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
                final ctx = context;
                if (!ctx.mounted) return;
                final current = chatProvider.selectedModel;
                    final defaultModel = Config.getDefaultTextModel();
                final initialModel =
                    current ??
                    (models.contains(defaultModel) ? defaultModel : (models.isNotEmpty ? models.first : null));
                // ignore: use_build_context_synchronously
                final selected = await _showModelSelectionDialog(ctx, models, initialModel);
                if (!ctx.mounted) return;
                _setSelectedModel(selected, current, chatProvider);
              } else if (value == 'select_audio_provider') {
                final providers = ['openai', 'google'];
                final current = await _loadActiveAudioProvider();
                final ctx = context;
                if (!ctx.mounted) return;
                final selected = await showDialog<String>(
                  context: ctx,
                  builder: (ctx) {
                    return AlertDialog(
                      backgroundColor: Colors.black,
                      title: const Text('Seleccionar sistema de voz', style: TextStyle(color: AppColors.secondary)),
                      content: SizedBox(
                        width: 300,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: providers.map((provider) {
                            return ListTile(
                              title: Text(
                                provider.toUpperCase(),
                                style: TextStyle(
                                  color: current == provider ? AppColors.primary : AppColors.secondary,
                                  fontWeight: current == provider ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                provider == 'openai'
                                    ? 'OpenAI Realtime API - Rápido y integrado'
                                    : 'Google Voice - Gemini AI + Cloud TTS/STT',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                              leading: Icon(
                                provider == 'openai' ? Icons.speed : Icons.graphic_eq,
                                color: current == provider ? AppColors.primary : AppColors.secondary,
                              ),
                              onTap: () => Navigator.of(ctx).pop(provider),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                );
                if (!ctx.mounted) return;
                if (selected != null && selected != current) {
                  // ignore: use_build_context_synchronously
                  await _saveActiveAudioProvider(selected);
                  if (!ctx.mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Proveedor de audio cambiado a ${selected.toUpperCase()}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: AppColors.primary,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else if (value == 'select_voice') {
                final provider = await _loadActiveAudioProvider();
                final current = await _loadActiveVoice();
                List<dynamic> voices;
                bool isGoogle = provider == 'google';
                if (isGoogle) {
                  voices = _fetchedGoogleVoices.isNotEmpty ? _fetchedGoogleVoices : [];
                } else {
                  voices = kOpenAIVoices;
                }
                final ctx = context;
                if (!ctx.mounted) return;
                // ignore: use_build_context_synchronously
                final selected = await showDialog<String>(
                  context: ctx,
                  builder: (ctx) {
                    return AlertDialog(
                      backgroundColor: Colors.black,
                      title: Text(
                        'Selecciona voz (${provider.toUpperCase()})',
                        style: const TextStyle(color: AppColors.secondary),
                      ),
                      content: SizedBox(
                        width: 320,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isGoogle)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: Text(
                                    _loadingGoogleVoices ? 'Actualizando...' : 'Actualizar voces',
                                    style: const TextStyle(color: AppColors.secondary),
                                  ),
                                  onPressed: _loadingGoogleVoices
                                      ? null
                                      : () async {
                                          final ctx = context;
                                          if (!ctx.mounted) return;
                                          setState(() => _loadingGoogleVoices = true);
                                          try {
                                            final aiCountry = widget.bio.aiCountryCode;
                                            String? aiLangCode;
                                            if (aiCountry != null && aiCountry.trim().isNotEmpty) {
                                              final codes = LocaleUtils.officialLanguageCodesForCountry(
                                                aiCountry.trim().toUpperCase(),
                                              );
                                              if (codes.isNotEmpty) aiLangCode = codes.first;
                                            }
                                            final voices = await GoogleSpeechService.voicesForUserAndAi(
                                              ['es-ES'],
                                              [aiLangCode ?? 'es-ES'],
                                              forceRefresh: true,
                                            );
                                            if (ctx.mounted) setState(() => _fetchedGoogleVoices = voices);
                                          } finally {
                                            if (ctx.mounted) setState(() => _loadingGoogleVoices = false);
                                          }
                                        },
                                ),
                              ),
                            Flexible(
                              child: ListView(
                                shrinkWrap: true,
                                children: [
                                  ...voices.map<Widget>((v) {
                                    final isMap = v is Map<String, dynamic>;
                                    final name = isMap ? (v['name'] as String? ?? '') : (v as String);
                                    final lcodes = (isMap && v['languageCodes'] is List)
                                        ? (v['languageCodes'] as List).cast<String>()
                                        : <String>[];
                                    final descRaw = isMap
                                        ? (v['description'] ?? v['gender'] ?? v['ssmlGender'] ?? '')
                                        : '';
                                    final desc = descRaw is String ? descRaw : descRaw?.toString() ?? '';
                                    final isNeural = RegExp(r'neural|wavenet', caseSensitive: false).hasMatch(name);

                                    final List<Widget> subtitleWidgets = [];
                                    if (desc.isNotEmpty) {
                                      subtitleWidgets.add(
                                        Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      );
                                    }
                                    if (isNeural) {
                                      subtitleWidgets.add(
                                        Text('Neural', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      );
                                    }

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        current == (isGoogle ? name : v)
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off,
                                        color: AppColors.secondary,
                                        size: 20,
                                      ),
                                      title: isGoogle
                                          ? Text(
                                              '$name (${lcodes.join(',')})',
                                              style: const TextStyle(color: AppColors.primary),
                                            )
                                          : Text(v, style: const TextStyle(color: AppColors.primary)),
                                      subtitle: subtitleWidgets.isEmpty
                                          ? null
                                          : Row(
                                              children: [
                                                for (int i = 0; i < subtitleWidgets.length; i++) ...[
                                                  subtitleWidgets[i],
                                                  if (i != subtitleWidgets.length - 1) const SizedBox(width: 8),
                                                ],
                                              ],
                                            ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.play_arrow, color: AppColors.secondary),
                                        tooltip: 'Escuchar demo',
                                        onPressed: () async {
                                          final ctx = context;
                                          final chatProv = ctx.read<ChatProvider>();
                                          final phrase = isGoogle
                                              ? 'Hola, soy tu asistente con la voz $name'
                                              : 'Hola, soy tu asistente con la voz $v';
                                          try {
                                            String? lang;
                                            if (isGoogle) {
                                              if (lcodes.isNotEmpty) lang = lcodes.first;
                                            }
                                            final file = await chatProv.audioService.synthesizeTts(
                                              phrase,
                                              voice: isGoogle ? name : v,
                                              languageCode: lang,
                                            );
                                            if (file != null) {
                                              final player = AudioPlayer();
                                              await player.play(DeviceFileSource(file.path));
                                            }
                                          } catch (e) {
                                            Log.d('Error during voice demo playback: $e', tag: 'CHAT_SCREEN');
                                          }
                                        },
                                      ),
                                      onTap: () => Navigator.of(ctx).pop(isGoogle ? name : v),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
                if (!ctx.mounted) return;
                if (selected != null && selected != current) {
                  await _saveActiveVoice(selected);
                }
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
                itemCount: chatProvider.messages
                    .where(
                      (m) =>
                          m.sender != MessageSender.system ||
                          (m.sender == MessageSender.system && m.text.contains('[call]')),
                    )
                    .length,
                itemBuilder: (context, index) {
                  final filteredMessages = chatProvider.messages
                      .where(
                        (m) =>
                            m.sender != MessageSender.system ||
                            (m.sender == MessageSender.system && m.text.contains('[call]')),
                      )
                      .toList();
                  if (filteredMessages.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final reversedMessages = filteredMessages.reversed.toList();
                  final message = reversedMessages[index];
                  bool isLastUserMessage = false;
                  if (message.sender == MessageSender.user) {
                    isLastUserMessage = !reversedMessages.skip(index + 1).any((m) => m.sender == MessageSender.user);
                  }
                  return ChatBubble(message: message, isLastUserMessage: isLastUserMessage, imageDir: _imageDir);
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
            else if (chatProvider.isSendingAudio)
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
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.mic_external_on, color: AppColors.secondary, size: 22),
                          const SizedBox(width: 10),
                          Row(
                            children: [
                              const ThreeDotsIndicator(color: AppColors.secondary),
                              const SizedBox(width: 8),
                              Text(
                                'Grabando nota de voz...',
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                            ],
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

  // Eliminado: diálogo para seleccionar países

  // ===== Soporte selección de voz (compartida con llamadas) =====
  Future<String?> _loadActiveVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('selected_voice');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveActiveVoice(String voice) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_voice', voice);
    } catch (_) {}
  }

  Future<String> _loadActiveAudioProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_audio_provider');
      final envValue = Config.getAudioProvider().toLowerCase();

      // Mapear 'gemini' a 'google' para compatibilidad hacia atrás
      String defaultValue = 'google';
      if (envValue == 'openai') {
        defaultValue = 'openai';
      } else if (envValue == 'gemini') {
        defaultValue = 'google'; // Mapear gemini a google
      }

      // Si el valor guardado es 'gemini', mapearlo a 'google'
      if (saved == 'gemini') {
        return 'google';
      }

      return saved ?? defaultValue;
    } catch (_) {
      return 'google';
    }
  }

  Future<void> _saveActiveAudioProvider(String provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_audio_provider', provider);

  // También persistir mapping legacy (mapear google->gemini) en prefs y no tocar dotenv global directamente
  // No escribimos en dotenv.env, persistimos solo en SharedPreferences (ya hecho arriba)
    } catch (_) {}
  }
}

class ThreeDotsIndicator extends StatefulWidget {
  final Color color;
  const ThreeDotsIndicator({super.key, required this.color});
  @override
  State<ThreeDotsIndicator> createState() => _ThreeDotsIndicatorState();
}

class _ThreeDotsIndicatorState extends State<ThreeDotsIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final phase = _ctrl.value;
        int active = (phase * 3).floor().clamp(0, 2);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final on = i == active;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: on ? 1 : 0.25),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
