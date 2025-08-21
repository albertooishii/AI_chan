import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_chan/core/config.dart';
import 'package:ai_chan/shared.dart'; // Using centralized shared exports

class TtsConfigurationDialog extends StatefulWidget {
  const TtsConfigurationDialog({super.key});

  @override
  State<TtsConfigurationDialog> createState() => _TtsConfigurationDialogState();
}

class _TtsConfigurationDialogState extends State<TtsConfigurationDialog> {
  String _selectedProvider = 'google';
  bool _isLoading = false;
  bool _androidNativeAvailable = false;
  bool _showOnlySpanishVoices =
      true; // Filtro para mostrar solo voces de español España
  List<Map<String, dynamic>> _googleVoices = [];
  final List<Map<String, dynamic>> _openaiVoices = [];
  List<Map<String, dynamic>> _androidNativeVoices = [];
  String? _selectedVoice;
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkAndroidNative();
    _loadVoices();
    _loadCacheSize();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedProvider =
          prefs.getString('selected_audio_provider') ??
          Config.getAudioProvider().toLowerCase();
      _selectedVoice = prefs.getString('selected_voice');
      _showOnlySpanishVoices =
          prefs.getBool('show_only_spanish_voices') ?? true;
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

  void _loadVoices() async {
    Log.d(
      'DEBUG TTS: _loadVoices iniciado - _showOnlySpanishVoices: $_showOnlySpanishVoices',
      tag: 'TTS_DIALOG',
    );
    try {
      List<Map<String, dynamic>> voices;
      if (_showOnlySpanishVoices) {
        voices = await GoogleSpeechService.voicesForUserAndAi(
          ['es-ES'],
          ['es-ES'],
        );
        Log.d(
          'DEBUG TTS: Spanish Spain voices loaded: ${voices.length}',
          tag: 'TTS_DIALOG',
        );
        // Imprimir los primeros 5 para debug
        for (int i = 0; i < voices.length && i < 5; i++) {
          final voice = voices[i];
          final name = voice['name'] ?? 'Sin nombre';
          final langCodes = voice['languageCodes'] ?? [];
          Log.d(
            'DEBUG TTS: Voice $i: $name - Languages: $langCodes',
            tag: 'TTS_DIALOG',
          );
        }
      } else {
        voices = await GoogleSpeechService.fetchGoogleVoices();
        Log.d(
          'DEBUG TTS: All voices loaded: ${voices.length}',
          tag: 'TTS_DIALOG',
        );
        // Contar voces españolas para debug
        int spanishCount = 0;
        for (final voice in voices) {
          final langCodes =
              (voice['languageCodes'] as List?)?.cast<String>() ?? [];
          if (langCodes.any((code) => code.toLowerCase().startsWith('es'))) {
            spanishCount++;
          }
        }
        Log.d(
          'DEBUG TTS: Total Spanish voices in all: $spanishCount',
          tag: 'TTS_DIALOG',
        );
      }

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
  }

  Future<void> _refreshVoices() async {
    setState(() => _isLoading = true);

    try {
      Log.d(
        '[TTS Dialog] Refrescando voces, filtro activo: $_showOnlySpanishVoices',
        tag: 'TTS_DIALOG',
      );

      if (GoogleSpeechService.isConfigured) {
        await GoogleSpeechService.clearVoicesCache();
        Log.d('[TTS Dialog] Cache limpiado', tag: 'TTS_DIALOG');

        if (_showOnlySpanishVoices) {
          // Usar voces filtradas para español de España con refresh forzado
          _googleVoices = await GoogleSpeechService.voicesForUserAndAi(
            ['es-ES'],
            ['es-ES'],
            forceRefresh: true,
          );
          Log.d(
            '[TTS Dialog] Voces filtradas refrescadas: ${_googleVoices.length}',
            tag: 'TTS_DIALOG',
          );
        } else {
          // Usar todas las voces disponibles con refresh forzado
          _googleVoices = await GoogleSpeechService.fetchGoogleVoices(
            forceRefresh: true,
          );
          Log.d(
            '[TTS Dialog] Todas las voces refrescadas: ${_googleVoices.length}',
            tag: 'TTS_DIALOG',
          );
        }

        // Debug: mostrar algunas voces después del refresh
        for (
          int i = 0;
          i < (_googleVoices.length > 3 ? 3 : _googleVoices.length);
          i++
        ) {
          final voice = _googleVoices[i];
          final name = voice['name'];
          final langs = voice['languageCodes'];
          Log.d(
            '[TTS Dialog] Después del refresh, voz $i: $name -> $langs',
            tag: 'TTS_DIALOG',
          );
        }
      }

      if (_androidNativeAvailable) {
        _androidNativeVoices =
            await AndroidNativeTtsService.getAvailableVoices();
      }
    } catch (e) {
      Log.d('[TTS Dialog] Error refrescando voces: $e', tag: 'TTS_DIALOG');
      if (mounted) {
        showAppSnackBar(context, 'Error actualizando voces: $e', isError: true);
      }
    }

    setState(() => _isLoading = false);
    await _loadCacheSize();
  }

  Future<void> _clearCache() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      await GoogleSpeechService.clearVoicesCache();
      await _loadCacheSize();

      if (mounted) {
        showAppSnackBar(context, 'Caché limpiado exitosamente');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configuración de TTS'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Proveedor:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Selector de proveedor: usamos ListTile con iconos para evitar APIs deprecadas
              if (_androidNativeAvailable) ...[
                ListTile(
                  leading: _selectedProvider == 'android_native'
                      ? const Icon(Icons.radio_button_checked)
                      : const Icon(Icons.radio_button_unchecked),
                  title: const Text('TTS Nativo Android (Gratuito)'),
                  subtitle: Text(
                    '${_androidNativeVoices.length} voces instaladas',
                  ),
                  onTap: () =>
                      setState(() => _selectedProvider = 'android_native'),
                ),
                const Divider(),
              ],

              ListTile(
                leading: _selectedProvider == 'google'
                    ? const Icon(Icons.radio_button_checked)
                    : const Icon(Icons.radio_button_unchecked),
                title: const Text('Google Cloud TTS'),
                subtitle: Text(
                  GoogleSpeechService.isConfigured
                      ? '${_googleVoices.length} voces disponibles'
                      : 'No configurado',
                ),
                enabled: GoogleSpeechService.isConfigured,
                onTap: GoogleSpeechService.isConfigured
                    ? () => setState(() => _selectedProvider = 'google')
                    : null,
              ),

              ListTile(
                leading: _selectedProvider == 'openai'
                    ? const Icon(Icons.radio_button_checked)
                    : const Icon(Icons.radio_button_unchecked),
                title: const Text('OpenAI TTS'),
                subtitle: Text('${_openaiVoices.length} voces disponibles'),
                onTap: () => setState(() => _selectedProvider = 'openai'),
              ),

              const SizedBox(height: 16),
              const Divider(),

              // Filtro de voces (solo para Google)
              if (_selectedProvider == 'google') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Solo voces de Español (España)',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            _showOnlySpanishVoices
                                ? 'Mostrando ${_googleVoices.length} voces filtradas'
                                : 'Mostrando ${_googleVoices.length} voces (todas)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _showOnlySpanishVoices,
                      onChanged: (value) async {
                        setState(() => _showOnlySpanishVoices = value);
                        // Guardar la preferencia
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('show_only_spanish_voices', value);
                        // Recargar voces con el nuevo filtro
                        _loadVoices();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Sección de voces
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Voces:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _isLoading ? null : _refreshVoices,
                    tooltip: 'Actualizar voces',
                  ),
                ],
              ),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                _buildVoiceList(),

              const SizedBox(height: 16),
              const Divider(),

              // Información del caché
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () async {
            final navCtx = context;
            final navigator = Navigator.of(navCtx);
            await _saveSettings();
            if (navCtx.mounted) navigator.pop(true);
          },
          child: const Text('Guardar'),
        ),
      ],
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
        child: Text('No hay voces disponibles para este proveedor'),
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

          if (_selectedProvider == 'android_native') {
            subtitle = AndroidNativeTtsService.formatVoiceInfo(voice);
          } else if (_selectedProvider == 'google') {
            // Usar nombre amigable para voces de Google
            displayName = VoiceDisplayUtils.getGoogleVoiceFriendlyName(voice);
            subtitle = VoiceDisplayUtils.getVoiceSubtitle(voice);
          } else if (_selectedProvider == 'openai') {
            subtitle = voice['description'] as String? ?? '';
          }

          return ListTile(
            dense: true,
            leading: _selectedVoice == voiceName
                ? const Icon(Icons.radio_button_checked, size: 20)
                : const Icon(Icons.radio_button_unchecked, size: 20),
            title: Text(displayName),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
            onTap: () => setState(() => _selectedVoice = voiceName),
          );
        },
      ),
    );
  }
}
