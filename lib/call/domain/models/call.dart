import 'package:ai_chan/call/domain/models/call_provider.dart';
import 'package:ai_chan/call/domain/models/call_message.dart';
import 'package:ai_chan/core/models.dart';

/// Agregado de dominio que representa una llamada completa
class Call {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final CallProvider provider;
  final String model;
  final String voice;
  final String languageCode;
  final List<CallMessage> messages;
  final CallStatus status;
  final CallConfig config;
  final Map<String, dynamic>? metadata;

  const Call({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.provider,
    required this.model,
    required this.voice,
    required this.languageCode,
    required this.messages,
    required this.status,
    required this.config,
    this.metadata,
  });

  /// Duración de la llamada
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  /// Verifica si la llamada está activa
  bool get isActive => status == CallStatus.active;

  /// Verifica si la llamada está finalizada
  bool get isCompleted => status == CallStatus.completed;

  /// Crea una nueva llamada
  factory Call.create({
    required String id,
    required CallProvider provider,
    required String model,
    required String voice,
    required String languageCode,
    required CallConfig config,
    Map<String, dynamic>? metadata,
  }) {
    return Call(
      id: id,
      startTime: DateTime.now(),
      provider: provider,
      model: model,
      voice: voice,
      languageCode: languageCode,
      messages: [],
      status: CallStatus.active,
      config: config,
      metadata: metadata,
    );
  }

  /// Copia con nuevos valores
  Call copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    CallProvider? provider,
    String? model,
    String? voice,
    String? languageCode,
    List<CallMessage>? messages,
    CallStatus? status,
    CallConfig? config,
    Map<String, dynamic>? metadata,
  }) {
    return Call(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      voice: voice ?? this.voice,
      languageCode: languageCode ?? this.languageCode,
      messages: messages ?? this.messages,
      status: status ?? this.status,
      config: config ?? this.config,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Convierte a mapa
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'provider': provider.name,
      'model': model,
      'voice': voice,
      'languageCode': languageCode,
      'messages': messages.map((m) => m.toMap()).toList(),
      'status': status.name,
      'config': config.toMap(),
      'metadata': metadata,
    };
  }

  /// Crea desde mapa
  factory Call.fromMap(Map<String, dynamic> map) {
    return Call(
      id: map['id'] as String,
      startTime: DateTime.parse(map['startTime'] as String),
      endTime: map['endTime'] != null
          ? DateTime.parse(map['endTime'] as String)
          : null,
      provider: CallProviderExtension.fromString(map['provider'] as String),
      model: map['model'] as String,
      voice: map['voice'] as String,
      languageCode: map['languageCode'] as String,
      messages: (map['messages'] as List<dynamic>)
          .map((m) => CallMessage.fromMap(m as Map<String, dynamic>))
          .toList(),
      status: CallStatusExtension.fromString(map['status'] as String),
      config: CallConfig.fromMap(map['config'] as Map<String, dynamic>),
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'Call(id: $id, provider: ${provider.name}, status: ${status.name}, messages: ${messages.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Call && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Configuración de una llamada de voz
class CallConfig {
  final String systemPrompt;
  final bool audioEnabled;
  final bool textEnabled;
  final String turnDetectionType;
  final double temperature;
  final int maxTokens;
  final Map<String, dynamic>? additionalOptions;

  const CallConfig({
    required this.systemPrompt,
    this.audioEnabled = true,
    this.textEnabled = true,
    this.turnDetectionType = 'server_vad',
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.additionalOptions,
  });

  /// Configuración por defecto
  factory CallConfig.defaultConfig() {
    return const CallConfig(
      systemPrompt: 'Eres AI-chan, una asistente de voz amigable y útil.',
    );
  }

  /// Copia con nuevos valores
  CallConfig copyWith({
    String? systemPrompt,
    bool? audioEnabled,
    bool? textEnabled,
    String? turnDetectionType,
    double? temperature,
    int? maxTokens,
    Map<String, dynamic>? additionalOptions,
  }) {
    return CallConfig(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      textEnabled: textEnabled ?? this.textEnabled,
      turnDetectionType: turnDetectionType ?? this.turnDetectionType,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      additionalOptions: additionalOptions ?? this.additionalOptions,
    );
  }

  /// Convierte a mapa
  Map<String, dynamic> toMap() {
    return {
      'systemPrompt': systemPrompt,
      'audioEnabled': audioEnabled,
      'textEnabled': textEnabled,
      'turnDetectionType': turnDetectionType,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'additionalOptions': additionalOptions,
    };
  }

  /// Crea desde mapa
  factory CallConfig.fromMap(Map<String, dynamic> map) {
    return CallConfig(
      systemPrompt: map['systemPrompt'] as String,
      audioEnabled: map['audioEnabled'] as bool? ?? true,
      textEnabled: map['textEnabled'] as bool? ?? true,
      turnDetectionType: map['turnDetectionType'] as String? ?? 'server_vad',
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: map['maxTokens'] as int? ?? 4096,
      additionalOptions: map['additionalOptions'] as Map<String, dynamic>?,
    );
  }
}
