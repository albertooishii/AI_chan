import 'package:ai_chan/chat/application/utils/avatar_persist_utils.dart';
import 'package:ai_chan/chat/presentation/controllers/chat_controller.dart'; // ✅ DDD: ETAPA 3 - DDD puro completado
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared/utils/chat_json_utils.dart' as chat_json_utils;
import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/chat_bubble.dart';
import '../widgets/message_input.dart';
import '../controllers/chat_input_controller.dart';
import 'package:ai_chan/call/presentation/screens/voice_call_screen.dart';
import '../widgets/typing_animation.dart';
import '../widgets/expandable_image_dialog.dart';
import 'package:ai_chan/core/models.dart';
import 'gallery_screen.dart';
import 'package:ai_chan/shared.dart'; // Using centralized shared exports
import 'package:ai_chan/shared/utils/model_utils.dart';
import 'package:ai_chan/shared/widgets/animated_indicators.dart';
import '../widgets/tts_configuration_dialog.dart';
import 'package:ai_chan/main.dart';
import 'package:ai_chan/shared/widgets/backup_dialog_factory.dart';
import 'package:ai_chan/shared/widgets/google_drive_backup_dialog.dart';
// google_backup_service not used directly in this file; ChatProvider exposes necessary state
import 'package:ai_chan/shared/widgets/local_backup_dialog.dart';
import 'package:ai_chan/shared/widgets/backup_diagnostics_dialog.dart';
import 'package:ai_chan/shared/utils/backup_utils.dart' show BackupUtils;
import 'package:ai_chan/core/di.dart' as di;
import 'dart:typed_data';
// ignore: unused_import
import 'package:ai_chan/core/domain/interfaces/i_call_to_chat_communication_service.dart'; // ✅ Bounded Context Abstraction

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.bio,
    required this.aiName,
    required this.chatController, // ✅ DDD: ETAPA 3 - DDD puro
    this.onClearAllDebug,
    this.onImportJson,
  });
  final AiChanProfile bio;
  final String aiName;
  final ChatController chatController; // ✅ DDD: ETAPA 3 - DDD puro
  final Future<void> Function()? onClearAllDebug;
  final Future<void> Function(ChatExport chatExport)? onImportJson;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// (Clase ThreeDotsIndicator movida al final del archivo para claridad)

class _ChatScreenState extends State<ChatScreen> {
  Directory? _imageDir;
  bool _isRegeneratingAppearance =
      false; // Muestra spinner en avatar durante la regeneración
  late final FileUIService _fileUIService;
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
    _fileUIService = di.getFileUIService();
    getLocalImageDir().then((final dir) {
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
      } on Exception catch (_) {}
    });
    // El estado de la cuenta de Google se obtiene desde ChatProvider
    // No cargar voces automáticamente - solo cuando se abra el diálogo
    // Create ChatInputController after first frame so context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final provider = widget.chatController;
        _chatInputController = ChatInputController(
          scheduleSend: (final text, {final image, final imageMimeType}) async {
            provider.messageController.scheduleSendMessage(
              text,
              image: image,
              imageMimeType: imageMimeType,
            );
            return Future.value();
          },
          startRecording: () async =>
              await provider.audioController.startRecording(),
          stopAndSendRecording: () async =>
              await provider.audioController.stopAndSendRecording(),
          cancelRecording: () async =>
              await provider.audioController.cancelRecording(),
          onUserTyping: (final text) =>
              provider.messageController.onUserTyping(text),
        );

        // Listener to push provider recording-related state into controller streams
        _chatProviderListener = () {
          try {
            // Push recording-related updates into the input controller when present.
            if (_chatInputController != null) {
              _chatInputController!.pushIsRecording(provider.isRecording);
              _chatInputController!.pushWaveform(provider.currentWaveform);
              _chatInputController!.pushElapsed(provider.recordingElapsed);
              _chatInputController!.pushLiveTranscript(provider.liveTranscript);
            }
            // Also trigger a rebuild so UI elements that read provider fields
            // (for example the overflow menu showing Google Drive linked status)
            // update immediately when the provider state changes.
            if (mounted) setState(() {});
          } on Exception catch (_) {}
        };
        provider.addListener(_chatProviderListener!);
        // Ensure UI reflects current provider state immediately in case the
        // provider was already updated before this listener was attached.
        if (mounted) setState(() {});
      } on Exception catch (_) {}
    });
  }

  Future<void> _tryLoadMore() async {
    if (_isLoadingMore) return;
    final chatController = widget.chatController;
    final filtered = chatController.messages
        .where(
          (final m) =>
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
      _displayedCount = (_displayedCount + _pageSize)
          .clamp(0, filtered.length)
          .toInt();
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
    } on Exception catch (_) {}

    if (!mounted) return;
    setState(() => _isLoadingMore = false);
  }

  Future<void> _showImportDialog(final ChatController chatController) async {
    // ✅ DDD: ETAPA 3
    // ✅ DDD: Type safety en ETAPA 2
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
            await chatController.applyChatExport(imported.toJson());
            if (mounted) setState(() {});
            _showImportSuccessSnackBar();
          } else {
            showErrorDialog('Error al importar: JSON inválido');
          }
        }
      } on Exception catch (e) {
        showErrorDialog('Error al importar:\n$e');
      }
    }
  }

  Future<String?> _showModelSelectionDialog(
    final List<String> models,
    final String? initialModel,
    final ChatController chatController, // ✅ DDD: ETAPA 3
  ) async {
    // ✅ DDD: Type safety en ETAPA 2
    final navCtx = navigatorKey.currentContext;
    if (navCtx == null) return null;
    // Use StatefulBuilder to allow in-dialog refresh of models
    bool localLoading = false;
    List<String> localModels = List.from(models);

    return await showAppDialog<String>(
      builder: (final dialogCtx) => StatefulBuilder(
        builder: (final dialogCtxInner, final setStateDialog) {
          Future<void> refreshModels() async {
            if (localLoading) return;
            setStateDialog(() => localLoading = true);
            try {
              final fetched = await chatController.getAllModels(
                forceRefresh: true,
              );
              setStateDialog(() => localModels = fetched);
            } on Exception catch (e) {
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
                        child: CyberpunkLoader(message: 'SYNC...'),
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
                    builder: (final innerCtx) {
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
                                      .where(
                                        (final k) => !preferred.contains(k),
                                      )
                                      .toList()
                                    ..sort();
                              final order = [
                                ...preferred.where(
                                  (final k) => grouped.containsKey(k),
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
                                    (final m) => ListTile(
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
    final String? selected,
    final String? current,
    final ChatController chatController,
  ) {
    // ✅ DDD: ETAPA 3
    // ✅ DDD: Type safety en ETAPA 2
    if (!mounted) return;
    if (selected != null && selected != current) {
      chatController.setSelectedModel(
        selected,
      ); // ✅ DDD: ETAPA 3 - Usar método setSelectedModel
      setState(() {});
    }
  }

  void _showImportSuccessSnackBar() {
    if (!mounted) return;
    showAppSnackBar('Chat importado correctamente.', preferRootMessenger: true);
  }

  void _showExportDialog(
    final String jsonStr,
    final ChatController chatController,
  ) {
    // ✅ DDD: ETAPA 3
    // ✅ DDD: Type safety en ETAPA 2
    final chatExport = ChatExport(
      profile: chatController.profile!,
      messages: chatController.messages,
      events: [],
      timeline: chatController.timeline,
    );
    // Delegate to shared util which shows preview and offers copy/save
    chat_json_utils.ChatJsonUtils.showExportedJsonDialog(
      jsonStr,
      chat: chatExport,
    );
  }

  // Central handler para eliminaciones de imagenes desde los viewers/galería.
  // Mantener aquí la llamada al util para evitar duplicación en varios sitios.
  Future<void> _handleImageDeleted(final AiImage? deleted) async {
    try {
      final chatController = widget.chatController;
      await removeImageFromProfileAndPersist(chatController, deleted);
    } on Exception catch (_) {}
  }

  // Snackbar helper removed: provider handles message insertion; UI will react to provider notifications.

  bool _loadingModels = false;

  void _showErrorDialog(final String error) {
    if (!mounted) return;
    showErrorDialog(error);
  }

  @override
  Widget build(final BuildContext context) {
    final chatController = widget.chatController;
    final aiName = widget.aiName;
    // Detectar llamada entrante pendiente y abrir pantalla si aún no está abierta
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navCtx = context;
      final navigator = Navigator.of(navCtx);
      if (chatController.isCalling) {
        // Abrir VoiceCallScreen en modo incoming solo si no hay ya otra ruta de llamada
        final alreadyOpen =
            navigator.widget is VoiceCallScreen; // heurístico simple
        if (!alreadyOpen) {
          // Clear the calling flag to avoid reopening while the screen is active.
          chatController.callController.clearPendingIncomingCall();
          navigator.push(
            MaterialPageRoute(
              builder: (_) => const VoiceCallScreen(incoming: true),
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
                // Loader cyberpunk minimalista para el avatar
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.black87,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Stack(
                      children: [
                        // Anillo exterior con efecto glow
                        Positioned.fill(
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        // Punto central con glow cyberpunk
                        Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary,
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Spinner principal
                        const Positioned.fill(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (chatController.profile?.avatars != null &&
                  chatController.profile!.avatars!.isNotEmpty &&
                  chatController.profile!.avatars!.last.url != null &&
                  chatController.profile!.avatars!.last.url!.isNotEmpty)
                (_imageDir != null)
                    ? GestureDetector(
                        onTap: () {
                          // Construir lista de Message para ExpandableImageDialog a partir de avatars
                          final avatars = chatController.profile!.avatars!;
                          final messages = avatars.map((final a) {
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
                            imageBasePath: _imageDir?.path,
                            fileUIService: _fileUIService,
                            onImageDeleted: _handleImageDeleted,
                          );
                        },
                        child: FutureBuilder<List<int>?>(
                          future: _fileUIService.readFileAsBytes(
                            '${_imageDir!.path}/${chatController.profile!.avatars!.last.url!.split('/').last}',
                          ),
                          builder: (final context, final snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.secondary,
                                backgroundImage: MemoryImage(
                                  Uint8List.fromList(snapshot.data!),
                                ),
                              );
                            }
                            return const CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.secondary,
                              child: Icon(Icons.person, color: Colors.grey),
                            );
                          },
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
                    fontFamily: 'monospace',
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
              // ignore: unused_local_variable
              final existingController = widget.chatController;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceCallScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.primary),
            itemBuilder: (final context) => [
              // Galería primero
              _buildMenuItem(
                value: 'gallery',
                icon: Icons.photo_library,
                text: 'Ver galería de fotos',
              ),
              // Abrir calendario (opción normal, arriba de debug)
              _buildMenuItem(
                value: 'calendar',
                icon: Icons.calendar_month,
                text: 'Abrir calendario',
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
                        builder: (final context) {
                          final defaultModel = Config.getDefaultTextModel();
                          final selected =
                              chatController.selectedModel ?? defaultModel;
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
                                  fontFamily: 'monospace',
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
                        builder: (final ctx) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Modelo de voz',
                                style: TextStyle(color: AppColors.primary),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  FutureBuilder<String>(
                                    future: _loadActiveAudioProvider(),
                                    builder: (final context, final snap2) {
                                      final p = snap2.data;
                                      if (p == null || p.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Text(
                                        p.toUpperCase(),
                                        style: const TextStyle(
                                          color: AppColors.secondary,
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      );
                                    },
                                  ),
                                  FutureBuilder<String?>(
                                    future: _loadActiveVoice(),
                                    builder: (final context, final snap) {
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
                                            fontFamily: 'monospace',
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
              _buildMenuItem(
                value: 'local_backup',
                icon: Icons.sd_storage,
                text: 'Copia de seguridad local',
              ),
              // Google Drive menu entry: always show a simple label (no avatar/email)
              _buildMenuItem(
                value: chatController.googleLinked
                    ? 'backup_status'
                    : 'backup_google',
                icon: Icons.add_to_drive,
                text: 'Copia de seguridad en Google Drive',
              ),
              const PopupMenuDivider(),
              // Opciones de debug - solo mostrar si DEBUG_MODE != 'off'
              if (Log.showDebugOptions) ...[
                // Debug: Vista previa JSON
                _buildMenuItem(
                  value: 'export_json',
                  icon: Icons.code,
                  text: 'Vista previa JSON (debug)',
                  color: Colors.redAccent,
                ),
                // Debug: regenerar apariencia
                _buildMenuItem(
                  value: 'regenAppearance',
                  icon: Icons.refresh,
                  text: 'Regenerar apariencia IA (debug)',
                  color: Colors.redAccent,
                ),
                // Debug: añadir un nuevo avatar (añade al array de avatars)
                _buildMenuItem(
                  value: 'add_new_avatar',
                  icon: Icons.add_a_photo,
                  text: 'Añadir un nuevo avatar (debug)',
                  color: Colors.redAccent,
                ),
                // Diagnóstico completo de backup y autenticación Google
                _buildMenuItem(
                  value: 'backup_diagnostics',
                  icon: Icons.health_and_safety,
                  text: 'Diagnóstico Google Drive',
                  color: Colors.orangeAccent,
                ),
                const PopupMenuDivider(),
              ],
              // Cerrar sesión - siempre visible, al final del menú
              _buildMenuItem(
                value: 'logout',
                icon: Icons.logout,
                text: 'Cerrar sesión',
                color: Colors.redAccent,
              ),
              // Debug options removed: import chat and clear all not applicable in release flows
            ],
            onSelected: (final value) async {
              if (value == 'gallery') {
                final images = chatController.messages
                    .where(
                      (final m) =>
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
                    builder: (_) => CalendarScreen(
                      chatProvider: widget.chatController,
                    ), // ✅ DDD: ETAPA 3 - Usar ChatController directamente
                  ),
                );
              } else if (value == 'export_json') {
                try {
                  final jsonStr = await BackupUtils.exportChatPartsToJson(
                    profile: widget.chatController.profile!,
                    messages: widget.chatController.messages,
                    events: widget.chatController.events,
                    timeline: widget.chatController.timeline,
                  );
                  final navCtx = navigatorKey.currentContext;
                  if (navCtx == null) return;
                  _showExportDialog(jsonStr, widget.chatController);
                } on Exception catch (e) {
                  Log.e(
                    'Error al exportar biografía',
                    tag: 'CHAT_SCREEN',
                    error: e,
                  );
                  // showErrorDialog resolves context via navigatorKey internally
                  showErrorDialog(e.toString());
                }
              } else if (value == 'import_json') {
                await _showImportDialog(widget.chatController);
              } else if (value == 'local_backup') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                await showAppDialog<void>(
                  builder: (final ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: LocalBackupDialog(
                      requestExportJson: () async {
                        return await BackupUtils.exportChatPartsToJson(
                          profile: widget.chatController.profile!,
                          messages: widget.chatController.messages,
                          events: widget.chatController.events,
                          timeline: widget.chatController.timeline,
                        );
                      },
                      onImportedJson: (final imported) async {
                        await widget.chatController.applyChatExport(
                          imported.toJson(),
                        );
                        if (mounted) setState(() {});
                      },
                      onImportError: (final err) {
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
                  await widget.chatController.dataController
                      .regenerateAppearance();
                } on Exception catch (e) {
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
                  await widget.chatController.dataController
                      .generateAvatarFromAppearance();
                } on Exception catch (e) {
                  if (!mounted) return;
                  showErrorDialog('Error al generar avatar:\n$e');
                } finally {
                  if (mounted) {
                    setState(() => _isRegeneratingAppearance = false);
                  }
                }
              } else if (value == 'logout') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                final confirm = await showAppDialog<bool>(
                  builder: (final ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    title: const Text(
                      'Cerrar sesión',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    content: const Text(
                      '¿Seguro que quieres cerrar sesión? Se borrarán todos los datos de la app incluyendo conversaciones, configuraciones y credenciales guardadas.\n\nEsta acción no se puede deshacer.',
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
                          'Cerrar sesión',
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
                  } on Exception catch (e) {
                    if (!mounted) return;
                    _showErrorDialog(e.toString());
                  }
                }
              } else if (value == 'backup_diagnostics') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                await showAppDialog<void>(
                  builder: (final ctx) => BackupDiagnosticsDialog(
                    chatProvider: widget.chatController,
                  ), // ✅ DDD: ETAPA 3 - ChatController directo
                );
              } else if (value == 'select_model') {
                if (_loadingModels) return;
                setState(() => _loadingModels = true);
                List<String> models = [];
                try {
                  models = await widget.chatController.getAllModels();
                } on Exception catch (e) {
                  if (!mounted) return;
                  _showErrorDialog('Error al obtener modelos:\n$e');
                  setState(() => _loadingModels = false);
                  return;
                }
                setState(() => _loadingModels = false);
                final current = widget.chatController.selectedModel;
                final defaultModel = Config.getDefaultTextModel();
                final initialModel =
                    current ??
                    (models.contains(defaultModel)
                        ? defaultModel
                        : (models.isNotEmpty ? models.first : null));
                final selected = await _showModelSelectionDialog(
                  models,
                  initialModel,
                  widget.chatController,
                );
                if (!mounted) return;
                _setSelectedModel(selected, current, widget.chatController);
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
                  fileService: _fileUIService,
                  synthesizeTts:
                      (
                        final phrase, {
                        required final voice,
                        required final language,
                        required final forDialogDemo,
                      }) async {
                        try {
                          final file = await widget.chatController.audioService
                              .synthesizeTts(
                                phrase,
                                voice: voice,
                                languageCode: language,
                                forDialogDemo: forDialogDemo,
                              );
                          return file; // Ya es String?, no necesita conversión
                        } on Exception {
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
                  builder: (final ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: _buildGoogleDriveBackupDialog(
                      widget.chatController,
                    ),
                  ),
                );
                // ChatProvider will be updated by the dialog; no local refresh needed.
              } else if (value == 'backup_status') {
                final navCtx = navigatorKey.currentContext;
                if (navCtx == null) return;
                await showAppDialog<void>(
                  builder: (final ctx) => AlertDialog(
                    backgroundColor: Colors.black,
                    content: _buildGoogleDriveBackupDialog(
                      widget.chatController,
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
        child: Column(
          children: [
            Expanded(
              child: Builder(
                builder: (final ctx) {
                  final filteredMessages = chatController.messages
                      .where(
                        (final m) =>
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
                    itemBuilder: (final context, final index) {
                      if (index == reversedShown.length && hasMore) {
                        // slot para indicador de carga (mensajes antiguos)
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CyberpunkLoader(message: 'LOADING...'),
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
                            .any((final m) => m.sender == MessageSender.user);
                      }
                      return ChatBubble(
                        message: message,
                        isLastUserMessage: isLastUserMessage,
                        imageDir: _imageDir,
                        fileService: _fileUIService,
                        onRetry: () async {
                          try {
                            chatController.messageController
                                .retryLastFailedMessage(); // ✅ DDD: Método compatible con ChatProviderAdapter
                          } on Exception catch (_) {}
                        },
                        onImageTap: () async {
                          try {
                            final images = chatController.messages
                                .where(
                                  (final m) =>
                                      m.isImage &&
                                      m.image != null &&
                                      m.image!.url != null &&
                                      m.image!.url!.isNotEmpty,
                                )
                                .toList();
                            final idx = images.indexWhere(
                              (final m) => m.image?.url == message.image?.url,
                            );
                            if (idx != -1) {
                              ExpandableImageDialog.show(
                                images,
                                idx,
                                imageBasePath: _imageDir?.path,
                                fileUIService: _fileUIService,
                                onImageDeleted: _handleImageDeleted,
                              );
                            }
                          } on Exception catch (_) {}
                        },
                        isAudioPlaying: (final msg) =>
                            chatController.isPlaying(msg),
                        onToggleAudio: (final msg) =>
                            chatController.audioController.togglePlayAudio(msg),
                        getAudioPosition: () => chatController.playingPosition,
                        getAudioDuration: () => chatController.playingDuration,
                      );
                    },
                  );
                },
              ),
            ),
            if (chatController.isSendingImage)
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
                      child: const Row(
                        children: [
                          Icon(
                            Icons.photo_camera,
                            color: AppColors.secondary,
                            size: 22,
                          ),
                          SizedBox(width: 10),
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
            else if (chatController.isSendingAudio)
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
                      child: const Row(
                        children: [
                          Icon(
                            Icons.mic_external_on,
                            color: AppColors.secondary,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Row(
                            children: [
                              ThreeDotsIndicator(color: AppColors.secondary),
                              SizedBox(width: 8),
                              Text(
                                'Grabando nota de voz...',
                                style: TextStyle(
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
            else if (chatController.isTyping)
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
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.keyboard_alt,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          TypingAnimation(),
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
                    scheduleSend:
                        (final text, {final image, final imageMimeType}) async {
                          chatController.messageController.scheduleSendMessage(
                            text,
                            image: image,
                            imageMimeType: imageMimeType,
                          );
                          return Future.value();
                        },
                    startRecording: () async =>
                        await chatController.audioController.startRecording(),
                    stopAndSendRecording: () async => await chatController
                        .audioController
                        .stopAndSendRecording(),
                    cancelRecording: () async =>
                        await chatController.audioController.cancelRecording(),
                    onUserTyping: (final text) =>
                        chatController.messageController.onUserTyping(text),
                  ),
              fileService: _fileUIService,
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
                  } on Exception catch (_) {
                    try {
                      _scrollController.jumpTo(0.0);
                    } on Exception catch (_) {}
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
    } on Exception catch (_) {
      return null;
    }
  }

  Future<String> _loadActiveAudioProvider() async {
    try {
      // getSelectedAudioProvider() ya normaliza y aplica mapeos como 'gemini'->'google'
      return await PrefsUtils.getSelectedAudioProvider();
    } on Exception catch (_) {
      return 'google';
    }
  }

  /// Helper para crear PopupMenuItems con el patrón estándar de icono + texto
  PopupMenuItem<String> _buildMenuItem({
    required final String value,
    required final IconData icon,
    required final String text,
    final bool enabled = true,
    final Color? color,
  }) {
    final itemColor = color ?? AppColors.primary;
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, color: itemColor, size: 20),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: itemColor)),
        ],
      ),
    );
  }

  /// Helper para crear GoogleDriveBackupDialog con callbacks estandarizados
  GoogleDriveBackupDialog _buildGoogleDriveBackupDialog(
    final ChatController provider,
  ) {
    return BackupDialogFactory.fromChatController(provider);
  }

  @override
  void dispose() {
    try {
      _scrollController.dispose();
    } on Exception catch (_) {}
    try {
      if (_chatProviderListener != null) {
        final provider = widget.chatController;
        provider.removeListener(_chatProviderListener!);
      }
    } on Exception catch (_) {}
    try {
      _chatInputController?.dispose();
    } on Exception catch (_) {}
    super.dispose();
  }
}
