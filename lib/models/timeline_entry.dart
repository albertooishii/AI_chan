class TimelineEntry {
  final String date;
  final String resume;

  TimelineEntry({required this.date, required this.resume});

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    return TimelineEntry(date: json['date'] ?? '', resume: json['resume'] ?? '');
  }

  Map<String, dynamic> toJson() => {'date': date, 'resume': resume};
}
