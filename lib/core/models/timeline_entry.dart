// Copia de lib/models/timeline_entry.dart para core/shared models
class TimelineEntry {
  final dynamic resume; // Puede ser Map<String, dynamic> (JSON) o String
  final String? startDate;
  final String? endDate;
  final int level;

  TimelineEntry({required this.resume, this.startDate, this.endDate, this.level = 0});

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    return TimelineEntry(
      resume: json['resume'],
      startDate: json['startDate'],
      endDate: json['endDate'],
      level: json['level'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'resume': resume,
    if (startDate != null) 'startDate': startDate,
    if (endDate != null) 'endDate': endDate,
    'level': level,
  };
}
