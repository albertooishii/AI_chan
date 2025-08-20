import 'package:ai_chan/voice/domain/models/voice_call.dart';
import 'package:ai_chan/voice/domain/models/voice_message.dart';
import 'package:ai_chan/voice/domain/models/voice_provider.dart';

/// Servicio de dominio para validaciones de llamadas de voz
class VoiceCallValidationService {
  /// Valida si una configuración de llamada es válida
  static bool isCallConfigValid(CallConfig config) {
    // System prompt no puede estar vacío
    if (config.systemPrompt.trim().isEmpty) {
      return false;
    }

    // Temperatura debe estar en rango válido
    if (config.temperature < 0.0 || config.temperature > 2.0) {
      return false;
    }

    // Max tokens debe ser positivo
    if (config.maxTokens <= 0) {
      return false;
    }

    // Debe haber al menos audio o texto habilitado
    if (!config.audioEnabled && !config.textEnabled) {
      return false;
    }

    return true;
  }

  /// Valida si un mensaje de voz es válido
  static bool isMessageValid(VoiceMessage message) {
    // ID no puede estar vacío
    if (message.id.trim().isEmpty) {
      return false;
    }

    // Debe tener al menos texto o audio
    if (!message.hasText && !message.hasAudio) {
      return false;
    }

    // Si tiene texto, no puede estar vacío
    if (message.hasText && message.text!.trim().isEmpty) {
      return false;
    }

    // Si tiene audio por path, el path no puede estar vacío
    if (message.audioPath != null && message.audioPath!.trim().isEmpty) {
      return false;
    }

    return true;
  }

  /// Valida si una llamada de voz es válida
  static bool isCallValid(VoiceCall call) {
    // ID no puede estar vacío
    if (call.id.trim().isEmpty) {
      return false;
    }

    // Modelo no puede estar vacío
    if (call.model.trim().isEmpty) {
      return false;
    }

    // Voz no puede estar vacía
    if (call.voice.trim().isEmpty) {
      return false;
    }

    // Language code debe tener formato válido (ej: es-ES)
    if (!_isLanguageCodeValid(call.languageCode)) {
      return false;
    }

    // Configuración debe ser válida
    if (!isCallConfigValid(call.config)) {
      return false;
    }

    // Todos los mensajes deben ser válidos
    for (final message in call.messages) {
      if (!isMessageValid(message)) {
        return false;
      }
    }

    // Si está finalizada, debe tener endTime
    if (call.isCompleted && call.endTime == null) {
      return false;
    }

    return true;
  }

  /// Valida si un proveedor es compatible con las opciones dadas
  static bool isProviderCompatible(
    VoiceProvider provider, {
    bool requiresRealtime = false,
    bool requiresSTTTTS = false,
  }) {
    if (requiresRealtime && !provider.supportsRealtime) {
      return false;
    }

    if (requiresSTTTTS && !provider.requiresSeparateSTTTTS) {
      return false;
    }

    return true;
  }

  /// Valida formato de código de idioma (ej: es-ES, en-US)
  static bool _isLanguageCodeValid(String languageCode) {
    final regex = RegExp(r'^[a-z]{2}(-[A-Z]{2})?$');
    return regex.hasMatch(languageCode);
  }
}

/// Servicio de dominio para orchestración de llamadas de voz
class VoiceCallOrchestrationService {
  /// Crea una nueva llamada con configuración por defecto
  static VoiceCall createCall({
    required String id,
    required VoiceProvider provider,
    required String model,
    required String voice,
    String languageCode = 'es-ES',
    CallConfig? config,
    Map<String, dynamic>? metadata,
  }) {
    final effectiveConfig = config ?? CallConfig.defaultConfig();

    return VoiceCall.create(
      id: id,
      provider: provider,
      model: model,
      voice: voice,
      languageCode: languageCode,
      config: effectiveConfig,
      metadata: metadata,
    );
  }

  /// Finaliza una llamada activa
  static VoiceCall finishCall(VoiceCall call) {
    if (!call.isActive) {
      throw StateError('Cannot finish a call that is not active');
    }

    return call.copyWith(status: CallStatus.completed, endTime: DateTime.now());
  }

  /// Pausa una llamada activa
  static VoiceCall pauseCall(VoiceCall call) {
    if (!call.isActive) {
      throw StateError('Cannot pause a call that is not active');
    }

    return call.copyWith(status: CallStatus.paused);
  }

  /// Reanuda una llamada pausada
  static VoiceCall resumeCall(VoiceCall call) {
    if (call.status != CallStatus.paused) {
      throw StateError('Cannot resume a call that is not paused');
    }

    return call.copyWith(status: CallStatus.active);
  }

  /// Cancela una llamada
  static VoiceCall cancelCall(VoiceCall call) {
    if (call.isCompleted) {
      throw StateError('Cannot cancel a call that is already completed');
    }

    return call.copyWith(status: CallStatus.cancelled, endTime: DateTime.now());
  }

  /// Marca una llamada como fallida
  static VoiceCall markCallAsFailed(VoiceCall call, String reason) {
    return call.copyWith(
      status: CallStatus.failed,
      endTime: DateTime.now(),
      metadata: {
        ...?call.metadata,
        'failureReason': reason,
        'failureTime': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Agrega un mensaje a una llamada
  static VoiceCall addMessageToCall(VoiceCall call, VoiceMessage message) {
    if (!VoiceCallValidationService.isMessageValid(message)) {
      throw ArgumentError('Invalid message');
    }

    final updatedMessages = [...call.messages, message];
    return call.copyWith(messages: updatedMessages);
  }

  /// Calcula estadísticas de una llamada
  static Map<String, dynamic> calculateCallStats(VoiceCall call) {
    final userMessages = call.messages.where((m) => m.isFromUser).length;
    final assistantMessages = call.messages
        .where((m) => m.isFromAssistant)
        .length;
    final audioMessages = call.messages.where((m) => m.hasAudio).length;
    final textMessages = call.messages.where((m) => m.hasText).length;

    final totalAudioDuration = call.messages
        .where((m) => m.audioDuration != null)
        .fold<Duration>(Duration.zero, (total, m) => total + m.audioDuration!);

    return {
      'duration': call.duration,
      'totalMessages': call.messages.length,
      'userMessages': userMessages,
      'assistantMessages': assistantMessages,
      'audioMessages': audioMessages,
      'textMessages': textMessages,
      'totalAudioDuration': totalAudioDuration,
      'averageResponseTime': _calculateAverageResponseTime(call),
    };
  }

  /// Calcula tiempo promedio de respuesta del asistente
  static Duration _calculateAverageResponseTime(VoiceCall call) {
    final messages = call.messages;
    if (messages.length < 2) return Duration.zero;

    final responseTimes = <Duration>[];

    for (int i = 0; i < messages.length - 1; i++) {
      final current = messages[i];
      final next = messages[i + 1];

      if (current.isFromUser && next.isFromAssistant) {
        responseTimes.add(next.timestamp.difference(current.timestamp));
      }
    }

    if (responseTimes.isEmpty) return Duration.zero;

    final totalMs = responseTimes.fold<int>(
      0,
      (sum, duration) => sum + duration.inMilliseconds,
    );

    return Duration(milliseconds: totalMs ~/ responseTimes.length);
  }
}
