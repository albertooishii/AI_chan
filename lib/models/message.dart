import 'image.dart';

enum MessageSender { user, assistant, system }

enum MessageStatus { sending, sent, delivered, read }

class Message {
  Message copyWith({
    String? text,
    MessageSender? sender,
    DateTime? dateTime,
    bool? isImage,
    Image? image,
    MessageStatus? status,
    bool? isAudio,
    String? audioPath,
    bool? autoTts,
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
    );
  }

  final String text;
  final MessageSender sender;
  final DateTime dateTime;
  final bool isImage;
  final Image? image;
  MessageStatus status;
  final bool isAudio; // nuevo: indica si el mensaje contiene nota de voz
  final String? audioPath; // ruta local del archivo de audio
  final bool autoTts; // si fue generado automáticamente vía TTS IA

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
  });

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
  };

  factory Message.fromJson(Map<String, dynamic> json) {
    final imageObj = json['image'] != null ? Image.fromJson(json['image']) : null;
    final bool isAudio = json['isAudio'] == true || json.containsKey('audioPath');
    return Message(
      text: json['text'] ?? '',
      sender: json['sender'] == 'user'
          ? MessageSender.user
          : (json['sender'] == 'system' ? MessageSender.system : MessageSender.assistant),
      dateTime: json['dateTime'] != null && json['dateTime'] is String
          ? DateTime.tryParse(json['dateTime']) ?? DateTime.now()
          : DateTime.now(),
      isImage: json['isImage'] is bool ? json['isImage'] as bool : (json['isImage'] == true),
      image: imageObj,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
      isAudio: isAudio,
      audioPath: json['audioPath'] as String?,
      autoTts: json['autoTts'] == true,
    );
  }
}
