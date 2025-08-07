import 'image.dart';

enum MessageSender { user, ia, system }

enum MessageStatus { sending, sent, delivered, read }

class Message {
  Message copyWith({
    String? text,
    MessageSender? sender,
    DateTime? dateTime,
    bool? isImage,
    Image? image,
    MessageStatus? status,
  }) {
    return Message(
      text: text ?? this.text,
      sender: sender ?? this.sender,
      dateTime: dateTime ?? this.dateTime,
      isImage: isImage ?? this.isImage,
      image: image ?? this.image,
      status: status ?? this.status,
    );
  }

  final String text;
  final MessageSender sender;
  final DateTime dateTime;
  final bool isImage;
  final Image? image;
  MessageStatus status;

  Message({
    required this.text,
    required this.sender,
    required this.dateTime,
    this.isImage = false,
    this.image,
    this.status = MessageStatus.sending,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'sender': sender == MessageSender.user ? 'user' : 'ia',
    'dateTime': dateTime.toIso8601String(),
    'isImage': isImage,
    'status': status.name,
    if (image != null) 'image': image!.toJson(),
  };

  factory Message.fromJson(Map<String, dynamic> json) {
    final imageObj = json['image'] != null ? Image.fromJson(json['image']) : null;
    return Message(
      text: json['text'],
      sender: json['sender'] == 'user' ? MessageSender.user : MessageSender.ia,
      dateTime: json['dateTime'] != null && json['dateTime'] is String
          ? DateTime.tryParse(json['dateTime']) ?? DateTime.now()
          : DateTime.now(),
      isImage: json['isImage'] is bool ? json['isImage'] as bool : (json['isImage'] == true),
      image: imageObj,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == (json['status'] ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
    );
  }
}
