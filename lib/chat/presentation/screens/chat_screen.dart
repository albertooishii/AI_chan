import 'package:ai_chan/chat/application/utils/avatar_persist_utils.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:flutter/material.dart';
import 'dart:io';
import '../../application/providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';
import '../controllers/chat_input_controller.dart';
import 'package:ai_chan/voice/presentation/screens/voice_call_screen.dart';
import '../widgets/typing_animation.dart';
import '../widgets/expandable_image_dialog.dart';
import 'package:ai_chan/core/models.dart';
import 'gallery_screen.dart';
import 'package:ai_chan/shared.dart'; // Using centralized shared exports
import 'package:ai_chan/shared/utils/model_utils.dart';
import 'package:ai_chan/shared/widgets/app_dialog.dart';
import 'package:ai_chan/shared/widgets/animated_indicators.dart';
import '../widgets/tts_configuration_dialog.dart';
import 'package:ai_chan/main.dart';
import 'package:ai_chan/shared/widgets/google_drive_backup_dialog.dart';
// google_backup_service not used directly in this file; ChatProvider exposes necessary state
import 'package:ai_chan/shared/widgets/local_backup_dialog.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;

class ChatScreen extends StatefulWidget {
  final AiChanProfile bio;
  final String aiName;
  final ChatProvider chatProvider;
  final Future<void> Function()? onClearAllDebug;
  final Future<void> Function(ImportedChat importedChat)? onImportJson;

  const ChatScreen({
    super.key,
    required this.bio,
    required this.aiName,
    required this.chatProvider,
    this.onClearAllDebug,
    this.onImportJson,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// (Clase ThreeDotsIndicator movida al final del archivo para claridad)

class _ChatScreenState extends State<ChatScreen> {
  Directory? _imageDir;
  bool _isRegeneratingAppearance =
      false; // Muestra spinner en avatar durante la regeneración
  // Google Drive linked account state is now provided by ChatProvider
  // Pagination / lazy loading for messages
  late final ScrollController _scrollController;
  int _displayedCount = 100; // inicial: últimos 100 mensajes
  bool _isLoadingMore = false;
  static const int _pageSize = 100;
  bool _showScrollToBottomButton = false;
  ChatInputController? _chatInputController;
  VoidCallback? _chatProviderListener;
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
    // El estado de la cuenta de Google se obtiene desde ChatProvider
    // No cargar voces automáticamente - solo cuando se abra el diálogo
    // Create ChatInputController after first frame so context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final provider = widget.chatProvider;
        _chatInputController = ChatInputController(
          scheduleSend: (text, {image, imageMimeType}) async {
            provider.scheduleSendMessage(
              text,
              image: image,
              imageMimeType: imageMimeType,
            );
            return Future.value();
          },
          startRecording: () async => await provider.startRecording(),
          stopAndSendRecording: () async =>
              await provider.stopAndSendRecording(),
          cancelRecording: () async => await provider.cancelRecording(),
          onUserTyping: (text) => provider.onUserTyping(text),
        );

        // Listener to push provider recording-related state into controller streams
        _chatProviderListener = () {
          try {
            // Push recording-related updates into the input controller when present.
            if (_chatInputController != null) {
              _chatInputController!.pushIsRecording(provider.isSendingAudio);
              _chatInputController!.pushWaveform(provider.currentWaveform);
              _chatInputController!.pushElapsed(provider.recordingElapsed);
              _chatInputController!.pushLiveTranscript(provider.liveTranscript);
            }
            // Also trigger a rebuild so UI elements that read provider fields
            // (for example the overflow menu showing Google Drive linked status)
            // update immediately when the provider state changes.
            if (mounted) setState(() {});
          } catch (_) {}
        };
        provider.addListener(_chatProviderListener!);
        // Ensure UI reflects current provider state immediately in case the
        // provider was already updated before this listener was attached.
        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  Future<void> _tryLoadMore() async {
    if (_isLoadingMore) return;
    final chatProvider = widget.chatProvider;
    final filtered = chatProvider.messages
        .where(
          (m) =>
              m.sender != MessageSender.system ||
              (m.sender == MessageSender.system && m.text.contains('[call]')),
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
    final (jsonStr, error) =
        await chat_json_utils.ChatJsonUtils.importJsonFile();
    if (error != null) {
      showErrorDialog(error);
      return;
    }

    if (jsonStr != null && jsonStr.trim().isNotEmpty) {
      try {
        final imported = await chat_json_utils.ChatJsonUtils.importAllFromJson(
          jsonStr,
        );
        if (widget.onImportJson != null && imported != null) {
          await widget.onImportJson!.call(imported);
        } else {
          if (imported != null) {
            await chatProvider.applyImportedChat(imported);
            if (mounted) setState(() {});
            _showImportSuccessSnackBar();
          } else {
            showErrorDialog('Error al importar: JSON inválido');
          }
        }
      } catch (e) {
        showErrorDialog('Error al importar:\n$e');
      }
    }
  }

  Future<String?> _showModelSelectionDialog(
    List<String> models,
    String? initialModel,
    ChatProvider chatProvider,
  ) async {
    final navCtx = navigatorKey.currentContext;
    if (navCtx == null) return null;
    // Use StatefulBuilder to allow in-dialog refresh of models
    bool localLoading = false;
    List<String> localModels = List.from(models);

    return await showAppDialog<String>(
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtxInner, setStateDialog) {
          Future<void> refreshModels() async {
            if (localLoading) return;
            setStateDialog(() => localLoading = true);
            try {
              final fetched = await chatProvider.getAllModels(
                forceRefresh: true,
              );
              setStateDialog(() => localModels = fetched);
            } catch (e) {
              // show error inside dialog
              showAppSnackBar(
                'Error al actualizar modelos: $e',
                preferRootMessenger: true,
              );
            } finally {
              setStateDialog(() => localLoading = false);
            }
          }

          return AppAlertDialog(
            title: const Text(
              'Modelo de texto',
              style: TextStyle(color: AppColors.primary),
            ),
            headerActions: [
              IconButton(
                icon: localLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, color: AppColors.primary),
                tooltip: 'Actualizar modelos',
                onPressed: () {
                  refreshModels();
                },
              ),
            ],
            content: localModels.isEmpty
                ? const Text(
                    'No se encontraron modelos disponibles.',
                    style: TextStyle(color: AppColors.primary),
                  )
                : Builder(
                    builder: (innerCtx) {
                      final double maxWidth = dialogContentMaxWidth(innerCtx);
                      // Use the full available dialog content width so the scroll bar
                      // sits at the right edge of the dialog (no forced narrow column).
                      final double desiredWidth = maxWidth;
                      return Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: desiredWidth),
                          child: ListView(
                            shrinkWrap: true,
                            children: () {
                              // Agrupar modelos por proveedor usando heurísticas sencillas.
                              final grouped = ModelUtils.groupModels(
                                localModels,
                              );
                              final preferred = ModelUtils.preferredOrder();
                              final others =
                                  grouped.keys
                                      .where((k) => !preferred.contains(k))
                                      .toList()
                                    ..sort();
                              final order = [
                                ...preferred.where(
                                  (k) => grouped.containsKey(k),
                                ),
                                ...others,
                              ];
                              final widgets = <Widget>[];
                              for (final grp in order) {
                                final items = grouped[grp] ?? [];
                                if (items.isEmpty) continue;
                                widgets.add(
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12.0,
                                      8.0,
                                      12.0,
                                      8.0,
                                    ),
                                    child: Text(
                                      grp,
                                      style: const TextStyle(
                                        color: AppColors.cyberpunkYellow,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                );
                                widgets.addAll(
                                  items.map(
                                    (m) => ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12.0,
                                            vertical: 4.0,
                                          ),
                                      title: Text(
                                        m,
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      trailing: initialModel == m
                                          ? const Icon(
                                              Icons.radio_button_checked,
                                              color: AppColors.secondary,
                                            )
                                          : const Icon(
                                              Icons.radio_button_off,
                                              color: AppColors.primary,
                                            ),
                                      onTap: () =>
                                          Navigator.of(dialogCtxInner).pop(m),
                                    ),
                                  ),
                                );
                                widgets.add(
                                  const Divider(
                                    color: AppColors.secondary,
                                    thickness: 1,
                                    height: 24,
                                  ),
                                );
                              }
                              return widgets;
                            }(),
                          ),
                        ),
                      );
                    },
                  ),
            // Bottom actions removed: dialog close is available in the AppAlertDialog title bar.
          );
        },
      ),
    );
  }

  void _setSelectedModel(
    String? selected,
    String? current,
    ChatProvider chatProvider,
  ) {
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

  void _showExportDialog(String jsonStr, ChatProvider chatProvider) {
    final importedChat = ImportedChat(
      profile: chatProvider.onboardingData,
      messages: chatProvider.messages,
      events: chatProvider.events,
    );
    // Delegate to shared util which shows preview and offers copy/save
    chat_json_utils.ChatJsonUtils.showExportedJsonDialog(
      jsonStr,
      chat: importedChat,
    );
  }

  // Central handler para eliminaciones de imagenes desde los viewers/galería.
  // Mantener aquí la llamada al util para evitar duplicación en varios sitios.
  Future<void> _handleImageDeleted(AiImage? deleted) async {
    try {
      final chatProvider = widget.chatProvider;
      await removeImageFromProfileAndPersist(chatProvider, deleted);
    } catch (_) {}
  }

  // Snackbar helper removed: provider handles message insertion; UI will react to provider notifications.

  bool _loadingModels = false;

  void _showErrorDialog(String error) {
    if (!mounted) return;
    showErrorDialog(error);
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = widget.chatProvider;
    final aiName = widget.aiName;
    // Detectar llamada entrante pendiente y abrir pantalla si aún no está abierta
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navCtx = context;
      final navigator = Navigator.of(navCtx);
      if (chatProvider.isCalling) {
        // Abrir VoiceCallChat en modo incoming solo si no hay ya otra ruta de llamada
        final alreadyOpen =
            navigator.widget is VoiceCallChat; // heurístico simple
        if (!alreadyOpen) {
          // Clear the calling flag to avoid reopening while the screen is active.
          chatProvider.clearPendingIncomingCall();
          navigator.push(
            MaterialPageRoute(
              builder: (_) =>
                  VoiceCallChat(incoming: true, chatProvider: chatProvider),
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
        title: Padding(
          padding: EdgeInsets.only(
            right: MediaQuery.of(context).padding.right + 8.0,
          ),
          child: Row(
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
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
                              image: AiImage(
                                url: filename,
                                seed: a.seed,
                                prompt: a.prompt,
                                createdAtMs: a.createdAtMs,
                              ),
                              text: '',
                              sender: MessageSender.assistant,
                              isImage: true,
                              dateTime: DateTime.now(),
                            );
                          }).toList();
                          // Mostrar último (index = last)
                          ExpandableImageDialog.show(
                            messages,
                            messages.length - 1,
                            imageDir: _imageDir,
                            onImageDeleted: _handleImageDeleted,
                          );
                        },
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.secondary,
                          backgroundImage: FileImage(
                            File(
                              '${_imageDir!.path}/${chatProvider.onboardingData.avatars!.last.url!.split('/').last}',
                            ),
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
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.secondary),
            tooltip: 'Llamada de voz',
            onPressed: () {
              final existing = widget.chatProvider;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VoiceCallChat(chatProvider: existing),
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
                    Icon(
                      Icons.photo_library,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Ver galería de fotos',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              // Abrir calendario (opción normal, arriba de debug)
              PopupMenuItem<String>(
                value: 'calendar',
                child: Row(
                  children: const [
                    Icon(
                      Icons.calendar_month,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Abrir calendario',
                      style: TextStyle(color: AppColors.primary),
                    ),
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
                    const Icon(
                      Icons.memory,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final defaultModel = Config.getDefaultTextModel();
                          final selected =
                              chatProvider.selectedModel ?? defaultModel;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadingModels
                                    ? 'Cargando modelos...'
                                    : 'Modelo de texto',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selected,
                                style: const TextStyle(
                                  color: AppColors.secondary,
                                  fontSize: 11,
                                ),
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
                    const Icon(
                      Icons.settings_voice,
                      color: AppColors.primary,
                      size: 20,
                    ),
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
                                style: const TextStyle(
                                  color: AppColors.primary,
                                ),
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
                                      if (p == null || p.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Text(
                                        p.toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.secondary,
                                          fontSize: 11,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      );
                                    },
                                  ),
                                  FutureBuilder<String?>(
                                    future: _loadActiveVoice(),
                                    builder: (context, snap) {
                                      final v = snap.data;
                                      if (v == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8.0,
                                        ),
                                        child: Text(
                                          v,
                                          style: const TextStyle(
                                            color: AppColors.secondary,
                                            fontSize: 11,
                                          ),
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
              // Copia de seguridad local (unificada)
              PopupMenuItem<String>(
                value: 'local_backup',
                child: Row(
                  children: const [
                    Icon(Icons.sd_storage, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Copia de seguridad local',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              // Google Drive menu entry: always show a simple label (no avatar/email)
              PopupMenuItem<String>(
                value: chatProvider.googleLinked
                    ? 'backup_status'
                    : 'backup_google',
                child: Row(
                  children: const [
                    Icon(
                      Icons.add_to_drive,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Copia de seguridad en Google Drive',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              // Debug: Vista previa JSON
              PopupMenuItem<String>(
                value: 'export_json',
                child: Row(
                  children: const [
                    Icon(Icons.code, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Vista previa JSON (debug)',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
              // Debug: regenerar apariencia
              PopupMenuItem<String>(
                value: 'regenAppearance',
                child: Row(
                  children: const [
                    Icon(Icons.refresh, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Regenerar apariencia IA (debug)',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
              // Debug: añadir un nuevo avatar (añade al array de avatars)
              PopupMenuItem<String>(
                value: 'add_new_avatar',
                child: Row(
                  children: const [
                    Icon(Icons.add_a_photo, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Añadir un nuevo avatar (debug)',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
              // Debug: borrar todo (debug) - reintroducido solo en ChatScreen
              PopupMenuItem<String>(
                value: 'clear_debug',
                child: Row(
                  children: const [
                    Icon(
                      Icons.delete_forever,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Borrar todo (debug)',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
              // Debug options removed: import chat and clear all not applicable in release flows
            ],
            onSelected: (value) async {
              if (value == 'gallery') {
                final images = chatProvider.messages
                    .where(
                      (m) =>
                          m.isImage &&
                          m.image != null &&
                          m.image!.url != null &&
                          m.image!.url!.isNotEmpty,
                    )
                    .toList();
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                Navigator.of(navCtx).push(
                  MaterialPageRoute(
                    builder: (_) => GalleryScreen(
                      images: images,
                      onImageDeleted: _handleImageDeleted,
                    ),
                  ),
                );
              } else if (value == 'calendar') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                Navigator.of(navCtx).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CalendarScreen(chatProvider: widget.chatProvider),
                  ),
                );
              } else if (value == 'export_json') {
                try {
                  final jsonStr = await BackupUtils.exportChatPartsToJson(
                    profile: widget.chatProvider.onboardingData,
                    messages: widget.chatProvider.messages,
                    events: widget.chatProvider.events,
                  );
                  final navCtx = navigatorKey.currentContext;
                  if (navCtx == null) return;
                  _showExportDialog(jsonStr, chatProvider);
                } catch (e) {
                  Log.e(
                    'Error al exportar biografía',
                    tag: 'CHAT_SCREEN',
                    error: e,
                  );
                  // showErrorDialog resolves context via navigatorKey internally
                  showErrorDialog(e.toString());
                }
              } else if (value == 'import_json') {
                await _showImportDialog(widget.chatProvider);
              } else if (value == 'local_backup') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                await showAppDialog<void>(
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: LocalBackupDialog(
                      requestExportJson: () async {
                        return await BackupUtils.exportChatPartsToJson(
                          profile: widget.chatProvider.onboardingData,
                          messages: widget.chatProvider.messages,
                          events: widget.chatProvider.events,
                        );
                      },
                      onImportedJson: (imported) async {
                        await widget.chatProvider.applyImportedChat(imported);
                        if (mounted) setState(() {});
                      },
                      onImportError: (err) {
                        showErrorDialog(err);
                      },
                    ),
                  ),
                );
              } else if (value == 'regenAppearance') {
                setState(() => _isRegeneratingAppearance = true);
                try {
                  // La generación del avatar se ejecutará automáticamente desde el provider
                  // después de actualizar la appearance. Propagamos errores para que la UI
                  // muestre un único diálogo.
                  await widget.chatProvider.regenerateAppearance(persist: true);
                } catch (e) {
                  if (!mounted) return;
                  showErrorDialog('Error al regenerar apariencia:\n$e');
                } finally {
                  if (mounted) {
                    setState(() => _isRegeneratingAppearance = false);
                  }
                }
              } else if (value == 'add_new_avatar') {
                setState(() => _isRegeneratingAppearance = true);
                try {
                  await widget.chatProvider.generateAvatarFromAppearance(
                    replace: false,
                  );
                } catch (e) {
                  if (!mounted) return;
                  showErrorDialog('Error al generar avatar:\n$e');
                } finally {
                  if (mounted) {
                    setState(() => _isRegeneratingAppearance = false);
                  }
                }
              } else if (value == 'clear_debug') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                final confirm = await showAppDialog<bool>(
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    title: const Text(
                      'Borrar todo (debug)',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    content: const Text(
                      '¿Seguro que quieres borrar absolutamente todos los datos de la app? Esta acción no se puede deshacer.',
                      style: TextStyle(color: AppColors.primary),
                    ),
                    actions: [
                      TextButton(
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(color: AppColors.primary),
                        ),
                        onPressed: () => Navigator.of(navCtx).pop(false),
                      ),
                      TextButton(
                        child: const Text(
                          'Borrar todo (debug)',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        onPressed: () => Navigator.of(navCtx).pop(true),
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
                  models = await widget.chatProvider.getAllModels();
                } catch (e) {
                  if (!mounted) return;
                  _showErrorDialog('Error al obtener modelos:\n$e');
                  setState(() => _loadingModels = false);
                  return;
                }
                setState(() => _loadingModels = false);
                final current = widget.chatProvider.selectedModel;
                final defaultModel = Config.getDefaultTextModel();
                final initialModel =
                    current ??
                    (models.contains(defaultModel)
                        ? defaultModel
                        : (models.isNotEmpty ? models.first : null));
                final selected = await _showModelSelectionDialog(
                  models,
                  initialModel,
                  widget.chatProvider,
                );
                if (!mounted) return;
                _setSelectedModel(selected, current, chatProvider);
              } else if (value == 'select_voice') {
                // Delegar selección de voz al diálogo centralizado y pasar los códigos de idioma
                final userCountry = widget.bio.userCountryCode;
                List<String> userLangCodes = [];
                if (userCountry != null && userCountry.trim().isNotEmpty) {
                  userLangCodes = LocaleUtils.officialLanguageCodesForCountry(
                    userCountry.trim().toUpperCase(),
                  );
                }

                final aiCountry = widget.bio.aiCountryCode;
                List<String> aiLangCodes = [];
                if (aiCountry != null && aiCountry.trim().isNotEmpty) {
                  aiLangCodes = LocaleUtils.officialLanguageCodesForCountry(
                    aiCountry.trim().toUpperCase(),
                  );
                }

                // Mostrar configuración de TTS en diálogo consistente con AppAlertDialog
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                final result = await TtsConfigurationDialog.showAsDialog(
                  navCtx,
                  userLangCodes: userLangCodes,
                  aiLangCodes: aiLangCodes,
                  synthesizeTts:
                      (
                        phrase, {
                        required voice,
                        required language,
                        required forDialogDemo,
                      }) async {
                        try {
                          final file = await widget.chatProvider.audioService
                              .synthesizeTts(
                                phrase,
                                voice: voice,
                                languageCode: language,
                                forDialogDemo: forDialogDemo,
                              );
                          return file;
                        } catch (e) {
                          return null;
                        }
                      },
                  onSettingsChanged: () {
                    if (mounted) setState(() {});
                  },
                );

                if (result == true && mounted) {
                  setState(() {});
                }
              } else if (value == 'backup_google') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                await showAppDialog<void>(
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: GoogleDriveBackupDialog(
                      clientId: 'YOUR_GOOGLE_CLIENT_ID',
                      requestBackupJson: () async =>
                          await BackupUtils.exportChatPartsToJson(
                            profile: chatProvider.onboardingData,
                            messages: chatProvider.messages,
                            events: chatProvider.events,
                          ),
                      onImportedJson: (jsonStr) async {
                        final imported = await chat_json_utils
                            .ChatJsonUtils.importAllFromJson(jsonStr);
                        if (imported != null) {
                          await widget.chatProvider.applyImportedChat(imported);
                        }
                      },
                      onAccountInfoUpdated:
                          ({
                            String? email,
                            String? avatarUrl,
                            String? name,
                            bool linked = false,
                          }) async {
                            await chatProvider.updateGoogleAccountInfo(
                              email: email,
                              avatarUrl: avatarUrl,
                              name: name,
                              linked: linked,
                            );
                          },
                      onClearAccountInfo: () =>
                          chatProvider.clearGoogleAccountInfo(),
                    ),
                  ),
                );
                // ChatProvider will be updated by the dialog; no local refresh needed.
              } else if (value == 'backup_status') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                await showAppDialog<void>(
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: GoogleDriveBackupDialog(
                      clientId: 'YOUR_GOOGLE_CLIENT_ID',
                      requestBackupJson: () async =>
                          await BackupUtils.exportChatPartsToJson(
                            profile: widget.chatProvider.onboardingData,
                            messages: widget.chatProvider.messages,
                            events: widget.chatProvider.events,
                          ),
                      onImportedJson: (jsonStr) async {
                        final imported = await chat_json_utils
                            .ChatJsonUtils.importAllFromJson(jsonStr);
                        if (imported != null) {
                          await widget.chatProvider.applyImportedChat(imported);
                        }
                      },
                      onAccountInfoUpdated:
                          ({
                            String? email,
                            String? avatarUrl,
                            String? name,
                            bool linked = false,
                          }) async {
                            await widget.chatProvider.updateGoogleAccountInfo(
                              email: email,
                              avatarUrl: avatarUrl,
                              name: name,
                              linked: linked,
                            );
                          },
                      onClearAccountInfo: () =>
                          chatProvider.clearGoogleAccountInfo(),
                    ),
                  ),
                );
                return;
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
                            (m.sender == MessageSender.system &&
                                m.text.contains('[call]')),
                      )
                      .toList();
                  if (filteredMessages.isEmpty) return const SizedBox.shrink();

                  final int take = filteredMessages.length <= _displayedCount
                      ? filteredMessages.length
                      : _displayedCount;
                  final shown = filteredMessages.sublist(
                    filteredMessages.length - take,
                  );
                  final reversedShown = shown.reversed.toList();
                  final hasMore = filteredMessages.length > shown.length;
                  final totalCount = reversedShown.length + (hasMore ? 1 : 0);

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 8,
                    ),
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
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Cargando mensajes antiguos...',
                                  style: TextStyle(color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final message = reversedShown[index];
                      bool isLastUserMessage = false;
                      if (message.sender == MessageSender.user) {
                        isLastUserMessage = !reversedShown
                            .skip(index + 1)
                            .any((m) => m.sender == MessageSender.user);
                      }
                      return ChatBubble(
                        message: message,
                        isLastUserMessage: isLastUserMessage,
                        imageDir: _imageDir,
                        onRetry: () async {
                          try {
                            chatProvider.retryLastFailedMessage(
                              onError: (e) {},
                            );
                          } catch (_) {}
                        },
                        onImageTap: () async {
                          try {
                            final images = chatProvider.messages
                                .where(
                                  (m) =>
                                      m.isImage &&
                                      m.image != null &&
                                      m.image!.url != null &&
                                      m.image!.url!.isNotEmpty,
                                )
                                .toList();
                            final idx = images.indexWhere(
                              (m) => m.image?.url == message.image?.url,
                            );
                            if (idx != -1) {
                              ExpandableImageDialog.show(
                                images,
                                idx,
                                imageDir: _imageDir,
                                onImageDeleted: _handleImageDeleted,
                              );
                            }
                          } catch (_) {}
                        },
                      );
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withAlpha(
                          (0.18 * 255).round(),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.secondary.withAlpha(
                              (0.12 * 255).round(),
                            ),
                            blurRadius: 8.0,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.photo_camera,
                            color: AppColors.secondary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Enviando imagen...',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withAlpha(
                          (0.18 * 255).round(),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.secondary.withAlpha(
                              (0.12 * 255).round(),
                            ),
                            blurRadius: 8.0,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mic_external_on,
                            color: AppColors.secondary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Row(
                            children: [
                              const ThreeDotsIndicator(
                                color: AppColors.secondary,
                              ),
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
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(
                          (0.18 * 255).round(),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withAlpha(
                              (0.12 * 255).round(),
                            ),
                            blurRadius: 8.0,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.keyboard_alt,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const TypingAnimation(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            MessageInput(
              controller:
                  _chatInputController ??
                  ChatInputController(
                    scheduleSend: (text, {image, imageMimeType}) async {
                      chatProvider.scheduleSendMessage(
                        text,
                        image: image,
                        imageMimeType: imageMimeType,
                      );
                      return Future.value();
                    },
                    startRecording: () async =>
                        await chatProvider.startRecording(),
                    stopAndSendRecording: () async =>
                        await chatProvider.stopAndSendRecording(),
                    cancelRecording: () async =>
                        await chatProvider.cancelRecording(),
                    onUserTyping: (text) => chatProvider.onUserTyping(text),
                  ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _showScrollToBottomButton
          ? Padding(
              padding: const EdgeInsets.only(
                bottom: 70.0,
              ), // bajar un poco el FAB
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

  // ...existing code...

  // Eliminado: diálogo para seleccionar países

  // ===== Soporte selección de voz (compartida con llamadas) =====
  Future<String?> _loadActiveVoice() async {
    try {
      // PrefsUtils.getPreferredVoice centraliza resolución y fallback.
      final voice = await PrefsUtils.getPreferredVoice(fallback: '');
      if (voice.trim().isEmpty) return null;
      return voice;
    } catch (_) {
      return null;
    }
  }

  Future<String> _loadActiveAudioProvider() async {
    try {
      // getSelectedAudioProvider() ya normaliza y aplica mapeos como 'gemini'->'google'
      return await PrefsUtils.getSelectedAudioProvider();
    } catch (_) {
      return 'google';
    }
  }

  @override
  void dispose() {
    try {
      _scrollController.dispose();
    } catch (_) {}
    try {
      if (_chatProviderListener != null) {
        final provider = widget.chatProvider;
        provider.removeListener(_chatProviderListener!);
      }
    } catch (_) {}
    try {
      _chatInputController?.dispose();
    } catch (_) {}
    super.dispose();
  }
}

// ...existing code...
