import 'package:flutter/material.dart';
// provider import removed; dialog receives ChatProvider from caller
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared.dart'; // Using centralized shared exports
import '../../application/providers/chat_provider.dart';

class TtsConfigurationDialog extends StatefulWidget {
  final List<String>? userLangCodes;
  final List<String>? aiLangCodes;
  final ChatProvider? chatProvider; // Provided by the caller to avoid Provider lookup inside dialog

  const TtsConfigurationDialog({super.key, this.userLangCodes, this.aiLangCodes, this.chatProvider});

  @override
  State<TtsConfigurationDialog> createState() => _TtsConfigurationDialogState();
}

class _TtsConfigurationDialogState extends State<TtsConfigurationDialog> {
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
    _loadSettings();
    _checkAndroidNative();
    _loadVoices();
    // Inicializar voces OpenAI desde la lista estática
    _openaiVoices.addAll(kOpenAIVoices.map((v) => {'name': v, 'description': v}));
    _loadCacheSize();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedProvider = prefs.getString('selected_audio_provider') ?? Config.getAudioProvider().toLowerCase();
      _selectedVoice = prefs.getString('selected_voice');
      // Cargar modelo seleccionado guardado o usar el por defecto
      _selectedModel = prefs.getString('selected_model') ?? Config.getDefaultTextModel();
    });
  }

  Future<void> _checkAndroidNative() async {
    if (AndroidNativeTtsService.isAndroid) {
      final available = await AndroidNativeTtsService.isNativeTtsAvailable();
      setState(() {
        _androidNativeAvailable = available;
      });
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

  Future<void> _loadCacheSize() async {
    final size = await CacheService.getCacheSize();
    setState(() => _cacheSize = size);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_audio_provider', _selectedProvider);
    if (_selectedVoice != null) {
      await prefs.setString('selected_voice', _selectedVoice!);
    }
    if (_selectedModel != null) {
      await prefs.setString('selected_model', _selectedModel!);
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
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
        title: const Text(
          'Configuración de TTS',
          style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
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

              // Botón para forzar actualización de voces (solo para Google)
              if (_selectedProvider == 'google') ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Actualizar voces', style: TextStyle(color: AppColors.secondary)),
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        await _loadVoices(forceRefresh: true);
                        showAppSnackBar('Voces actualizadas', isError: false);
                      } catch (e) {
                        showAppSnackBar('Error al actualizar voces: $e', isError: true);
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],

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
        voices = _androidNativeVoices;
        break;
      case 'google':
        voices = _googleVoices;
        break;
      case 'openai':
        voices = _openaiVoices;
        break;
    }

    if (voices.isEmpty) {
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
            subtitle = '$originalSubtitle • $quality';
          } else if (_selectedProvider == 'openai') {
            subtitle = voice['description'] as String? ?? '';
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
                        final cachedFile = await CacheService.getCachedAudioFile(
                          text: phrase,
                          voice: voiceName,
                          languageCode: lang,
                          provider: providerKey,
                        );

                        if (cachedFile != null) {
                          final player = AudioPlayer();
                          await player.play(DeviceFileSource(cachedFile.path));
                          showAppSnackBar('Audio reproducido desde caché', isError: false);
                          return;
                        }

                        showAppSnackBar('Generando audio de prueba...', isError: false);

                        final file = await chatProv.audioService.synthesizeTts(
                          phrase,
                          voice: voiceName,
                          languageCode: lang,
                        );
                        if (file != null) {
                          final player = AudioPlayer();
                          await player.play(DeviceFileSource(file.path));
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
                        await prefs.setString('selected_voice', voiceName);
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
