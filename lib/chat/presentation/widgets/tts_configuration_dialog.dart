import 'package:flutter/material.dart';
// provider import removed; dialog receives ChatProvider from caller
import 'package:ai_chan/core/di.dart' as di;
import 'package:audioplayers/audioplayers.dart' as ap;
import 'dart:io' show Platform;
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared.dart'; // Using centralized shared exports
import '../../application/providers/chat_provider.dart';
// Use the infrastructure facade to avoid direct imports from presentation layer
// Usar la lista estática de voces para la capa de presentación y evitar
// dependencias directas a infraestructura o aplicación en este widget.
// shared.dart already re-exports voice constants

class TtsConfigurationDialog extends StatefulWidget {
  final List<String>? userLangCodes;
  final List<String>? aiLangCodes;
  final ChatProvider? chatProvider; // Provided by the caller to avoid Provider lookup inside dialog

  const TtsConfigurationDialog({super.key, this.userLangCodes, this.aiLangCodes, this.chatProvider});

  @override
  State<TtsConfigurationDialog> createState() => _TtsConfigurationDialogState();
}

class _TtsConfigurationDialogState extends State<TtsConfigurationDialog> with WidgetsBindingObserver {
  String _selectedProvider = 'google';
  bool _isLoading = false;
  bool _androidNativeAvailable = false;
  List<Map<String, dynamic>> _googleVoices = [];
  final List<Map<String, dynamic>> _openaiVoices = [];
  final List<Map<String, dynamic>> _androidNativeVoices = [];
  String? _selectedVoice;
  String? _selectedModel;
  int _cacheSize = 0;

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver (resumed) intentamos refrescar las voces nativas automáticamente
    if (state == AppLifecycleState.resumed && Platform.isAndroid && _selectedProvider == 'android_native') {
      _refreshNativeVoices();
    }
  }

  Future<void> _refreshNativeVoices() async {
    setState(() => _isLoading = true);
    try {
      final voices = await AndroidNativeTtsService.getAvailableVoices();
      // Aplicar filtrado por idioma similar a Google Cloud TTS
      final effectiveUserCodes = widget.userLangCodes ?? <String>[];
      final effectiveAiCodes = widget.aiLangCodes ?? <String>[];
      final filtered = _filterNativeVoices(voices, effectiveUserCodes, effectiveAiCodes);
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
        showAppSnackBar('Voces nativas detectadas: ${voices.length}. Filtradas: ${filtered.length}', isError: false);
      }
    } catch (e) {
      Log.d('DEBUG TTS: Error refrescando voces nativas: $e', tag: 'TTS_DIALOG');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _filterNativeVoices(
    List<Map<String, dynamic>> voices,
    List<String> userCodes,
    List<String> aiCodes,
  ) {
    if ((userCodes.isEmpty) && (aiCodes.isEmpty)) return voices;

    // Separar códigos exactos (con región) y sólo idioma.
    final exactCodes = <String>{};
    final langCodes = <String>{};

    for (final c in [...userCodes, ...aiCodes]) {
      if (c.trim().isEmpty) continue;
      final normalizedIn = c.replaceAll('_', '-').toLowerCase();
      final parts = normalizedIn.split('-');
      if (parts.length >= 2) {
        // Guardar la forma language-region (p.ej. 'es-es')
        exactCodes.add('${parts[0]}-${parts[1]}');
      } else {
        langCodes.add(parts[0]);
      }
    }

    return voices.where((voice) {
      var locale = (voice['locale'] as String?) ?? '';
      if (locale.isEmpty) return false;
      locale = locale.replaceAll('_', '-').toLowerCase();
      final parts = locale.split('-');
      final vlang = parts[0];
      final vexact = parts.length >= 2 ? '${parts[0]}-${parts[1]}' : parts[0];

      // Si hay códigos exactos especificados, requerimos coincidencia exacta (incluye región).
      if (exactCodes.isNotEmpty) {
        return exactCodes.contains(vexact);
      }

      // Si no hay exactos, y hay códigos de idioma, hacer match por idioma.
      if (langCodes.isNotEmpty) {
        return langCodes.contains(vlang);
      }

      // Por defecto (no había códigos válidos), permitir todas
      return true;
    }).toList();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedProvider = prefs.getString('selected_audio_provider') ?? Config.getAudioProvider().toLowerCase();
    // Prefer provider-specific saved voice, fall back to legacy 'selected_voice'
    final providerVoiceKey = 'selected_voice_$savedProvider';
    final providerVoice = prefs.getString(providerVoiceKey);
    final legacyVoice = prefs.getString('selected_voice');
    setState(() {
      _selectedProvider = savedProvider;
      _selectedVoice = providerVoice ?? legacyVoice;
      // Cargar modelo seleccionado guardado o usar el por defecto
      _selectedModel = prefs.getString('selected_model') ?? Config.getDefaultTextModel();
    });
  }

  Future<void> _checkAndroidNative() async {
    // Detectar plataforma y comprobar disponibilidad nativa solo en Android
    if (Platform.isAndroid) {
      final available = await AndroidNativeTtsService.isNativeTtsAvailable();
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
      {'action': 'android.settings.TTS_SETTINGS', 'package': 'com.android.settings'},
      {'action': 'android.settings.TTS_SETTINGS', 'package': 'com.google.android.tts'},
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
        final intent = AndroidIntent(action: action, package: package, data: data);
        await intent.launch();
        return;
      } catch (e) {
        Log.d('DEBUG TTS: Intent ${a['action']} falló: $e', tag: 'TTS_DIALOG');
        // seguir con el siguiente intento
      }
    }

    // Si fallaron todos los intent, mostrar instrucción al usuario
    Log.d('DEBUG TTS: No se pudo abrir ninguna pantalla de ajustes', tag: 'TTS_DIALOG');
    showAppSnackBar('Abre Ajustes → Idioma y entrada → Salida de texto a voz para instalar voces', isError: false);
  }

  Future<void> _installTtsData() async {
    if (!Platform.isAndroid) return;

    try {
      final intent = AndroidIntent(action: 'android.speech.tts.engine.INSTALL_TTS_DATA');
      await intent.launch();
    } catch (e) {
      Log.d('DEBUG TTS: INSTALL_TTS_DATA intent falló: $e', tag: 'TTS_DIALOG');
      showAppSnackBar(
        'No se pudo iniciar la instalación de datos TTS. Abre Ajustes → Salida de texto a voz',
        isError: false,
      );
    }
  }

  /// Obtiene el nivel de calidad legible de una voz Neural/WaveNet
  String _getVoiceQualityLevel(Map<String, dynamic> voice) {
    final name = (voice['name'] as String? ?? '').toLowerCase();
    if (name.contains('wavenet')) {
      return 'WaveNet'; // Máxima calidad
    } else if (name.contains('neural')) {
      return 'Neural'; // Alta calidad
    } else {
      return 'Standard'; // No debería llegar aquí con getNeuralWaveNetVoices
    }
  }

  Future<void> _loadVoices({bool forceRefresh = false}) async {
    Log.d('DEBUG TTS: _loadVoices iniciado - forceRefresh: $forceRefresh', tag: 'TTS_DIALOG');
    try {
      // Preferir los códigos proporcionados por el widget; si no existen, no filtrar por idioma
      final effectiveUserCodes = widget.userLangCodes ?? <String>[];
      final effectiveAiCodes = widget.aiLangCodes ?? <String>[];

      final voices = await GoogleSpeechService.getNeuralWaveNetVoices(
        effectiveUserCodes,
        effectiveAiCodes,
        forceRefresh: forceRefresh,
      );
      Log.d(
        'DEBUG TTS: Neural/WaveNet voices loaded: ${voices.length} (user=$effectiveUserCodes, ai=$effectiveAiCodes)',
        tag: 'TTS_DIALOG',
      );

      // Ya no necesitamos filtro de calidad porque getNeuralWaveNetVoices solo devuelve Neural/WaveNet
      // que son de alta calidad por definición

      // Imprimir algunas voces para debug
      for (int i = 0; i < voices.length && i < 5; i++) {
        final voice = voices[i];
        final name = voice['name'] ?? 'Sin nombre';
        final langCodes = voice['languageCodes'] ?? [];
        final quality = _getVoiceQualityLevel(voice);
        Log.d('DEBUG TTS: Voice $i: $name ($quality) - Languages: $langCodes', tag: 'TTS_DIALOG');
      }

      if (mounted) {
        setState(() {
          _googleVoices = voices;
          _isLoading = false;
        });
        Log.d('DEBUG TTS: setState completado con ${_googleVoices.length} voces', tag: 'TTS_DIALOG');
      }
    } catch (e) {
      Log.d('DEBUG TTS: Error loading voices: $e', tag: 'TTS_DIALOG');
      if (mounted) {
        setState(() {
          _googleVoices = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOpenAiVoices({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      // Nota: Para mantener la separación de capas la UI usa la lista
      // estática `kOpenAIVoices`. El fetch remoto se realiza en capas de
      // infraestructura o en providers cuando corresponda.
      _openaiVoices.clear();
      _openaiVoices.addAll(
        kOpenAIVoices.map((v) => {'name': v, 'description': v, 'languageCodes': <String>[]}).toList(),
      );
    } catch (e) {
      // keep fallback static list
      _openaiVoices.clear();
      _openaiVoices.addAll(
        kOpenAIVoices.map((v) => {'name': v, 'description': v, 'languageCodes': <String>[]}).toList(),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_audio_provider', _selectedProvider);
    if (_selectedVoice != null) {
      // Save both provider-specific and legacy key for backward compatibility
      await prefs.setString('selected_voice', _selectedVoice!);
      final providerKey = 'selected_voice_$_selectedProvider';
      await prefs.setString(providerKey, _selectedVoice!);
    }
    if (_selectedModel != null) {
      await prefs.setString('selected_model', _selectedModel!);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showAppDialog<bool>(
      builder: (context) => AlertDialog(
        title: const Text('Limpiar Caché'),
        content: Text('¿Eliminar ${CacheService.formatCacheSize(_cacheSize)} de audio en caché?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Limpiar')),
        ],
      ),
    );

    if (confirmed == true) {
      await CacheService.clearAudioCache();
      await GoogleSpeechService.clearVoicesCache();
      await _loadCacheSize();

      if (mounted) {
        showAppSnackBar('Caché limpiado exitosamente', preferRootMessenger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pantalla completa con Scaffold para parecer una pantalla nativa

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
                style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar voces',
              icon: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
                  }
                  showAppSnackBar('Voces actualizadas', isError: false);
                } catch (e) {
                  showAppSnackBar('Error al actualizar voces: $e', isError: true);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Proveedor:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              // Selector de proveedor
              if (_androidNativeAvailable) ...[
                ListTile(
                  leading: _selectedProvider == 'android_native'
                      ? const Icon(Icons.radio_button_checked)
                      : const Icon(Icons.radio_button_unchecked),
                  title: const Text('TTS Nativo Android (Gratuito)'),
                  subtitle: Text('${_androidNativeVoices.length} voces instaladas'),
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
                  GoogleSpeechService.isConfigured ? '${_googleVoices.length} voces disponibles' : 'No configurado',
                ),
                enabled: GoogleSpeechService.isConfigured,
                onTap: GoogleSpeechService.isConfigured
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

              Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildVoiceList()),

              const SizedBox(height: 12),

              // Información del caché y limpiar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Caché:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Tamaño: ${CacheService.formatCacheSize(_cacheSize)}', style: const TextStyle(fontSize: 12)),
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
      ),
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
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Paso 1
              Card(
                color: Colors.grey.shade900,
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.settings, color: AppColors.secondary)),
                  title: const Text('Paso 1: Abrir ajustes TTS', style: TextStyle(color: AppColors.secondary)),
                  subtitle: const Text(
                    'Abre la pantalla de salida de texto a voz del sistema',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: TextButton(onPressed: _openAndroidTtsSettings, child: const Text('Abrir')),
                ),
              ),

              // Paso 2
              Card(
                color: Colors.grey.shade900,
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.download, color: AppColors.secondary)),
                  title: const Text('Paso 2: Instalar paquetes de voz', style: TextStyle(color: AppColors.secondary)),
                  subtitle: const Text(
                    'En Ajustes > Salida de texto a voz instala paquetes o selecciona un motor (ej. Google TTS)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: TextButton(onPressed: _installTtsData, child: const Text('Instalar')),
                ),
              ),

              // Paso 3
              Card(
                color: Colors.grey.shade900,
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.refresh, color: AppColors.secondary)),
                  title: const Text('Paso 3: Volver y actualizar', style: TextStyle(color: AppColors.secondary)),
                  subtitle: const Text(
                    'Cuando hayas instalado voces, vuelve a la app y actualiza la lista',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        await _refreshNativeVoices();
                        showAppSnackBar('Actualización completada', isError: false);
                      } catch (e) {
                        showAppSnackBar('Error al actualizar: $e', isError: true);
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
        child: Text('No hay voces disponibles para este proveedor', style: TextStyle(color: AppColors.primary)),
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
        itemBuilder: (context, index) {
          final voice = voices[index];
          final voiceName = voice['name'] as String? ?? 'Sin nombre';

          String displayName = voiceName;
          String subtitle = '';

          // Obtener ChatProvider proporcionado por quien abrió el diálogo
          final chatProv = widget.chatProvider;

          if (_selectedProvider == 'android_native') {
            subtitle = AndroidNativeTtsService.formatVoiceInfo(voice);
          } else if (_selectedProvider == 'google') {
            // Usar nombre amigable para voces de Google
            displayName = VoiceDisplayUtils.getGoogleVoiceFriendlyName(voice);
            final originalSubtitle = VoiceDisplayUtils.getVoiceSubtitle(voice);
            final quality = _getVoiceQualityLevel(voice);
            // Evitar duplicados: si el subtítulo ya contiene la calidad (por ejemplo 'Neural'), no la añadimos de nuevo.
            if (originalSubtitle.toLowerCase().contains(quality.toLowerCase())) {
              subtitle = originalSubtitle;
            } else if (originalSubtitle.isEmpty) {
              subtitle = quality;
            } else {
              // Usar ' · ' para mantener consistencia con VoiceDisplayUtils
              subtitle = '$originalSubtitle · $quality';
            }
          } else if (_selectedProvider == 'openai') {
            // Para voces OpenAI: título capitalizado (ej: 'Sage') y subtítulo
            // con género según el mapa kOpenAIVoiceGender (Femenina/Masculina) y token en minúsculas.
            final token = (voice['name'] as String? ?? '').trim();
            if (token.isNotEmpty) {
              displayName = '${token[0].toUpperCase()}${token.substring(1)}';
            } else {
              displayName = token;
            }

            final genderLabel = (kOpenAIVoiceGender[token.toLowerCase()] ?? '').toString();
            final genderPart = genderLabel.isNotEmpty ? genderLabel : '';
            // Construir subtítulo: 'Género · Multilenguaje · token'
            final parts = <String>[];
            if (genderPart.isNotEmpty) parts.add(genderPart);
            parts.add('Multilenguaje');
            if (token.isNotEmpty) parts.add(token.toLowerCase());
            subtitle = parts.join(' · ');
          }

          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: _selectedVoice == voiceName
                ? const Icon(Icons.radio_button_checked, size: 20, color: AppColors.secondary)
                : const Icon(Icons.radio_button_unchecked, size: 20, color: AppColors.primary),
            title: Text(displayName, style: const TextStyle(color: AppColors.primary)),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            trailing: SizedBox(
              width: 96,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: AppColors.secondary),
                    tooltip: 'Escuchar demo',
                    onPressed: () async {
                      final phrase = 'Hola, soy tu asistente con la voz $voiceName';
                      showAppSnackBar('Buscando audio en caché...', isError: false);
                      try {
                        String lang = 'es-ES';
                        if (voice['languageCodes'] is List && (voice['languageCodes'] as List).isNotEmpty) {
                          lang = (voice['languageCodes'] as List).cast<String>().first;
                        }

                        if (chatProv == null) {
                          showAppSnackBar('Proveedor de audio no disponible', isError: true);
                          return;
                        }

                        final providerKey = _selectedProvider == 'openai'
                            ? 'openai'
                            : (_selectedProvider == 'android_native' ? 'android_native' : 'google');

                        // Comprobar caché primero
                        // For dialog demos, prefer cache (dialog-scoped). Use a
                        // specific provider key to avoid mixing with message cache.
                        final cachedFile = await CacheService.getCachedAudioFile(
                          text: phrase,
                          voice: voiceName,
                          languageCode: lang,
                          provider: '${providerKey}_tts_dialog',
                        );

                        if (cachedFile != null) {
                          final player = di.getAudioPlayback();
                          try {
                            // Debug: ensure file exists and has content before attempting to play
                            final exists = await cachedFile.exists();
                            final length = exists ? await cachedFile.length() : 0;
                            debugPrint(
                              '[TTS_DIALOG] Playing cached audio: path=${cachedFile.path} exists=$exists length=$length',
                            );
                          } catch (e) {
                            debugPrint('[TTS_DIALOG] Failed to stat cached file: $e');
                          }

                          // Prefer explicit DeviceFileSource for local files to avoid Uri/FileProvider fallbacks
                          await player.play(ap.DeviceFileSource(cachedFile.path));
                          // Esperar a la finalización antes de liberar el player para que se oiga el audio
                          try {
                            await player.onPlayerComplete.first;
                          } catch (_) {}
                          await player.dispose();
                          showAppSnackBar('Audio reproducido desde caché', isError: false);
                          return;
                        }

                        showAppSnackBar('Generando audio de prueba...', isError: false);

                        final file = await chatProv.audioService.synthesizeTts(
                          phrase,
                          voice: voiceName,
                          languageCode: lang,
                          forDialogDemo: true,
                        );
                        if (file != null) {
                          final player = di.getAudioPlayback();
                          try {
                            final exists = await file.exists();
                            final length = exists ? await file.length() : 0;
                            debugPrint(
                              '[TTS_DIALOG] Playing generated audio: path=${file.path} exists=$exists length=$length',
                            );
                          } catch (e) {
                            debugPrint('[TTS_DIALOG] Failed to stat generated file: $e');
                          }

                          await player.play(ap.DeviceFileSource(file.path));
                          // Esperar a que termine la reproducción antes de liberar recursos
                          try {
                            await player.onPlayerComplete.first;
                          } catch (_) {}
                          await player.dispose();
                          showAppSnackBar('¡Audio reproducido!', isError: false);
                        } else {
                          showAppSnackBar('No se pudo generar el audio', isError: true);
                        }
                      } catch (e) {
                        showAppSnackBar('Error al reproducir voz: $e', isError: true);
                      }
                    },
                  ),
                  IconButton(
                    icon: _selectedVoice == voiceName
                        ? const Icon(Icons.check_circle, color: AppColors.secondary)
                        : const Icon(Icons.circle_outlined, color: AppColors.primary),
                    tooltip: 'Seleccionar voz',
                    onPressed: () async {
                      setState(() => _selectedVoice = voiceName);
                      try {
                        final prefs = await SharedPreferences.getInstance();
                        // Save both legacy key and provider-specific key to avoid mismatch between
                        // the UI selection and the active provider used by TTS at runtime.
                        await prefs.setString('selected_voice', voiceName);
                        final providerKey = 'selected_voice_$_selectedProvider';
                        await prefs.setString(providerKey, voiceName);
                        if (widget.chatProvider != null) widget.chatProvider!.notifyListeners();
                        showAppSnackBar('Voz seleccionada: $voiceName', isError: false);
                      } catch (e) {
                        showAppSnackBar('Error guardando la voz seleccionada: $e', isError: true);
                      }
                    },
                  ),
                ],
              ),
            ),
            onTap: () async {
              setState(() => _selectedVoice = voiceName);
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('selected_voice', voiceName);
                final providerKey = 'selected_voice_$_selectedProvider';
                await prefs.setString(providerKey, voiceName);
                if (widget.chatProvider != null) widget.chatProvider!.notifyListeners();
                showAppSnackBar('Voz seleccionada: $voiceName', isError: false);
              } catch (e) {
                showAppSnackBar('Error guardando la voz seleccionada: $e', isError: true);
              }
            },
          );
        },
      ),
    );
  }
}
