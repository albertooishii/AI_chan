/// Chat Event Entry - Domain Model
/// Representa eventos específicos del contexto de chat
class ChatEvent {
  ChatEvent({
    required this.type,
    required this.description,
    this.date,
    this.extra,
  });

  factory ChatEvent.fromJson(final Map<String, dynamic> json) {
    return ChatEvent(
      type: json['type'] ?? '',
      description: json['description'] ?? '',
      date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }
  final String type; // Ej: 'programado', 'promesa', 'cita', etc.
  final String description;
  final DateTime? date;
  final Map<String, dynamic>? extra;

  Map<String, dynamic> toJson() => {
    'type': type,
    'description': description,
    if (date != null) 'date': date!.toIso8601String(),
    if (extra != null) 'extra': extra,
  };

  ChatEvent copyWith({
    final String? type,
    final String? description,
    final DateTime? date,
    final Map<String, dynamic>? extra,
  }) {
    return ChatEvent(
      type: type ?? this.type,
      description: description ?? this.description,
      date: date ?? this.date,
      extra: extra ?? this.extra,
    );
  }
}
