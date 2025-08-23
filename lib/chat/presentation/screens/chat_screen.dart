import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../../application/providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';
import 'package:ai_chan/voice/presentation/screens/voice_call_screen.dart';
import '../widgets/typing_animation.dart';
import '../widgets/expandable_image_dialog.dart';
import 'package:ai_chan/core/models.dart';
import 'gallery_screen.dart';
import 'package:ai_chan/shared.dart'; // Using centralized shared exports
import '../widgets/tts_configuration_dialog.dart';
import 'package:ai_chan/core/services/ia_avatar_generator.dart';

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
  // Pagination / lazy loading for messages
  late final ScrollController _scrollController;
  int _displayedCount = 100; // inicial: últimos 100 mensajes
  bool _isLoadingMore = false;
  static const int _pageSize = 100;
  bool _showScrollToBottomButton = false;
  // Estado relacionado con la carga de voces migrado a TtsConfigurationDialog

  @override
  void initState() {
    super.initState();
    getLocalImageDir().then((dir) {
      if (mounted) setState(() => _imageDir = dir);
    });
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      try {
        final pos = _scrollController.position;
        // En reverse:true, el tope (scroll hacia arriba) es maxScrollExtent
        if (pos.pixels >= (pos.maxScrollExtent - 200)) {
          _tryLoadMore();
        }
        // Mostrar botón solo cuando el usuario ha scrolleado lo suficiente
        // como para que los últimos mensajes probablemente ya no estén visibles.
        // Usamos un umbral relativo: establecerlo a 200% del viewport como solicitó el usuario.
        final threshold = (pos.viewportDimension * 2.0);
        final shouldShow = pos.pixels > threshold;
        if (shouldShow != _showScrollToBottomButton) {
          setState(() => _showScrollToBottomButton = shouldShow);
        }
      } catch (_) {}
    });
    // No cargar voces automáticamente - solo cuando se abra el diálogo
  }

  Future<void> _tryLoadMore() async {
    if (_isLoadingMore) return;
    final chatProvider = context.read<ChatProvider>();
    final filtered = chatProvider.messages
        .where(
          (m) => m.sender != MessageSender.system || (m.sender == MessageSender.system && m.text.contains('[call]')),
        )
        .toList();
    if (filtered.length <= _displayedCount) return;
    setState(() => _isLoadingMore = true);
    // Preserve scroll position: measure offset from top of list in pixels
    // In reverse:true the top is maxScrollExtent. We'll compute distance to top.
    final beforeMax = _scrollController.position.maxScrollExtent;
    final beforePixels = _scrollController.position.pixels;
    final distanceToTop = beforeMax - beforePixels;

    // pequeña espera para agrupar múltiples eventos de scroll
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    setState(() {
      _displayedCount = (_displayedCount + _pageSize).clamp(0, filtered.length);
    });

    // Allow a frame to render the newly added items and then adjust scroll
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    try {
      final afterMax = _scrollController.position.maxScrollExtent;
      final target = afterMax - distanceToTop;
      // Clamp target within scroll extents
      final clamped = target.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(clamped);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isLoadingMore = false);
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
    // Use StatefulBuilder to allow in-dialog refresh of models
    bool localLoading = false;
    List<String> localModels = List.from(models);

    return await showAppDialog<String>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtxInner, setStateDialog) {
          Future<void> refreshModels() async {
            if (localLoading) return;
            setStateDialog(() => localLoading = true);
            try {
              final chatProvider = ctx.read<ChatProvider>();
              final fetched = await chatProvider.getAllModels(forceRefresh: true);
              setStateDialog(() => localModels = fetched);
            } catch (e) {
              // show error inside dialog
              showAppSnackBar('Error al actualizar modelos: $e', preferRootMessenger: true);
            } finally {
              setStateDialog(() => localLoading = false);
            }
          }

          return AlertDialog(
            backgroundColor: Colors.black,
            title: Row(
              children: [
                const Expanded(
                  child: Text('Modelo de texto', style: TextStyle(color: AppColors.primary)),
                ),
                IconButton(
                  icon: localLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, color: AppColors.primary),
                  tooltip: 'Actualizar modelos',
                  onPressed: () {
                    refreshModels();
                  },
                ),
              ],
            ),
            content: localModels.isEmpty
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
                        ...localModels
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
                        ...localModels
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
          );
        },
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
    showAppSnackBar('Chat importado correctamente.', preferRootMessenger: true);
  }

  void _showExportDialog(BuildContext ctx, String jsonStr) {
    if (!mounted) return;
    final chatProvider = context.read<ChatProvider>();
    final importedChat = ImportedChat(
      profile: chatProvider.onboardingData,
      messages: chatProvider.messages,
      events: chatProvider.events,
    );
    // Delegate to shared util which shows preview and offers copy/save
    chat_json_utils.ChatJsonUtils.showExportedJsonDialog(ctx, jsonStr, chat: importedChat);
  }

  void _showAppearanceRegeneratedSnackBarWith(BuildContext ctx) {
    if (!mounted) return;
    showAppSnackBar('Apariencia IA regenerada y reemplazada.', preferRootMessenger: true);
  }

  bool _loadingModels = false;

  void _showErrorDialog(String error) {
    if (!mounted) return;
    showErrorDialog(error);
  }

  void _showErrorDialogWith(BuildContext ctx, String error) {
    if (!mounted) return;
    showErrorDialog(error);
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
            else if (chatProvider.onboardingData.avatars != null &&
                chatProvider.onboardingData.avatars!.isNotEmpty &&
                chatProvider.onboardingData.avatars!.last.url != null &&
                chatProvider.onboardingData.avatars!.last.url!.isNotEmpty)
              (_imageDir != null)
                  ? GestureDetector(
                      onTap: () {
                        // Construir lista de Message para ExpandableImageDialog a partir de avatars
                        final avatars = chatProvider.onboardingData.avatars!;
                        final messages = avatars.map((a) {
                          final filename = a.url?.split('/').last ?? '';
                          return Message(
                            image: AiImage(url: filename, seed: a.seed, prompt: a.prompt),
                            text: '',
                            sender: MessageSender.assistant,
                            isImage: true,
                            dateTime: DateTime.now(),
                          );
                        }).toList();
                        // Mostrar último (index = last)
                        ExpandableImageDialog.show(messages, messages.length - 1, imageDir: _imageDir);
                      },
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.secondary,
                        backgroundImage: FileImage(
                          File('${_imageDir!.path}/${chatProvider.onboardingData.avatars!.last.url!.split('/').last}'),
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
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final defaultModel = Config.getDefaultTextModel();
                          final selected = chatProvider.selectedModel ?? defaultModel;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadingModels ? 'Cargando modelos...' : 'Modelo de texto',
                                style: const TextStyle(color: AppColors.primary),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selected,
                                style: const TextStyle(color: AppColors.secondary, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // (Sistema de voz eliminado) - delegamos la gestión de proveedor en la pantalla de Configurar voz
              // Configurar voz (abre diálogo/pantalla de configuración TTS)
              PopupMenuItem<String>(
                value: 'select_voice',
                child: Row(
                  children: [
                    const Icon(Icons.settings_voice, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (ctx) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Modelo de voz',
                                style: const TextStyle(color: AppColors.primary),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  FutureBuilder<String>(
                                    future: _loadActiveAudioProvider(),
                                    builder: (context, snap2) {
                                      final p = snap2.data;
                                      if (p == null || p.isEmpty) return const SizedBox.shrink();
                                      return Text(
                                        p.toUpperCase(),
                                        style: const TextStyle(color: AppColors.secondary, fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      );
                                    },
                                  ),
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
                                          maxLines: 1,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
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
              // Debug: generar nuevo avatar (elimina anteriores y crea uno nuevo sin usar la misma semilla)
              PopupMenuItem<String>(
                value: 'generate_new_avatar',
                child: Row(
                  children: const [
                    Icon(Icons.add_a_photo, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Generar nuevo avatar (debug)', style: TextStyle(color: Colors.redAccent)),
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
                  final appearanceMap = await chatProvider.iaAppearanceGenerator.generateAppearancePrompt(bio);
                  // Regenerar usando la misma semilla (si existe) y AÑADIR al histórico, no reemplazar
                  final seed = bio.avatar?.seed;
                  final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(
                    bio,
                    appearanceMap,
                    seedOverride: seed,
                  );
                  if (!ctx.mounted) return;
                  final existing = bio.avatars ?? <AiImage>[];
                  final newBio = AiChanProfile(
                    biography: bio.biography,
                    userName: bio.userName,
                    aiName: bio.aiName,
                    userBirthday: bio.userBirthday,
                    aiBirthday: bio.aiBirthday,
                    appearance: appearanceMap as Map<String, dynamic>? ?? <String, dynamic>{},
                    avatars: [...existing, avatar],
                    timeline: bio.timeline, // timeline SIEMPRE al final
                  );
                  chatProvider.onboardingData = newBio;
                  chatProvider.saveAll();
                  setState(() {});
                  _showAppearanceRegeneratedSnackBarWith(ctx);
                } catch (e) {
                  if (!ctx.mounted) return;
                  final choice = await showAppDialog<String>(
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
                      final appearanceMap = await chatProvider.iaAppearanceGenerator.generateAppearancePrompt(bio);
                      final seed = bio.avatar?.seed;
                      final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(
                        bio,
                        appearanceMap,
                        seedOverride: seed,
                      );
                      if (!ctx.mounted) return;
                      final existing = bio.avatars ?? <AiImage>[];
                      final newBio = AiChanProfile(
                        biography: bio.biography,
                        userName: bio.userName,
                        aiName: bio.aiName,
                        userBirthday: bio.userBirthday,
                        aiBirthday: bio.aiBirthday,
                        appearance: appearanceMap as Map<String, dynamic>? ?? <String, dynamic>{},
                        avatars: [...existing, avatar],
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
                  if (mounted) {
                    setState(() => _isRegeneratingAppearance = false);
                  }
                }
              } else if (value == 'generate_new_avatar') {
                final ctx = context;
                final bio = chatProvider.onboardingData;
                if (mounted) setState(() => _isRegeneratingAppearance = true);
                try {
                  // No regenerar la apariencia: usar la apariencia existente del perfil.
                  final appearanceMap = bio.appearance as Map<String, dynamic>? ?? <String, dynamic>{};
                  // Generación completamente nueva: NO usar seed existente. Reemplaza todos los avatars.
                  final avatar = await IAAvatarGenerator().generateAvatarFromAppearance(bio, appearanceMap);
                  if (!ctx.mounted) return;
                  final newBio = AiChanProfile(
                    biography: bio.biography,
                    userName: bio.userName,
                    aiName: bio.aiName,
                    userBirthday: bio.userBirthday,
                    aiBirthday: bio.aiBirthday,
                    appearance: appearanceMap as Map<String, dynamic>? ?? <String, dynamic>{},
                    avatars: [avatar],
                    timeline: bio.timeline,
                  );
                  chatProvider.onboardingData = newBio;
                  chatProvider.saveAll();
                  setState(() {});
                  showAppSnackBar('Avatar completamente nuevo generado y reemplazado.', preferRootMessenger: true);
                } catch (e) {
                  if (!ctx.mounted) return;
                  _showErrorDialogWith(ctx, e.toString());
                } finally {
                  if (mounted) setState(() => _isRegeneratingAppearance = false);
                }
              } else if (value == 'clear_debug') {
                final confirm = await showAppDialog<bool>(
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
                final selected = await _showModelSelectionDialog(ctx, models, initialModel);
                if (!ctx.mounted) return;
                _setSelectedModel(selected, current, chatProvider);
              } else if (value == 'select_voice') {
                // Delegar selección de voz al diálogo centralizado y pasar los códigos de idioma
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

                // Abrir configuración de TTS como pantalla completa
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (ctx) => TtsConfigurationDialog(
                      userLangCodes: userLangCodes,
                      aiLangCodes: aiLangCodes,
                      chatProvider: chatProvider,
                    ),
                  ),
                );

                if (result == true && mounted) {
                  setState(() {});
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
              child: Builder(
                builder: (ctx) {
                  final filteredMessages = chatProvider.messages
                      .where(
                        (m) =>
                            m.sender != MessageSender.system ||
                            (m.sender == MessageSender.system && m.text.contains('[call]')),
                      )
                      .toList();
                  if (filteredMessages.isEmpty) return const SizedBox.shrink();

                  final int take = filteredMessages.length <= _displayedCount
                      ? filteredMessages.length
                      : _displayedCount;
                  final shown = filteredMessages.sublist(filteredMessages.length - take);
                  final reversedShown = shown.reversed.toList();
                  final hasMore = filteredMessages.length > shown.length;
                  final totalCount = reversedShown.length + (hasMore ? 1 : 0);

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    itemCount: totalCount,
                    itemBuilder: (context, index) {
                      if (index == reversedShown.length && hasMore) {
                        // slot para indicador de carga (mensajes antiguos)
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 8),
                                Text('Cargando mensajes antiguos...', style: TextStyle(color: AppColors.primary)),
                              ],
                            ),
                          ),
                        );
                      }

                      final message = reversedShown[index];
                      bool isLastUserMessage = false;
                      if (message.sender == MessageSender.user) {
                        isLastUserMessage = !reversedShown.skip(index + 1).any((m) => m.sender == MessageSender.user);
                      }
                      return ChatBubble(message: message, isLastUserMessage: isLastUserMessage, imageDir: _imageDir);
                    },
                  );
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
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _showScrollToBottomButton
          ? Padding(
              padding: const EdgeInsets.only(bottom: 70.0), // bajar un poco el FAB
              child: FloatingActionButton(
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.arrow_downward, color: Colors.black),
                onPressed: () {
                  try {
                    _scrollController.animateTo(
                      0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } catch (_) {
                    try {
                      _scrollController.jumpTo(0.0);
                    } catch (_) {}
                  }
                  setState(() => _showScrollToBottomButton = false);
                },
              ),
            )
          : null,
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

  Future<String> _loadActiveAudioProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_audio_provider');
      final envValue = Config.getAudioProvider().toLowerCase();

      String defaultValue = 'google';
      if (envValue == 'openai') {
        defaultValue = 'openai';
      }
      if (envValue == 'gemini') {
        defaultValue = 'google';
      }

      if (saved == 'gemini') {
        return 'google';
      }

      return saved ?? defaultValue;
    } catch (_) {
      return 'google';
    }
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
        final int active = (phase * 3).floor().clamp(0, 2);
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
                  color: widget.color.withAlpha(on ? 255 : (0.25 * 255).round()),
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
