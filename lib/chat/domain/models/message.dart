import 'package:ai_chan/core/models.dart';

enum MessageStatus { sending, sent, read, failed }

/// Mensaje de voz dentro de una llamada
class VoiceCallMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  VoiceCallMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
  };

  factory VoiceCallMessage.fromJson(Map<String, dynamic> json) {
    return VoiceCallMessage(
      text: json['text'] ?? '',
      isUser: json['isUser'] == true,
      timestamp: json['timestamp'] != null && json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

/// Resumen completo de una llamada de voz
class VoiceCallSummary {
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;
  final List<VoiceCallMessage> messages;
  final bool userSpoke;
  final bool aiResponded;

  VoiceCallSummary({
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.messages,
    required this.userSpoke,
    required this.aiResponded,
  });

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'duration': duration.inMilliseconds,
    'messages': messages.map((m) => m.toJson()).toList(),
    'userSpoke': userSpoke,
    'aiResponded': aiResponded,
  };

  factory VoiceCallSummary.fromJson(Map<String, dynamic> json) {
    final messagesList = (json['messages'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(VoiceCallMessage.fromJson)
        .toList();

    return VoiceCallSummary(
      startTime: DateTime.tryParse(json['startTime'] ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(json['endTime'] ?? '') ?? DateTime.now(),
      duration: Duration(milliseconds: json['duration'] ?? 0),
      messages: messagesList,
      userSpoke: json['userSpoke'] == true,
      aiResponded: json['aiResponded'] == true,
    );
  }
}

/// Modelo de mensaje principal - Chat Domain Model
class Message {
  final String text;
  final MessageSender sender;
  final DateTime dateTime;
  final bool isImage;
  final AiImage? image;
  MessageStatus status;
  final bool isAudio;
  final String? audioPath;
  final bool autoTts;
  final Duration? callDuration;
  final DateTime? callEndTime;
  final CallStatus? callStatus; // null si no es mensaje de llamada

  Message({
    required this.text,
    required this.sender,
    required this.dateTime,
    this.isImage = false,
    this.image,
    this.status = MessageStatus.sending,
    this.isAudio = false,
    this.audioPath,
    this.autoTts = false,
    this.callDuration,
    this.callEndTime,
    this.callStatus,
  });

  /// Determina si este mensaje es un resumen de llamada de voz
  bool get isVoiceCallSummary =>
      callStatus == CallStatus.completed && callDuration != null;

  /// Formatea la duración de llamada si existe
  String get formattedCallDuration {
    if (callDuration == null) return '';
    final d = callDuration!;
    String two(int v) => v.toString().padLeft(2, '0');
    final h = two(d.inHours);
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '$h:$m:$s';
  }

  Message copyWith({
    String? text,
    MessageSender? sender,
    DateTime? dateTime,
    bool? isImage,
    AiImage? image,
    MessageStatus? status,
    bool? isAudio,
    String? audioPath,
    bool? autoTts,
    Duration? callDuration,
    DateTime? callEndTime,
    CallStatus? callStatus,
  }) {
    return Message(
      text: text ?? this.text,
      sender: sender ?? this.sender,
      dateTime: dateTime ?? this.dateTime,
      isImage: isImage ?? this.isImage,
      image: image ?? this.image,
      status: status ?? this.status,
      isAudio: isAudio ?? this.isAudio,
      audioPath: audioPath ?? this.audioPath,
      autoTts: autoTts ?? this.autoTts,
      callDuration: callDuration ?? this.callDuration,
      callEndTime: callEndTime ?? this.callEndTime,
      callStatus: callStatus ?? this.callStatus,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'sender': sender == MessageSender.user
        ? 'user'
        : sender == MessageSender.assistant
        ? 'assistant'
        : 'system',
    'dateTime': dateTime.toIso8601String(),
    'isImage': isImage,
    'status': status.name,
    if (image != null) 'image': image!.toJson(),
    if (isAudio) 'isAudio': isAudio,
    if (audioPath != null) 'audioPath': audioPath,
    if (autoTts) 'autoTts': autoTts,
    if (callDuration != null) 'callDuration': callDuration!.inMilliseconds,
    if (callEndTime != null) 'callEndTime': callEndTime!.toIso8601String(),
    if (callStatus != null) 'callStatus': callStatus!.name,
  };

  factory Message.fromJson(Map<String, dynamic> json) {
    final imageObj = json['image'] != null
        ? AiImage.fromJson(json['image'])
        : null;
    final bool isAudio =
        json['isAudio'] == true || json.containsKey('audioPath');
    return Message(
      text: json['text'] ?? '',
      sender: json['sender'] == 'user'
          ? MessageSender.user
          : (json['sender'] == 'system'
                ? MessageSender.system
                : MessageSender.assistant),
      dateTime: json['dateTime'] != null && json['dateTime'] is String
          ? DateTime.tryParse(json['dateTime']) ?? DateTime.now()
          : DateTime.now(),
      isImage: json['isImage'] is bool
          ? json['isImage'] as bool
          : (json['isImage'] == true),
      image: imageObj,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
      isAudio: isAudio,
      audioPath: json['audioPath'] as String?,
      autoTts: json['autoTts'] == true,
      callDuration: json['callDuration'] != null
          ? Duration(milliseconds: json['callDuration'])
          : null,
      callEndTime: json['callEndTime'] != null && json['callEndTime'] is String
          ? DateTime.tryParse(json['callEndTime'])
          : null,
      callStatus: _inferCallStatus(json),
    );
  }

  static CallStatus? _inferCallStatus(Map<String, dynamic> json) {
    if (json['callStatus'] != null) {
      final name = json['callStatus'];
      try {
        return CallStatus.values.firstWhere((e) => e.name == name);
      } catch (_) {}
    }
    // Heurísticas retro-compatibilidad
    final text = (json['text'] ?? '').toString().trim();
    if (text == '[call][/call]') return CallStatus.placeholder;
    if (text.toLowerCase() == 'llamada rechazada') return CallStatus.rejected;
    if (text.toLowerCase() == 'llamada no contestada') return CallStatus.missed;
    if (json['callDuration'] != null) return CallStatus.completed;
    return null;
  }
}
