enum MessageSender { user, ia }

enum MessageStatus { sending, sent, delivered, read }

class Message {
  final String text;
  final String? imagePath;
  final MessageSender sender;
  final DateTime dateTime;
  final bool isImage;
  final String? imageId;
  final String? revisedPrompt;
  MessageStatus status;

  Message({
    required this.text,
    required this.sender,
    required this.dateTime,
    this.isImage = false,
    this.imagePath,
    this.imageId,
    this.revisedPrompt,
    this.status = MessageStatus.sending,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'sender': sender == MessageSender.user ? 'user' : 'ia',
    'dateTime': dateTime.toIso8601String(),
    'isImage': isImage,
    'status': status.name,
    if (imagePath != null) 'imagePath': imagePath,
    if (imageId != null) 'imageId': imageId,
    if (revisedPrompt != null) 'revisedPrompt': revisedPrompt,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    text: json['text'],
    sender: json['sender'] == 'user' ? MessageSender.user : MessageSender.ia,
    dateTime: json['dateTime'] != null && json['dateTime'] is String
        ? DateTime.tryParse(json['dateTime']) ?? DateTime.now()
        : DateTime.now(),
    isImage: json['isImage'] is bool
        ? json['isImage'] as bool
        : (json['isImage'] == true),
    imagePath: json['imagePath'],
    imageId: json['imageId'],
    revisedPrompt: json['revisedPrompt'],
    status: MessageStatus.values.firstWhere(
      (e) => e.name == (json['status'] ?? 'sent'),
      orElse: () => MessageStatus.sent,
    ),
  );
}
