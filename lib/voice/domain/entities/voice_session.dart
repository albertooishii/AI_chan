import 'package:ai_chan/shared.dart';

/// 🎯 DDD: Entidad del dominio para una sesión de voz
/// Agregado raíz con identidad y comportamientos de negocio
class VoiceSession {
  /// Factory para crear nueva sesión
  factory VoiceSession.start({
    required final String id,
    required final VoiceSettings settings,
    final Map<String, dynamic>? metadata,
  }) {
    return VoiceSession(
      id: id,
      startTime: DateTime.now(),
      settings: settings,
      messages: [],
      status: VoiceSessionStatus.active,
      metadata: metadata,
    );
  }
  const VoiceSession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.settings,
    required this.messages,
    required this.status,
    this.metadata,
  });

  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final VoiceSettings settings;
  final List<VoiceMessage> messages;
  final VoiceSessionStatus status;
  final Map<String, dynamic>? metadata;

  // 🎯 COMPORTAMIENTOS DEL DOMINIO

  /// Duración de la sesión
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// ¿Está activa?
  bool get isActive => status == VoiceSessionStatus.active;

  /// ¿Está completada?
  bool get isCompleted => status == VoiceSessionStatus.completed;

  /// Número de mensajes
  int get messageCount => messages.length;

  /// Agregar mensaje (comportamiento de dominio)
  VoiceSession addMessage(final VoiceMessage message) {
    return copyWith(messages: [...messages, message]);
  }

  /// Finalizar sesión
  VoiceSession end() {
    return copyWith(
      endTime: DateTime.now(),
      status: VoiceSessionStatus.completed,
    );
  }

  /// Cambiar configuración de voz
  VoiceSession updateSettings(final VoiceSettings newSettings) {
    return copyWith(settings: newSettings);
  }

  /// Copia inmutable
  VoiceSession copyWith({
    final String? id,
    final DateTime? startTime,
    final DateTime? endTime,
    final VoiceSettings? settings,
    final List<VoiceMessage>? messages,
    final VoiceSessionStatus? status,
    final Map<String, dynamic>? metadata,
  }) {
    return VoiceSession(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      settings: settings ?? this.settings,
      messages: messages ?? this.messages,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() =>
      'VoiceSession($id, ${messages.length} msgs, ${duration.inSeconds}s)';

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is VoiceSession &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 🎯 DDD: Entidad para mensaje de voz
class VoiceMessage {
  /// Factory para mensaje del usuario
  factory VoiceMessage.fromUser({
    required final String id,
    required final String text,
    final List<int>? audioData,
    final Duration? duration,
  }) {
    return VoiceMessage(
      id: id,
      timestamp: DateTime.now(),
      isUser: true,
      text: text,
      audioData: audioData,
      duration: duration,
    );
  }

  /// Factory para mensaje del asistente
  factory VoiceMessage.fromAssistant({
    required final String id,
    required final String text,
    final List<int>? audioData,
    final Duration? duration,
  }) {
    return VoiceMessage(
      id: id,
      timestamp: DateTime.now(),
      isUser: false,
      text: text,
      audioData: audioData,
      duration: duration,
    );
  }
  const VoiceMessage({
    required this.id,
    required this.timestamp,
    required this.isUser,
    required this.text,
    this.audioData,
    this.duration,
  });

  final String id;
  final DateTime timestamp;
  final bool isUser;
  final String text;
  final List<int>? audioData;
  final Duration? duration;

  /// ¿Tiene audio?
  bool get hasAudio => audioData != null && audioData!.isNotEmpty;

  /// ¿Es del asistente?
  bool get isAssistant => !isUser;

  @override
  String toString() => 'VoiceMessage(${isUser ? "User" : "AI"}: "$text")';

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is VoiceMessage &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// 🎯 DDD: Enum para estado de sesión
enum VoiceSessionStatus { active, paused, completed, error }

extension VoiceSessionStatusExtension on VoiceSessionStatus {
  String get displayName {
    switch (this) {
      case VoiceSessionStatus.active:
        return 'Activa';
      case VoiceSessionStatus.paused:
        return 'Pausada';
      case VoiceSessionStatus.completed:
        return 'Completada';
      case VoiceSessionStatus.error:
        return 'Error';
    }
  }
}
