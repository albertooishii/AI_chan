import 'dart:typed_data';
import 'package:ai_chan/core/models.dart';

/// Mensaje dentro de una llamada de voz
class CallMessage {
  const CallMessage({
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

  /// Crea un mensaje de texto del usuario
  factory CallMessage.userText({
    required final String id,
    required final String text,
    final Map<String, dynamic>? metadata,
  }) {
    return _createTextMessage(
      id: id,
      text: text,
      sender: MessageSender.user,
      metadata: metadata,
    );
  }

  /// Crea un mensaje de audio del usuario
  factory CallMessage.userAudio({
    required final String id,
    final Uint8List? audioData,
    final String? audioPath,
    final Duration? audioDuration,
    final Map<String, dynamic>? metadata,
  }) {
    return _createAudioMessage(
      id: id,
      sender: MessageSender.user,
      audioData: audioData,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: metadata,
    );
  }

  /// Crea un mensaje de texto del asistente
  factory CallMessage.assistantText({
    required final String id,
    required final String text,
    final Map<String, dynamic>? metadata,
  }) {
    return _createTextMessage(
      id: id,
      text: text,
      sender: MessageSender.assistant,
      metadata: metadata,
    );
  }

  /// Crea un mensaje de audio del asistente
  factory CallMessage.assistantAudio({
    required final String id,
    final Uint8List? audioData,
    final String? audioPath,
    final Duration? audioDuration,
    final Map<String, dynamic>? metadata,
  }) {
    return _createAudioMessage(
      id: id,
      sender: MessageSender.assistant,
      audioData: audioData,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: metadata,
    );
  }

  /// Crea un mensaje mixto (texto + audio) del asistente
  factory CallMessage.assistantMixed({
    required final String id,
    required final String text,
    final Uint8List? audioData,
    final String? audioPath,
    final Duration? audioDuration,
    final Map<String, dynamic>? metadata,
  }) {
    return CallMessage(
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

  /// Crea desde mapa
  factory CallMessage.fromMap(final Map<String, dynamic> map) {
    return CallMessage(
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
  final String id;
  final MessageType type;
  final MessageSender sender;
  final DateTime timestamp;
  final String? text;
  final Uint8List? audioData;
  final String? audioPath;
  final Duration? audioDuration;
  final Map<String, dynamic>? metadata;

  /// Verifica si el mensaje contiene audio
  bool get hasAudio => audioData != null || audioPath != null;

  /// Verifica si el mensaje contiene texto
  bool get hasText => text != null && text!.trim().isNotEmpty;

  /// Verifica si es un mensaje del usuario
  bool get isFromUser => sender == MessageSender.user;

  /// Verifica si es un mensaje del asistente
  bool get isFromAssistant => sender == MessageSender.assistant;

  /// Helper interno para crear mensaje de texto
  static CallMessage _createTextMessage({
    required final String id,
    required final String text,
    required final MessageSender sender,
    final Map<String, dynamic>? metadata,
  }) {
    return CallMessage(
      id: id,
      type: MessageType.text,
      sender: sender,
      timestamp: DateTime.now(),
      text: text,
      metadata: metadata,
    );
  }

  /// Helper interno para crear mensaje de audio
  static CallMessage _createAudioMessage({
    required final String id,
    required final MessageSender sender,
    final Uint8List? audioData,
    final String? audioPath,
    final Duration? audioDuration,
    final Map<String, dynamic>? metadata,
  }) {
    return CallMessage(
      id: id,
      type: MessageType.audio,
      sender: sender,
      timestamp: DateTime.now(),
      audioData: audioData,
      audioPath: audioPath,
      audioDuration: audioDuration,
      metadata: metadata,
    );
  }

  /// Copia con nuevos valores
  CallMessage copyWith({
    final String? id,
    final MessageType? type,
    final MessageSender? sender,
    final DateTime? timestamp,
    final String? text,
    final Uint8List? audioData,
    final String? audioPath,
    final Duration? audioDuration,
    final Map<String, dynamic>? metadata,
  }) {
    return CallMessage(
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

  @override
  String toString() {
    return 'CallMessage(id: $id, type: ${type.name}, sender: ${sender.name}, hasText: $hasText, hasAudio: $hasAudio)';
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) return true;
    return other is CallMessage && other.id == id;
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

  static MessageType fromString(final String value) {
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
