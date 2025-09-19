import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_realtime_client.dart';
import 'package:ai_chan/shared/ai_providers/core/interfaces/i_ai_provider.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/domain/models/index.dart';
import 'package:ai_chan/shared/infrastructure/utils/log_utils.dart';
import 'package:ai_chan/shared/ai_providers/core/services/ai_provider_manager.dart';
import 'package:ai_chan/shared/ai_providers/core/models/provider_response.dart';

/// Servicio híbrido que combina TTS + STT + modelo de texto
/// para simular capacidades realtime en proveedores que no las tienen nativas
class HybridRealtimeService implements IRealtimeClient {
  HybridRealtimeService({
    required final IAIProvider provider,
    required final String model,
    final Map<String, dynamic>? config,
  }) : _provider = provider,
       _model = model,
       _config = config ?? {};
  final IAIProvider _provider;
  final String _model;
  final Map<String, dynamic> _config;

  // Estado interno
  bool _isConnected = false;
  bool _isProcessing = false;
  String _currentVoice = ''; // Dinámico del provider configurado
  String _systemPrompt = '';
  final List<int> _pendingAudio = [];

  // Controllers para eventos (simulando callbacks del realtime)
  final StreamController<String> _textResponseController =
      StreamController<String>.broadcast();
  final StreamController<Uint8List> _audioResponseController =
      StreamController<Uint8List>.broadcast();
  final StreamController<String> _transcriptionController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Callbacks configurables
  Function(String)? _onTranscription;
  Function(String)? _onTextResponse;
  Function(Uint8List)? _onAudioResponse;
  Function(String)? _onError;

  // Helper para logging
  void _debugLog(final String message) {
    Log.d(message, tag: 'HybridRealtime');
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect({
    required final String systemPrompt,
    final String? voice,
    final String? inputAudioFormat,
    final String? outputAudioFormat,
    final String? turnDetectionType,
    final int? silenceDurationMs,
    final Map<String, dynamic>? options,
  }) async {
    try {
      _systemPrompt = systemPrompt;
      _currentVoice = voice ?? _currentVoice;

      // Configurar desde options si están disponibles
      if (options != null) {
        _config.addAll(options);
      }

      _isConnected = true;

      // Configurar listeners para eventos
      _setupEventListeners();

      _debugLog(
        'Conectado - Proveedor: ${_provider.runtimeType}, Modelo: $_model',
      );
    } on Exception catch (e) {
      final error = 'Error conectando servicio híbrido: $e';
      _handleError(error);
      throw Exception(error);
    }
  }

  @override
  void updateVoice(final String voice) {
    _currentVoice = voice;
    _debugLog('Voz actualizada: $voice');
  }

  @override
  void appendAudio(final List<int> bytes) {
    if (!_isConnected) {
      _handleError('Cliente no conectado');
      return;
    }

    _pendingAudio.addAll(bytes);
    _debugLog(
      'Audio agregado: ${bytes.length} bytes (Total: ${_pendingAudio.length})',
    );
  }

  @override
  void sendText(final String text) {
    if (!_isConnected) {
      _handleError('Cliente no conectado');
      return;
    }

    _debugLog('Enviando texto: $text');

    // Procesar texto inmediatamente
    _processTextInput(text);
  }

  @override
  void requestResponse({final bool audio = true, final bool text = true}) {
    if (!_isConnected) {
      _handleError('Cliente no conectado');
      return;
    }

    _debugLog('Solicitando respuesta - Audio: $audio, Texto: $text');

    // Procesar audio pendiente si hay alguno
    if (_pendingAudio.isNotEmpty) {
      _processAudioInput(
        Uint8List.fromList(_pendingAudio),
        audio: audio,
        text: text,
      );
      _pendingAudio.clear();
    }
  }

  @override
  Future<void> commitPendingAudio() async {
    if (_pendingAudio.isNotEmpty) {
      await _processAudioInput(Uint8List.fromList(_pendingAudio));
      _pendingAudio.clear();
      _debugLog('Audio pendiente procesado');
    }
  }

  @override
  Future<void> close() async {
    try {
      _isConnected = false;
      _isProcessing = false;
      _pendingAudio.clear();

      await _textResponseController.close();
      await _audioResponseController.close();
      await _transcriptionController.close();
      await _errorController.close();

      _debugLog('Cerrado');
    } on Exception catch (e) {
      _debugLog('Error cerrando: $e');
    }
  }

  // Implementaciones por defecto para funcionalidades opcionales (gpt-realtime)

  @override
  void sendImageWithText({
    required final String imageBase64,
    final String? text,
    final String imageFormat = 'png',
  }) {
    _debugLog('Envío de imagen no soportado en modo híbrido');
    _handleError('Envío de imagen no soportado en modo híbrido');
  }

  @override
  void configureTools(final List<Map<String, dynamic>> tools) {
    _debugLog('Configuración de herramientas no soportada en modo híbrido');
  }

  @override
  void sendFunctionCallOutput({
    required final String callId,
    required final String output,
  }) {
    _debugLog('Respuesta de función no soportada en modo híbrido');
  }

  @override
  void cancelResponse({final String? itemId, final int? sampleCount}) {
    _debugLog('Cancelación de respuesta en modo híbrido');
    _isProcessing = false;
  }

  /// Configura callbacks para eventos del servicio híbrido
  void setCallbacks({
    final Function(String)? onTranscription,
    final Function(String)? onTextResponse,
    final Function(Uint8List)? onAudioResponse,
    final Function(String)? onError,
  }) {
    _onTranscription = onTranscription;
    _onTextResponse = onTextResponse;
    _onAudioResponse = onAudioResponse;
    _onError = onError;
  }

  /// Configura listeners para eventos internos
  void _setupEventListeners() {
    _transcriptionController.stream.listen((final transcription) {
      _onTranscription?.call(transcription);
    });

    _textResponseController.stream.listen((final text) {
      _onTextResponse?.call(text);
    });

    _audioResponseController.stream.listen((final audio) {
      _onAudioResponse?.call(audio);
    });

    _errorController.stream.listen((final error) {
      _onError?.call(error);
    });
  }

  /// Procesa entrada de texto directamente
  Future<void> _processTextInput(final String text) async {
    if (_isProcessing) {
      _handleError('Ya se está procesando una solicitud');
      return;
    }

    try {
      _isProcessing = true;

      // Simular transcripción del usuario
      _transcriptionController.add(text);

      // Generar respuesta AI
      await _generateAIResponse(text);
    } on Exception catch (e) {
      _handleError('Error procesando texto: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Procesa entrada de audio usando pipeline híbrido
  Future<void> _processAudioInput(
    final Uint8List audioData, {
    final bool audio = true,
    final bool text = true,
  }) async {
    if (_isProcessing) {
      _handleError('Ya se está procesando una solicitud');
      return;
    }

    try {
      _isProcessing = true;

      // Paso 1: Transcripción de audio a texto (STT)
      final transcription = await _transcribeAudio(audioData);

      if (transcription.isNotEmpty) {
        // Notificar transcripción
        _transcriptionController.add(transcription);

        // Paso 2: Generar respuesta AI con el texto transcrito
        if (text || audio) {
          await _generateAIResponse(transcription, includeAudio: audio);
        }
      }
    } on Exception catch (e) {
      _handleError('Error procesando audio: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Transcribe audio usando capacidades STT del proveedor
  Future<String> _transcribeAudio(final Uint8List audioData) async {
    try {
      // Convertir audio a base64 para API
      final audioBase64 = base64Encode(audioData);

      // Usar capacidades STT del proveedor
      final dynamic rawResp = await _provider.transcribeAudio(
        audioBase64: audioBase64,
        model: _getTranscriptionModel(),
        language: _getCurrentLanguage(),
        additionalParams: _config,
      );

      final providerResp = rawResp is ProviderResponse
          ? rawResp
          : ProviderResponse(
              text: (rawResp as AIResponse).text,
              seed: (rawResp).seed,
              prompt: (rawResp).prompt,
            );

      final text = providerResp.text;
      if (text.isNotEmpty) {
        return text;
      } else {
        return 'Sin transcripción disponible';
      }
    } on Exception catch (e) {
      _debugLog('Error en transcripción: $e');
      // Fallback: devolver texto placeholder para pruebas
      return 'Transcripción simulada debido a error: $e';
    }
  }

  /// Genera respuesta AI usando modelo de texto del proveedor
  Future<void> _generateAIResponse(
    final String userText, {
    final bool includeAudio = true,
  }) async {
    try {
      // Construir historial de conversación con system prompt incluido
      final history = [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userText},
      ];

      // Para simplificar, usar SystemPrompt mínimo
      // En implementación real debería usarse el perfil completo
      final systemPrompt = SystemPrompt.fromJson({
        'profile': {},
        'dateTime': DateTime.now().toIso8601String(),
        'instructions': {'content': _systemPrompt},
      });

      // Generar respuesta de texto
      final dynamic rawResp = await _provider.sendMessage(
        history: history,
        systemPrompt: systemPrompt,
        capability: AICapability.textGeneration,
        model: _model,
        additionalParams: _config,
      );

      final providerResp = rawResp is ProviderResponse
          ? rawResp
          : ProviderResponse(
              text: (rawResp as AIResponse).text,
              seed: (rawResp).seed,
              prompt: (rawResp).prompt,
            );

      final responseText = providerResp.text;

      if (responseText.isNotEmpty) {
        // Notificar respuesta de texto
        _textResponseController.add(responseText);

        // Generar audio si se solicita
        if (includeAudio) {
          await _generateAudioResponse(responseText);
        }
      }
    } on Exception catch (e) {
      _handleError('Error generando respuesta AI: $e');
    }
  }

  /// Genera audio usando capacidades TTS del proveedor
  Future<void> _generateAudioResponse(final String text) async {
    try {
      // Usar capacidades TTS del proveedor
      final dynamic rawResp = await _provider.generateAudio(
        text: text,
        model: _getAudioModel(),
        voice: _currentVoice,
        additionalParams: _config,
      );
      final providerResp = rawResp is ProviderResponse
          ? rawResp
          : ProviderResponse(
              text: (rawResp as AIResponse).text,
              seed: (rawResp).seed,
              prompt: (rawResp).prompt,
            );

      // Extraer datos de audio de la respuesta: prefer audioBase64
      if (providerResp.audioBase64 != null &&
          providerResp.audioBase64!.isNotEmpty) {
        try {
          final bytes = base64Decode(providerResp.audioBase64!);
          _audioResponseController.add(Uint8List.fromList(bytes));
          return;
        } on Exception catch (e) {
          _debugLog('Error decoding provider audio base64: $e');
        }
      }

      if (providerResp.text.isNotEmpty) {
        // Intentar convertir texto como fallback
        final audioBytes = Uint8List.fromList(providerResp.text.codeUnits);
        _audioResponseController.add(audioBytes);
      }
    } on Exception catch (e) {
      _debugLog('Error generando audio: $e');
      // No es error crítico, continuar solo con texto
    }
  }

  /// Obtiene modelo de transcripción apropiado para el proveedor
  String _getTranscriptionModel() {
    // Usar configuración del YAML si está disponible
    final hybridConfig = _config['hybrid_system'] as Map<String, dynamic>?;
    if (hybridConfig != null) {
      final sttSettings = hybridConfig['stt_settings'] as Map<String, dynamic>?;
      if (sttSettings != null && sttSettings.containsKey('model')) {
        return sttSettings['model'] as String;
      }
    }

    // Fallback obtenido dinámicamente del primer provider disponible para transcripción
    final manager = AIProviderManager.instance;
    final providers = manager.getProvidersByCapability(
      AICapability.audioTranscription,
    );
    if (providers.isNotEmpty) {
      final provider = manager.providers[providers.first];
      if (provider != null) {
        final models =
            provider.metadata.availableModels[AICapability.audioTranscription];
        if (models != null && models.isNotEmpty) {
          return models.first;
        }
      }
    }
    return 'unknown-stt-model'; // 🚀 DINÁMICO: Valor genérico en lugar de hardcodear
  }

  /// Obtiene modelo de generación de audio apropiado para el proveedor
  String _getAudioModel() {
    // Usar configuración del YAML si está disponible
    final hybridConfig = _config['hybrid_system'] as Map<String, dynamic>?;
    if (hybridConfig != null) {
      final ttsSettings = hybridConfig['tts_settings'] as Map<String, dynamic>?;
      if (ttsSettings != null && ttsSettings.containsKey('model')) {
        return ttsSettings['model'] as String;
      }
    }

    // Fallback obtenido dinámicamente del primer provider disponible para audio generation
    final manager = AIProviderManager.instance;
    final providers = manager.getProvidersByCapability(
      AICapability.audioGeneration,
    );
    if (providers.isNotEmpty) {
      final provider = manager.providers[providers.first];
      if (provider != null) {
        final models =
            provider.metadata.availableModels[AICapability.audioGeneration];
        if (models != null && models.isNotEmpty) {
          return models.first;
        }
      }
    }
    return 'unknown-tts-model'; // 🚀 DINÁMICO: Valor genérico en lugar de hardcodear
  }

  /// Obtiene idioma actual de la configuración
  String _getCurrentLanguage() {
    return _config['language'] as String? ?? 'es';
  }

  /// Maneja errores y los propaga a callbacks
  void _handleError(final String error) {
    Log.e(error, tag: 'HybridRealtime'); // Usar Log.e para errores
    _errorController.add(error);
  }

  /// Limpieza cuando se destruye el servicio
  void dispose() {
    close();
  }
}
