import 'dart:typed_data';
import 'package:ai_chan/core/models.dart';

/// Mensaje de voz dentro de una llamada
class VoiceMessage {
  final String id;
  final MessageType type;
  final MessageSender sender;
  final DateTime timestamp;
  final String? text;
  final Uint8List? audioData;
  final String? audioPath;
  final Duration? audioDuration;
  final Map<String, dynamic>? metadata;

  const VoiceMessage({
    required this.id,
    required this.type,
    required this.sender,
    required this.timestamp,
    this.text,
    this.audioData,
    this.audioPath,
    this.audioDuration,
    this.metadata,
  });

  /// Verifica si el mensaje contiene audio
  bool get hasAudio => audioData != null || audioPath != null;

  /// Verifica si el mensaje contiene texto
  bool get hasText => text != null && text!.trim().isNotEmpty;

  /// Verifica si es un mensaje del usuario
  bool get isFromUser => sender == MessageSender.user;

  /// Verifica si es un mensaje del asistente
  bool get isFromAssistant => sender == MessageSender.assistant;

  /// Crea un mensaje de texto del usuario
  factory VoiceMessage.userText({
    required String id,
    required String text,
    Map<String, dynamic>? metadata,
  }) {
    return VoiceMessage(
      id: id,
      type: MessageType.text,
      sender: MessageSender.user,
      timestamp: DateTime.now(),
      text: text,
      metadata: metadata,
    );
  }

  /// Crea un mensaje de audio del usuario
  factory VoiceMessage.userAudio({
    required String id,
    Uint8List? audioData,
    String? audioPath,
    Duration? audioDuration,
    Map<String, dynamic>? metadata,
  }) {
    return VoiceMessage(
      id: id,
      type: MessageType.audio,
      sender: MessageSender.user,
      timestamp: DateTime.now(),
      audioData: audioData,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: metadata,
    );
  }

  /// Crea un mensaje de texto del asistente
  factory VoiceMessage.assistantText({
    required String id,
    required String text,
    Map<String, dynamic>? metadata,
  }) {
    return VoiceMessage(
      id: id,
      type: MessageType.text,
      sender: MessageSender.assistant,
      timestamp: DateTime.now(),
      text: text,
      metadata: metadata,
    );
  }

  /// Crea un mensaje de audio del asistente
  factory VoiceMessage.assistantAudio({
    required String id,
    Uint8List? audioData,
    String? audioPath,
    Duration? audioDuration,
    Map<String, dynamic>? metadata,
  }) {
    return VoiceMessage(
      id: id,
      type: MessageType.audio,
      sender: MessageSender.assistant,
      timestamp: DateTime.now(),
      audioData: audioData,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: metadata,
    );
  }

  /// Crea un mensaje mixto (texto + audio) del asistente
  factory VoiceMessage.assistantMixed({
    required String id,
    required String text,
    Uint8List? audioData,
    String? audioPath,
    Duration? audioDuration,
    Map<String, dynamic>? metadata,
  }) {
    return VoiceMessage(
      id: id,
      type: MessageType.mixed,
      sender: MessageSender.assistant,
      timestamp: DateTime.now(),
      text: text,
      audioData: audioData,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: metadata,
    );
  }

  /// Copia con nuevos valores
  VoiceMessage copyWith({
    String? id,
    MessageType? type,
    MessageSender? sender,
    DateTime? timestamp,
    String? text,
    Uint8List? audioData,
    String? audioPath,
    Duration? audioDuration,
    Map<String, dynamic>? metadata,
  }) {
    return VoiceMessage(
      id: id ?? this.id,
      type: type ?? this.type,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      audioData: audioData ?? this.audioData,
      audioPath: audioPath ?? this.audioPath,
      audioDuration: audioDuration ?? this.audioDuration,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Convierte a mapa
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'sender': sender.name,
      'timestamp': timestamp.toIso8601String(),
      'text': text,
      'audioData': audioData?.toList(),
      'audioPath': audioPath,
      'audioDuration': audioDuration?.inMilliseconds,
      'metadata': metadata,
    };
  }

  /// Crea desde mapa
  factory VoiceMessage.fromMap(Map<String, dynamic> map) {
    return VoiceMessage(
      id: map['id'] as String,
      type: MessageTypeExtension.fromString(map['type'] as String),
      sender: MessageSenderExtension.fromString(map['sender'] as String),
      timestamp: DateTime.parse(map['timestamp'] as String),
      text: map['text'] as String?,
      audioData: map['audioData'] != null
          ? Uint8List.fromList((map['audioData'] as List<dynamic>).cast<int>())
          : null,
      audioPath: map['audioPath'] as String?,
      audioDuration: map['audioDuration'] != null
          ? Duration(milliseconds: map['audioDuration'] as int)
          : null,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() {
    return 'VoiceMessage(id: $id, type: ${type.name}, sender: ${sender.name}, hasText: $hasText, hasAudio: $hasAudio)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VoiceMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Tipos de mensaje de voz
enum MessageType { text, audio, mixed }

/// Extensión para MessageType
extension MessageTypeExtension on MessageType {
  String get name {
    switch (this) {
      case MessageType.text:
        return 'text';
      case MessageType.audio:
        return 'audio';
      case MessageType.mixed:
        return 'mixed';
    }
  }

  static MessageType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'text':
        return MessageType.text;
      case 'audio':
        return MessageType.audio;
      case 'mixed':
        return MessageType.mixed;
      default:
        return MessageType.text;
    }
  }
}
