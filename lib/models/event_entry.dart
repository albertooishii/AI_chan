class EventEntry {
  final String type; // Ej: 'programado', 'promesa', 'cita', etc.
  final String description;
  final DateTime? date;
  final Map<String, dynamic>? extra;

  EventEntry({required this.type, required this.description, this.date, this.extra});

  factory EventEntry.fromJson(Map<String, dynamic> json) {
    return EventEntry(
      type: json['type'] ?? '',
      description: json['description'] ?? '',
      date: json['date'] != null ? DateTime.tryParse(json['date']) : null,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'description': description,
    if (date != null) 'date': date!.toIso8601String(),
    if (extra != null) 'extra': extra,
  };
}
