import 'package:ai_chan/core.dart'; // Core bounded context barrel
import 'package:ai_chan/shared.dart'; // Shared bounded context barrel
import 'package:ai_chan/chat.dart'; // Chat bounded context barrel
import 'package:ai_chan/call.dart'; // Call bounded context barrel
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart' show AndroidIntent;

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
  String _selectedProvider = 'google';
  bool _isLoading = false;
  bool _androidNativeAvailable = false;
  List<Map<String, dynamic>> _googleVoices = [];
  final List<Map<String, dynamic>> _openaiVoices = [];
  final List<Map<String, dynamic>> _androidNativeVoices = [];
  String? _selectedVoice;
  String? _selectedModel;
  int _cacheSize = 0;

  // 🎵 Instancia persistente de audio para evitar múltiples players
  final AudioPlaybackService _audioPlayer = getAudioPlaybackService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _checkAndroidNative();
    _loadVoices();
    // Preload OpenAI voices (will fallback to static list if API not configured)
    _loadOpenAiVoices();
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
      final voices = await AndroidNativeTtsService.getVoices();
      // Aplicar filtrado por idioma similar a Google Cloud TTS
      final effectiveUserCodes = widget.userLangCodes ?? <String>[];
      final effectiveAiCodes = widget.aiLangCodes ?? <String>[];
      // Debug: mostrar códigos efectivos y una muestra de locales recuperadas
      try {
        final sampleLocales = voices
            .take(10)
            .map(
              (final v) =>
                  (v['locale'] as String?) ??
                  (v['name'] as String?) ??
                  '<no-locale>',
            )
            .join(', ');
        Log.d(
          'DEBUG TTS: effectiveUserCodes=$effectiveUserCodes effectiveAiCodes=$effectiveAiCodes sampleLocales=[$sampleLocales]',
          tag: 'TTS_DIALOG',
        );
      } on Exception catch (_) {}
      final filtered = await AndroidNativeTtsService.filterVoicesByCodes(
        voices,
        effectiveUserCodes,
        effectiveAiCodes,
      );
      setState(() {
        _androidNativeVoices.clear();
        _androidNativeVoices.addAll(filtered);
        _isLoading = false;
      });
      Log.d(
        'DEBUG TTS: Voces nativas actualizadas: ${voices.length} -> filtradas: ${filtered.length}',
        tag: 'TTS_DIALOG',
      );
      if (mounted) {
        showAppSnackBar(
          'Voces nativas detectadas: ${voices.length}. Filtradas: ${filtered.length}',
        );
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
      if (_selectedProvider == 'google') {
        await _loadVoices(forceRefresh: forceRefresh);
      } else if (_selectedProvider == 'openai') {
        await _loadOpenAiVoices(forceRefresh: forceRefresh);
      } else if (_selectedProvider == 'android_native') {
        await _refreshNativeVoices();
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
      final providerVoice = await PrefsUtils.getPreferredVoice(fallback: '');
      final selModel = await PrefsUtils.getSelectedModel();
      setState(() {
        _selectedProvider = savedProvider;
        _selectedVoice = providerVoice.isEmpty ? null : providerVoice;
        _selectedModel = selModel ?? Config.getDefaultTextModel();
      });
    } on Exception catch (_) {
      setState(() {
        _selectedProvider = Config.getAudioProvider().toLowerCase();
        _selectedVoice = null;
        _selectedModel = Config.getDefaultTextModel();
      });
    }
  }

  Future<void> _checkAndroidNative() async {
    // Detectar plataforma y comprobar disponibilidad nativa solo en Android
    if (Platform.isAndroid) {
      final available = await AndroidNativeTtsService.checkNativeTtsAvailable();
      setState(() {
        _androidNativeAvailable = available;
      });
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
    return TtsVoiceService.getVoiceQualityLevel(voice);
  }

  Future<void> _loadVoices({final bool forceRefresh = false}) async {
    Log.d(
      'DEBUG TTS: _loadVoices iniciado - forceRefresh: $forceRefresh',
      tag: 'TTS_DIALOG',
    );
    try {
      // Preferir los códigos proporcionados por el widget; si no existen, no filtrar por idioma
      final effectiveUserCodes = widget.userLangCodes ?? <String>[];
      final effectiveAiCodes = widget.aiLangCodes ?? <String>[];

      // If caller requested forceRefresh, clear cached voices to force re-download
      if (forceRefresh) {
        try {
          await CacheService.clearAllVoicesCache();
          Log.d(
            'DEBUG TTS: ClearAllVoicesCache invoked due to forceRefresh',
            tag: 'TTS_DIALOG',
          );
        } on Exception catch (e) {
          Log.d('DEBUG TTS: clearAllVoicesCache failed: $e', tag: 'TTS_DIALOG');
        }
      }

      final voices = await GoogleSpeechService.fetchGoogleVoicesStatic(
        forceRefresh: forceRefresh,
      );
      Log.d(
        'DEBUG TTS: Neural/WaveNet voices loaded: ${voices.length} (user=$effectiveUserCodes, ai=$effectiveAiCodes)',
        tag: 'TTS_DIALOG',
      );

      if (mounted) {
        setState(() {
          _googleVoices = voices;
          _isLoading = false;
        });
        Log.d(
          'DEBUG TTS: setState completado con ${_googleVoices.length} voces',
          tag: 'TTS_DIALOG',
        );
      }
    } on Exception catch (e) {
      Log.d('DEBUG TTS: Error loading voices: $e', tag: 'TTS_DIALOG');
      if (mounted) {
        setState(() {
          _googleVoices = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOpenAiVoices({final bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      // Use the static voice list helper (presentation-level) to ensure consistent shape and display
      _openaiVoices.clear();
      _openaiVoices.addAll(OpenAiVoiceUtils.loadStaticOpenAiVoices());
    } on Exception {
      _openaiVoices.clear();
      _openaiVoices.addAll(
        kOpenAIVoices.map((final v) => {'name': v}).toList(),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      await CacheService.clearAudioCache();
      await GoogleSpeechService.clearVoicesCacheStatic();
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

            // Selector de proveedor
            if (_androidNativeAvailable) ...[
              ListTile(
                leading: _selectedProvider == 'android_native'
                    ? const Icon(Icons.radio_button_checked)
                    : const Icon(Icons.radio_button_unchecked),
                title: const Text('TTS Nativo Android (Gratuito)'),
                subtitle: Text(
                  '${_androidNativeVoices.length} voces instaladas',
                ),
                onTap: () async {
                  setState(() => _selectedProvider = 'android_native');
                  await _saveSettings();
                  // Forzar refresco inmediato al seleccionar proveedor nativo
                  await _refreshNativeVoices();
                },
              ),
              const SizedBox(height: 8),
            ],

            ListTile(
              leading: _selectedProvider == 'google'
                  ? const Icon(Icons.radio_button_checked)
                  : const Icon(Icons.radio_button_unchecked),
              title: const Text('Google Cloud TTS'),
              subtitle: Text(
                GoogleSpeechService.isConfiguredStatic
                    ? '${_googleVoices.length} voces disponibles'
                    : 'No configurado',
              ),
              enabled: GoogleSpeechService.isConfiguredStatic,
              onTap: GoogleSpeechService.isConfiguredStatic
                  ? () async {
                      setState(() => _selectedProvider = 'google');
                      await _saveSettings();
                    }
                  : null,
            ),

            ListTile(
              leading: _selectedProvider == 'openai'
                  ? const Icon(Icons.radio_button_checked)
                  : const Icon(Icons.radio_button_unchecked),
              title: const Text('OpenAI TTS'),
              subtitle: Text('${_openaiVoices.length} voces disponibles'),
              onTap: () async {
                setState(() => _selectedProvider = 'openai');
                await _saveSettings();
              },
            ),

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

            // Información del caché y limpiar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Caché:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Tamaño: ${CacheService.formatCacheSize(_cacheSize)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Limpiar'),
                  onPressed: _cacheSize > 0 ? _clearCache : null,
                ),
              ],
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
                  if (_selectedProvider == 'google') {
                    await _loadVoices(forceRefresh: true);
                  } else if (_selectedProvider == 'openai') {
                    await _loadOpenAiVoices(forceRefresh: true);
                  } else if (_selectedProvider == 'android_native') {
                    // Refresh native voices (fetch list) when native provider is selected
                    await _refreshNativeVoices();

                    // Debug: dump JSON for requested language codes to help inspect raw plugin output
                    try {
                      final effectiveUserCodes =
                          widget.userLangCodes ?? <String>[];
                      final effectiveAiCodes = widget.aiLangCodes ?? <String>[];
                      var codes = [...effectiveUserCodes, ...effectiveAiCodes];
                      if (codes.isEmpty) codes = ['es-ES'];
                      for (final c in codes) {
                        try {
                          await AndroidNativeTtsService.dumpVoicesJsonForLanguage(
                            c,
                            exactOnly: true,
                          );
                        } on Exception catch (e) {
                          Log.d(
                            'DEBUG TTS: dumpVoicesJsonForLanguage failed for $c: $e',
                            tag: 'TTS_DIALOG',
                          );
                        }
                      }
                    } on Exception catch (e) {
                      Log.d(
                        'DEBUG TTS: Error dumping native voices JSON: $e',
                        tag: 'TTS_DIALOG',
                      );
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

    switch (_selectedProvider) {
      case 'android_native':
        // Ya se filtraron las voces nativas en _refreshNativeVoices usando
        // los códigos proporcionados por widget.userLangCodes y widget.aiLangCodes.
        voices = List<Map<String, dynamic>>.from(_androidNativeVoices);
        break;
      case 'google':
        voices = _googleVoices;
        break;
      case 'openai':
        voices = _openaiVoices;
        break;
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
            subtitle = AndroidNativeTtsService.formatVoiceInfoStatic(voice);
          } else if (_selectedProvider == 'google') {
            // Usar nombre amigable para voces de Google
            displayName = VoiceDisplayUtils.getGoogleVoiceFriendlyName(voice);
            final originalSubtitle = VoiceDisplayUtils.getVoiceSubtitle(voice);
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
          } else if (_selectedProvider == 'openai') {
            final disp = OpenAiVoiceUtils.formatVoiceDisplay(voice);
            displayName = disp['displayName'] ?? displayName;
            subtitle = disp['subtitle'] ?? '';
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

                        final providerKey = _selectedProvider == 'openai'
                            ? 'openai'
                            : (_selectedProvider == 'android_native'
                                  ? 'android_native'
                                  : 'google');

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
