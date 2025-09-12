import 'package:ai_chan/core/cache/cache_service.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/core/di.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_config_loader.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';
import 'package:ai_chan/shared/utils/dialog_utils.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/utils/voice_display_utils.dart';
import 'package:ai_chan/shared/application/services/file_ui_service.dart';
import 'package:ai_chan/shared/domain/interfaces/audio_playback_service.dart';
import 'package:ai_chan/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart' show AndroidIntent;

import '../../domain/interfaces/i_tts_voice_management_service.dart';
import 'package:ai_chan/shared/constants/app_colors.dart';

typedef SynthesizeTtsFn =
    Future<String?> Function(
      String phrase, {
      required String voice,
      required String language,
      required bool forDialogDemo,
    });

class TtsConfigurationDialog extends StatefulWidget {
  const TtsConfigurationDialog({
    super.key,
    required this.fileService,
    this.userLangCodes,
    this.aiLangCodes,
    this.synthesizeTts,
    this.onSettingsChanged,
  });
  final List<String>? userLangCodes;
  final List<String>? aiLangCodes;
  final FileUIService fileService;
  // Callback that performs TTS synthesis for dialog demos. If null, play demo is disabled.
  final SynthesizeTtsFn? synthesizeTts;
  // Callback to notify the caller that settings changed and it may want to refresh UI
  final VoidCallback? onSettingsChanged;

  @override
  State<TtsConfigurationDialog> createState() => _TtsConfigurationDialogState();

  /// Helper para mostrar este widget dentro de un AppAlertDialog.
  static Future<bool?> showAsDialog(
    final BuildContext ctx, {
    required final FileUIService fileService,
    final List<String>? userLangCodes,
    final List<String>? aiLangCodes,
    final SynthesizeTtsFn? synthesizeTts,
    final VoidCallback? onSettingsChanged,
  }) {
    final stateKey = GlobalKey<_TtsConfigurationDialogState>();
    return showAppDialog<bool>(
      builder: (final context) => AppAlertDialog(
        title: const Text('Configuración de TTS'),
        headerActions: [
          // Action that triggers the internal refresh logic via the state key
          IconButton(
            tooltip: 'Actualizar voces',
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () {
              stateKey.currentState?.refreshVoices(forceRefresh: true);
            },
          ),
        ],
        content: TtsConfigurationDialog(
          key: stateKey,
          fileService: fileService,
          userLangCodes: userLangCodes,
          aiLangCodes: aiLangCodes,
          synthesizeTts: synthesizeTts,
          onSettingsChanged: onSettingsChanged,
        ),
      ),
    );
  }
}

class _TtsConfigurationDialogState extends State<TtsConfigurationDialog>
    with WidgetsBindingObserver {
  String _selectedProvider = ''; // Se inicializará dinámicamente
  bool _isLoading = false;

  // 🚀 SISTEMA DINÁMICO: Mapas por provider ID en lugar de variables específicas
  final Map<String, List<Map<String, dynamic>>> _voicesByProvider = {};
  final List<Map<String, dynamic>> _androidNativeVoices =
      []; // 🚀 PROVIDERS DINÁMICOS: Lista de providers disponibles
  List<String> _availableProviders = [];
  Map<String, String> _providerDisplayNames = {};

  String? _selectedVoice;
  String? _selectedModel;
  int _cacheSize = 0;

  // 🎵 Instancia persistente de audio para evitar múltiples players
  final AudioPlaybackService _audioPlayer = getAudioPlaybackService();

  // Application service for voice management - using DI factory
  final ITtsVoiceManagementService _voiceService =
      getTtsVoiceManagementService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 🚀 SISTEMA DINÁMICO: Cargar providers disponibles primero
    _loadAvailableProviders();

    _loadSettings();
    _checkAndroidNative();

    // 🚀 CARGAR VOCES: Inicializar providers disponibles
    _loadInitialVoices();
    _loadCacheSize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Limpiar instancia persistente de audio
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(final AppLifecycleState state) {
    // Al volver (resumed) intentamos refrescar las voces nativas automáticamente
    if (state == AppLifecycleState.resumed &&
        Platform.isAndroid &&
        _selectedProvider == 'android_native') {
      _refreshNativeVoices();
    }
  }

  Future<void> _refreshNativeVoices() async {
    setState(() => _isLoading = true);
    try {
      // Use application service instead of direct infrastructure access
      final voices = await _voiceService.getAndroidNativeVoices(
        userLangCodes: widget.userLangCodes,
        aiLangCodes: widget.aiLangCodes,
      );
      setState(() {
        _androidNativeVoices.clear();
        _androidNativeVoices.addAll(voices);
        _isLoading = false;
      });
      Log.d(
        'DEBUG TTS: Voces nativas actualizadas: ${voices.length}',
        tag: 'TTS_DIALOG',
      );
      if (mounted) {
        showAppSnackBar('Voces nativas detectadas: ${voices.length}');
      }
    } on Exception catch (e) {
      Log.d(
        'DEBUG TTS: Error refrescando voces nativas: $e',
        tag: 'TTS_DIALOG',
      );
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Método público que puede ser invocado desde la cabecera (header action)
  /// para forzar la recarga de voces.
  Future<void> refreshVoices({final bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final manager = AIProviderManager.instance;
      final provider = manager.providers[_selectedProvider];

      if (provider?.supportsCapability(AICapability.audioGeneration) == true) {
        if (_selectedProvider == 'android_native') {
          await _refreshNativeVoices();
        } else {
          await _loadVoices(forceRefresh: forceRefresh);
        }
      }
      showAppSnackBar('Voces actualizadas');
    } on Exception catch (e) {
      showAppSnackBar('Error al actualizar voces: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final savedProvider = await PrefsUtils.getSelectedAudioProvider();
      // getPreferredVoice centraliza la lógica de resolución por provider + fallback
      final providerVoice = await PrefsUtils.getPreferredVoice();
      final selModel = await PrefsUtils.getSelectedModel();
      setState(() {
        _selectedProvider = savedProvider;
        _selectedVoice = providerVoice.isEmpty ? null : providerVoice;
        _selectedModel = selModel ?? Config.getDefaultTextModel();
      });
    } on Exception catch (_) {
      // ✅ YAML: Usar configuración YAML como fallback
      try {
        final defaultProvider =
            AIProviderConfigLoader.getDefaultAudioProvider();
        setState(() {
          _selectedProvider = defaultProvider.toLowerCase();
          _selectedVoice = null;
          _selectedModel = Config.getDefaultTextModel();
        });
      } on Exception catch (_) {
        // Obtener el primer provider disponible dinámicamente
        final manager = AIProviderManager.instance;
        final availableProviders = manager.getProvidersByCapability(
          AICapability.audioGeneration,
        );

        setState(() {
          _selectedProvider = availableProviders.isNotEmpty
              ? availableProviders.first
              : '';
          _selectedVoice = null;
          _selectedModel = Config.getDefaultTextModel();
        });
      }
    }
  }

  Future<void> _checkAndroidNative() async {
    // Detectar plataforma y comprobar disponibilidad nativa solo en Android
    if (Platform.isAndroid) {
      final available = _voiceService.isAndroidNativeTtsAvailable();
      // Note: Android native availability is now handled by dynamic provider system

      // Si está disponible, intentar cargar/filtrar las voces nativas inmediatamente
      if (available) {
        await _refreshNativeVoices();
      }
    }
  }

  Future<void> _openAndroidTtsSettings() async {
    if (!Platform.isAndroid) return;

    // Intent fallbacks: algunos fabricantes o versiones pueden no aceptar
    // directamente ACTION_TTS_SETTINGS; probamos varias opciones para abrir
    // la pantalla de ajustes relevante en la mayoría de dispositivos.
    final attempts = [
      {'action': 'android.settings.TTS_SETTINGS', 'package': null},
      {
        'action': 'android.settings.TTS_SETTINGS',
        'package': 'com.android.settings',
      },
      {
        'action': 'android.settings.TTS_SETTINGS',
        'package': 'com.google.android.tts',
      },
      // Intent para abrir la pantalla de instalación de datos TTS (puede iniciar el flujo de descarga)
      {'action': 'android.speech.tts.engine.INSTALL_TTS_DATA', 'package': null},
      // Abrir la pantalla de info de la app Google TTS para que el usuario pueda acceder a sus ajustes
      {
        'action': 'android.settings.APPLICATION_DETAILS_SETTINGS',
        'package': null,
        'data': 'package:com.google.android.tts',
      },
      {'action': 'android.settings.SOUND_SETTINGS', 'package': null},
      {'action': 'android.settings.SETTINGS', 'package': null},
    ];

    for (final a in attempts) {
      try {
        final action = a['action'] as String;
        final package = a['package'];
        final data = a['data'];
        final intent = AndroidIntent(
          action: action,
          package: package,
          data: data,
        );
        await intent.launch();
        return;
      } on Exception catch (e) {
        Log.d('DEBUG TTS: Intent ${a['action']} falló: $e', tag: 'TTS_DIALOG');
        // seguir con el siguiente intento
      }
    }

    // Si fallaron todos los intent, mostrar instrucción al usuario
    Log.d(
      'DEBUG TTS: No se pudo abrir ninguna pantalla de ajustes',
      tag: 'TTS_DIALOG',
    );
    showAppSnackBar(
      'Abre Ajustes → Idioma y entrada → Salida de texto a voz para instalar voces',
    );
  }

  Future<void> _installTtsData() async {
    if (!Platform.isAndroid) return;

    try {
      final intent = const AndroidIntent(
        action: 'android.speech.tts.engine.INSTALL_TTS_DATA',
      );
      await intent.launch();
    } on Exception catch (e) {
      Log.d('DEBUG TTS: INSTALL_TTS_DATA intent falló: $e', tag: 'TTS_DIALOG');
      showAppSnackBar(
        'No se pudo iniciar la instalación de datos TTS. Abre Ajustes → Salida de texto a voz',
      );
    }
  }

  /// Obtiene el nivel de calidad legible de una voz Neural/WaveNet
  String _getVoiceQualityLevel(final Map<String, dynamic> voice) {
    // Extract quality from voice name or properties
    final voiceName = voice['name'] as String? ?? '';
    final naturalSampleRateHertz = voice['naturalSampleRateHertz'] as int? ?? 0;

    // Determine quality based on voice name patterns
    if (voiceName.contains('WaveNet')) {
      return 'WaveNet';
    } else if (voiceName.contains('Neural2')) {
      return 'Neural2';
    } else if (voiceName.contains('Polyglot')) {
      return 'Polyglot';
    } else if (voiceName.contains('Journey')) {
      return 'Journey';
    } else if (voiceName.contains('Studio')) {
      return 'Studio';
    } else if (voiceName.contains('Neural')) {
      return 'Neural';
    } else if (voiceName.contains('Standard')) {
      return 'Standard';
    } else if (naturalSampleRateHertz >= 24000) {
      return 'High Quality';
    } else {
      return 'Standard';
    }
  }

  /// 🚀 SISTEMA DINÁMICO: Cargar providers de TTS disponibles
  Future<void> _loadAvailableProviders() async {
    try {
      final manager = AIProviderManager.instance;
      await manager.initialize();

      // Obtener providers con capacidad de audio generation (TTS)
      final ttsProviders = manager.getProvidersByCapability(
        AICapability.audioGeneration,
      );

      _availableProviders.clear();
      _providerDisplayNames.clear();

      // Android native siempre primero si está disponible
      if (Platform.isAndroid) {
        _availableProviders.add('android_native');
        _providerDisplayNames['android_native'] =
            AIProviderConfigLoader.getTtsProviderDisplayName('android_native');
      }

      // 🚀 YAML: Obtener provider IDs dinámicamente
      for (final providerId in ttsProviders) {
        if (!_availableProviders.contains(providerId)) {
          _availableProviders.add(providerId);
          // 🚀 YAML: Usar configuración dinámica del YAML
          _providerDisplayNames[providerId] =
              AIProviderConfigLoader.getTtsProviderDisplayName(providerId);
        }
      }
    } on Exception catch (e) {
      Log.e('Error cargando providers: $e', tag: 'TTS_DIALOG');
      // 🚀 YAML: Fallback dinámico usando configuración
      final defaultProvider = AIProviderConfigLoader.getDefaultAudioProvider();
      _availableProviders = Platform.isAndroid
          ? ['android_native', defaultProvider]
          : [defaultProvider];

      // 🚀 YAML: Cargar nombres desde configuración en lugar de hardcodear
      _providerDisplayNames = {};
      for (final providerId in _availableProviders) {
        _providerDisplayNames[providerId] =
            AIProviderConfigLoader.getTtsProviderDisplayName(providerId);
      }
    }
  }

  /// 🚀 CARGAR VOCES: Cargar voces para providers iniciales
  Future<void> _loadInitialVoices() async {
    for (final providerId in _availableProviders) {
      if (providerId == 'android_native') {
        // android_native se carga por separado en _checkAndroidNative
        continue;
      }

      // 🚀 DINÁMICO: Cargar voces usando método específico por provider
      await _loadVoicesForProvider(providerId);
    }
  }

  /// 🚀 DINÁMICO: Cargar voces para un provider específico
  Future<void> _loadVoicesForProvider(final String providerId) async {
    try {
      // 🚀 SISTEMA DINÁMICO: Cargar voces con sistema dinámico para todos los providers
      await _loadProviderVoicesDynamically(providerId);
    } on Exception catch (e) {
      Log.e('Error loading voices for provider $providerId: $e');
      _voicesByProvider[providerId] = [];
    }
  }

  /// 🚀 DINÁMICO: Cargar voces dinámicamente para cualquier provider
  Future<void> _loadProviderVoicesDynamically(final String providerId) async {
    setState(() => _isLoading = true);
    try {
      final manager = AIProviderManager.instance;
      await manager.initialize();

      final allProviders = manager.providers;
      final targetProvider = allProviders[providerId];

      if (targetProvider != null) {
        // Cast to concrete provider para acceder a getAvailableVoices()
        final concreteProvider = targetProvider as dynamic;
        final voices = await concreteProvider.getAvailableVoices() as List;

        _voicesByProvider[providerId] = voices
            .map(
              (final voice) => {
                'name': voice.name ?? '',
                'description': voice.name ?? '',
                'languageCodes': voice.languageCodes ?? <String>[],
                'gender': voice.gender ?? 'Desconocido',
              },
            )
            .toList()
            .cast<Map<String, dynamic>>();
      } else {
        Log.w('Provider $providerId not found');
        _voicesByProvider[providerId] = [];
      }
    } on Exception catch (e) {
      Log.e('Error loading voices for provider $providerId: $e');
      _voicesByProvider[providerId] = [];
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 🚀 YAML: Obtener subtítulo del provider desde configuración
  String _getProviderSubtitle(final String providerId) {
    switch (providerId) {
      case 'android_native':
        // Usar template del YAML con reemplazo dinámico
        final template = AIProviderConfigLoader.getTtsProviderSubtitleTemplate(
          providerId,
        );
        return template.replaceAll(
          '{voice_count}',
          '${_androidNativeVoices.length}',
        );
      default:
        // 🚀 YAML: Sistema unificado para todos los providers
        if (_isProviderConfigured(providerId)) {
          final template =
              AIProviderConfigLoader.getTtsProviderSubtitleTemplate(providerId);
          return template.replaceAll(
            '{voice_count}',
            '${_voicesByProvider[providerId]?.length ?? 0}',
          );
        } else {
          return AIProviderConfigLoader.getTtsProviderNotConfiguredSubtitle(
            providerId,
          );
        }
    }
  }

  /// 🚀 SISTEMA DINÁMICO: Verificar si provider está configurado
  bool _isProviderConfigured(final String providerId) {
    switch (providerId) {
      case 'android_native':
        return Platform.isAndroid;
      default:
        // Para providers dinámicos, asumimos que están disponibles si están en la lista
        return _availableProviders.contains(providerId);
    }
  }

  /// 🚀 SISTEMA DINÁMICO: Verificar si provider está habilitado
  bool _isProviderEnabled(final String providerId) {
    switch (providerId) {
      case 'android_native':
        return Platform.isAndroid && _androidNativeVoices.isNotEmpty;
      default:
        // Para providers dinámicos, usar la función de configuración
        return _isProviderConfigured(providerId);
    }
  }

  Future<void> _loadVoices({final bool forceRefresh = false}) async {
    // 🚀 DINÁMICO: Usar sistema dinámico para cargar voces del proveedor seleccionado
    if (_selectedProvider.isEmpty) return;

    Log.d(
      'DEBUG TTS: _loadVoices iniciado para $_selectedProvider - forceRefresh: $forceRefresh',
      tag: 'TTS_DIALOG',
    );
    try {
      // If caller requested forceRefresh, clear cached voices to force re-download
      if (forceRefresh) {
        try {
          await _voiceService.clearVoicesCache();
          Log.d(
            'DEBUG TTS: ClearAllVoicesCache invoked due to forceRefresh',
            tag: 'TTS_DIALOG',
          );
        } on Exception catch (e) {
          Log.d('DEBUG TTS: clearAllVoicesCache failed: $e', tag: 'TTS_DIALOG');
        }
      }

      await _loadProviderVoicesDynamically(_selectedProvider);
      Log.d(
        'DEBUG TTS: Voices loaded for $_selectedProvider',
        tag: 'TTS_DIALOG',
      );
    } on Exception catch (e) {
      Log.d('DEBUG TTS: Error loading voices: $e', tag: 'TTS_DIALOG');
      if (mounted) {
        setState(() {
          _voicesByProvider[_selectedProvider] = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCacheSize() async {
    final size = await CacheService.getCacheSize();
    setState(() => _cacheSize = size);
  }

  Future<void> _saveSettings() async {
    try {
      await PrefsUtils.setSelectedAudioProvider(_selectedProvider);
      if (_selectedVoice != null) {
        await PrefsUtils.setSelectedVoiceForProvider(
          _selectedProvider,
          _selectedVoice!,
        );
      }
      if (_selectedModel != null) {
        await PrefsUtils.setSelectedModel(_selectedModel!);
      }
    } on Exception catch (_) {}
  }

  String _getProviderDisplayName(final String providerId) {
    // 🚀 YAML: Usar configuración del YAML en lugar de hardcodeo
    return AIProviderConfigLoader.getTtsProviderDisplayName(providerId);
  }

  String _getProviderDescription(final String providerId) {
    // 🚀 YAML: Usar configuración del YAML en lugar de hardcodeo
    return AIProviderConfigLoader.getTtsProviderDescription(providerId);
  }

  Future<void> _clearCache() async {
    final confirmed = await showAppDialog<bool>(
      builder: (final context) => AlertDialog(
        title: const Text('Limpiar Caché'),
        content: Text(
          '¿Eliminar ${CacheService.formatCacheSize(_cacheSize)} de audio en caché?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _voiceService.clearAudioCache();
      await _voiceService.clearVoicesCache();
      await _loadCacheSize();

      if (mounted) {
        showAppSnackBar(
          'Caché limpiado exitosamente',
          preferRootMessenger: true,
        );
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    // Detectar si este widget está siendo mostrado dentro de un diálogo
    final isInDialog =
        ModalRoute.of(context)?.settings.name == null &&
        Navigator.of(context).canPop() &&
        // heurística: si no hay un Scaffold ancestor asumimos diálogo embebido
        Scaffold.maybeOf(context) == null;

    // Construir el cuerpo principal que puede ser embebido dentro de AppAlertDialog
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Proveedor:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // 🚀 SISTEMA DINÁMICO: Selector de proveedor basado en providers disponibles
            ..._availableProviders.map((final providerId) {
              return Column(
                children: [
                  ListTile(
                    leading: _selectedProvider == providerId
                        ? const Icon(Icons.radio_button_checked)
                        : const Icon(Icons.radio_button_unchecked),
                    title: Text(
                      _providerDisplayNames[providerId] ?? providerId,
                    ),
                    subtitle: Text(_getProviderSubtitle(providerId)),
                    enabled: _isProviderEnabled(providerId),
                    onTap: _isProviderEnabled(providerId)
                        ? () async {
                            setState(() => _selectedProvider = providerId);
                            await _saveSettings();
                            // Forzar refresco para providers específicos
                            if (providerId == 'android_native') {
                              await _refreshNativeVoices();
                            }
                          }
                        : null,
                  ),
                  if (providerId != _availableProviders.last)
                    const SizedBox(height: 8),
                ],
              );
            }),

            const SizedBox(height: 12),
            const Divider(),

            // Nota: el control de actualización ahora está en la cabecera (icono refresh)
            const Text('Voces:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Expanded(
              child: _isLoading
                  ? const CyberpunkLoader(
                      message: 'LOADING VOICE MODELS...',
                      showProgressBar: true,
                    )
                  : _buildVoiceList(),
            ),

            const SizedBox(height: 12),

            // Info section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.secondary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.secondary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Proveedor: ${_getProviderDisplayName(_selectedProvider)}${_selectedVoice != null ? ' ($_selectedVoice)' : ''}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getProviderDescription(_selectedProvider),
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  if (_cacheSize > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.cached,
                              color: AppColors.secondary,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Caché: ${CacheService.formatCacheSize(_cacheSize)}',
                              style: const TextStyle(
                                color: AppColors.secondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        // Botón limpiar caché en la misma línea
                        ElevatedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Limpiar'),
                          onPressed: _cacheSize > 0 ? _clearCache : null,
                        ),
                      ],
                    ),
                  ] else ...[
                    // Si no hay caché, mostrar el botón solo
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Limpiar'),
                        onPressed: _cacheSize > 0 ? _clearCache : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    // Si estamos dentro de un diálogo, devolver solo el contenido; el AppAlertDialog
    // se encargará de mostrar la cabecera con el botón de cerrar/volver.
    if (isInDialog) return content;

    // En caso contrario, mantener la pantalla completa existente (Scaffold con AppBar)
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.primary,
        elevation: 0,
        title: Row(
          children: [
            const Expanded(
              child: Text(
                'Configuración de TTS',
                style: TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar voces',
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CyberpunkLoader(message: 'SYNC...'),
                    )
                  : const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: () async {
                // Refresh according to current provider
                setState(() => _isLoading = true);
                try {
                  final manager = AIProviderManager.instance;
                  final provider = manager.providers[_selectedProvider];

                  if (provider?.supportsCapability(
                        AICapability.audioGeneration,
                      ) ==
                      true) {
                    if (_selectedProvider == 'android_native') {
                      // Refresh native voices (fetch list) when native provider is selected
                      await _refreshNativeVoices();

                      // Debug: dump JSON for requested language codes to help inspect raw plugin output
                      try {
                        final effectiveUserCodes =
                            widget.userLangCodes ?? <String>[];
                        final effectiveAiCodes =
                            widget.aiLangCodes ?? <String>[];
                        var codes = [
                          ...effectiveUserCodes,
                          ...effectiveAiCodes,
                        ];
                        if (codes.isEmpty) codes = ['es-ES'];
                        for (final c in codes) {
                          try {
                            // Debug functionality removed - would need to be implemented in application service
                            Log.d(
                              'DEBUG TTS: Would dump voices for language $c',
                              tag: 'TTS_DIALOG',
                            );
                          } on Exception catch (e) {
                            Log.d(
                              'DEBUG TTS: Debug dump failed for $c: $e',
                              tag: 'TTS_DIALOG',
                            );
                          }
                        }
                      } on Exception catch (e) {
                        Log.d(
                          'DEBUG TTS: Error in debug dump: $e',
                          tag: 'TTS_DIALOG',
                        );
                      }
                    } else {
                      // For other providers, use generic voice loading
                      await _loadVoices(forceRefresh: true);
                    }
                  }
                  showAppSnackBar('Voces actualizadas');
                } on Exception catch (e) {
                  showAppSnackBar(
                    'Error al actualizar voces: $e',
                    isError: true,
                  );
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
      ),
      body: content,
    );
  }

  Widget _buildVoiceList() {
    List<Map<String, dynamic>> voices = [];

    // 🚀 DINÁMICO: Usar approach unificado para todos los providers
    if (_selectedProvider == 'android_native') {
      // Ya se filtraron las voces nativas en _refreshNativeVoices usando
      // los códigos proporcionados por widget.userLangCodes y widget.aiLangCodes.
      voices = List<Map<String, dynamic>>.from(_androidNativeVoices);
    } else {
      // Para todos los otros providers, usar el mapa dinámico
      voices = _voicesByProvider[_selectedProvider] ?? [];
    }

    if (voices.isEmpty) {
      // Mostrar guía paso a paso cuando el proveedor nativo no tiene voces instaladas
      if (_selectedProvider == 'android_native' && Platform.isAndroid) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Guía rápida para instalar voces nativas',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Paso 1
              Card(
                color: Colors.grey.shade900,
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.settings, color: AppColors.secondary),
                  ),
                  title: const Text(
                    'Paso 1: Abrir ajustes TTS',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                  subtitle: const Text(
                    'Abre la pantalla de salida de texto a voz del sistema',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: _openAndroidTtsSettings,
                    child: const Text('Abrir'),
                  ),
                ),
              ),

              // Paso 2
              Card(
                color: Colors.grey.shade900,
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.download, color: AppColors.secondary),
                  ),
                  title: const Text(
                    'Paso 2: Instalar paquetes de voz',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                  subtitle: const Text(
                    'En Ajustes > Salida de texto a voz instala paquetes o selecciona un motor (ej. Google TTS)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: _installTtsData,
                    child: const Text('Instalar'),
                  ),
                ),
              ),

              // Paso 3
              Card(
                color: Colors.grey.shade900,
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.refresh, color: AppColors.secondary),
                  ),
                  title: const Text(
                    'Paso 3: Volver y actualizar',
                    style: TextStyle(color: AppColors.secondary),
                  ),
                  subtitle: const Text(
                    'Cuando hayas instalado voces, vuelve a la app y actualiza la lista',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        await _refreshNativeVoices();
                        showAppSnackBar('Actualización completada');
                      } on Exception catch (e) {
                        showAppSnackBar(
                          'Error al actualizar: $e',
                          isError: true,
                        );
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                    child: const Text('Actualizar'),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              const Text(
                'Si sigues sin ver voces, revisa que tienes un motor TTS instalado (p. ej. Google Text-to-Speech) y que los paquetes de idioma estén descargados.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        );
      }

      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'No hay voces disponibles para este proveedor',
          style: TextStyle(color: AppColors.primary),
        ),
      );
    }

    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: voices.length,
        itemBuilder: (final context, final index) {
          final voice = voices[index];
          final voiceName = voice['name'] as String? ?? 'Sin nombre';

          String displayName = voiceName;
          String subtitle = '';

          // Use the provided synthesizeTts callback to generate demo audio

          if (_selectedProvider == 'android_native') {
            // Simple voice info formatting
            final locale = voice['locale'] as String? ?? '';
            final quality = voice['quality'] as String? ?? '';
            subtitle = locale.isNotEmpty
                ? '$locale${quality.isNotEmpty ? ' · $quality' : ''}'
                : 'Native voice';
          } else {
            // 🚀 FORMATO DINÁMICO: Usar lógica específica por provider detectada dinámicamente
            final hasGoogleFormatting =
                voice.containsKey('languageCode') && voice.containsKey('name');
            if (hasGoogleFormatting) {
              // Usar nombre amigable para voces con formato Google
              displayName = VoiceDisplayUtils.getGoogleVoiceFriendlyName(voice);
              final originalSubtitle = VoiceDisplayUtils.getVoiceSubtitle(
                voice,
              );
              final quality = _getVoiceQualityLevel(voice);
              // Evitar duplicados: si el subtítulo ya contiene la calidad (por ejemplo 'Neural'), no la añadimos de nuevo.
              if (originalSubtitle.toLowerCase().contains(
                quality.toLowerCase(),
              )) {
                subtitle = originalSubtitle;
              } else if (originalSubtitle.isEmpty) {
                subtitle = quality;
              } else {
                // Usar ' · ' para mantener consistencia con VoiceDisplayUtils
                subtitle = '$originalSubtitle · $quality';
              }
            } else {
              // 🚀 FORMATO DINÁMICO: Para otros providers (OpenAI, XAI, etc)
              final gender = voice['gender'] as String? ?? '';
              final parts = <String>[];
              if (gender.isNotEmpty) parts.add(gender);
              parts.add('Multilingüe');

              displayName = voiceName.isNotEmpty
                  ? '${voiceName[0].toUpperCase()}${voiceName.substring(1)}'
                  : voiceName;
              subtitle = parts.join(' · ');
            }
          }

          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            leading: _selectedVoice == voiceName
                ? const Icon(
                    Icons.radio_button_checked,
                    size: 20,
                    color: AppColors.secondary,
                  )
                : const Icon(
                    Icons.radio_button_unchecked,
                    size: 20,
                    color: AppColors.primary,
                  ),
            title: Text(
              displayName,
              style: const TextStyle(color: AppColors.primary),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            trailing: SizedBox(
              width: 96,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.play_arrow,
                      color: AppColors.secondary,
                    ),
                    tooltip: 'Escuchar demo',
                    onPressed: () async {
                      final phrase =
                          'Hola, soy tu asistente con la voz $voiceName';
                      showAppSnackBar('Buscando audio en caché...');
                      try {
                        String lang = 'es-ES';
                        if (voice['languageCodes'] is List &&
                            (voice['languageCodes'] as List).isNotEmpty) {
                          lang = (voice['languageCodes'] as List)
                              .cast<String>()
                              .first;
                        }

                        if (widget.synthesizeTts == null) {
                          showAppSnackBar(
                            'Proveedor de audio no disponible',
                            isError: true,
                          );
                          return;
                        }

                        // 🚀 SISTEMA DINÁMICO: Usar selectedProvider directamente
                        final providerKey = _selectedProvider;

                        // Comprobar caché primero
                        // For dialog demos, prefer cache (dialog-scoped). Use a
                        // specific provider key to avoid mixing with message cache.
                        final cachedFile =
                            await CacheService.getCachedAudioFile(
                              text: phrase,
                              voice: voiceName,
                              languageCode: lang,
                              provider: '${providerKey}_tts_dialog',
                            );

                        final cachedFilePath = cachedFile?.path;
                        if (cachedFilePath != null) {
                          try {
                            // Debug: ensure file exists and has content before attempting to play
                            final exists = await widget.fileService.fileExists(
                              cachedFilePath,
                            );
                            final length = exists
                                ? await widget.fileService.getFileSize(
                                    cachedFilePath,
                                  )
                                : 0;
                            debugPrint(
                              '[TTS_DIALOG] Playing cached audio: path=$cachedFilePath exists=$exists length=$length',
                            );
                          } on Exception catch (e) {
                            debugPrint(
                              '[TTS_DIALOG] Failed to stat cached file: $e',
                            );
                          }

                          // Prefer explicit DeviceFileSource for local files to avoid Uri/FileProvider fallbacks
                          await _audioPlayer.play(
                            ap.DeviceFileSource(cachedFilePath),
                          );
                          // Esperar a la finalización antes de liberar el player para que se oiga el audio
                          try {
                            await _audioPlayer.onPlayerComplete.first;
                          } on Exception catch (_) {}
                          // No dispose en instancia persistente
                          await _audioPlayer.stop();
                          showAppSnackBar('Audio reproducido desde caché');
                          return;
                        }

                        showAppSnackBar('Generando audio de prueba...');

                        final file = await widget.synthesizeTts!(
                          phrase,
                          voice: voiceName,
                          language: lang,
                          forDialogDemo: true,
                        );
                        if (file != null) {
                          try {
                            final exists = await widget.fileService.fileExists(
                              file,
                            );
                            final length = exists
                                ? await widget.fileService.getFileSize(file)
                                : 0;
                            debugPrint(
                              '[TTS_DIALOG] Playing generated audio: path=$file exists=$exists length=$length',
                            );
                          } on Exception catch (e) {
                            debugPrint(
                              '[TTS_DIALOG] Failed to stat generated file: $e',
                            );
                          }

                          await _audioPlayer.play(ap.DeviceFileSource(file));
                          // Esperar a que termine la reproducción antes de liberar recursos
                          try {
                            await _audioPlayer.onPlayerComplete.first;
                          } on Exception catch (_) {}
                          // No dispose en instancia persistente
                          await _audioPlayer.stop();
                          showAppSnackBar('¡Audio reproducido!');
                        } else {
                          showAppSnackBar(
                            'No se pudo generar el audio',
                            isError: true,
                          );
                        }
                      } on Exception catch (e) {
                        showAppSnackBar(
                          'Error al reproducir voz: $e',
                          isError: true,
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: _selectedVoice == voiceName
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.secondary,
                          )
                        : const Icon(
                            Icons.circle_outlined,
                            color: AppColors.primary,
                          ),
                    tooltip: 'Seleccionar voz',
                    onPressed: () async {
                      setState(() => _selectedVoice = voiceName);
                      try {
                        await PrefsUtils.setSelectedVoiceForProvider(
                          _selectedProvider,
                          voiceName,
                        );
                        if (widget.onSettingsChanged != null) {
                          widget.onSettingsChanged!.call();
                        }
                        showAppSnackBar('Voz seleccionada: $voiceName');
                      } on Exception catch (e) {
                        showAppSnackBar(
                          'Error guardando la voz seleccionada: $e',
                          isError: true,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            onTap: () async {
              setState(() => _selectedVoice = voiceName);
              try {
                await PrefsUtils.setSelectedVoiceForProvider(
                  _selectedProvider,
                  voiceName,
                );
                if (widget.onSettingsChanged != null) {
                  widget.onSettingsChanged!.call();
                }
                showAppSnackBar('Voz seleccionada: $voiceName');
              } on Exception catch (e) {
                showAppSnackBar(
                  'Error guardando la voz seleccionada: $e',
                  isError: true,
                );
              }
            },
          );
        },
      ),
    );
  }
}
