class TimelineEntry {
  final String resume;
  final String? startDate;
  final String? endDate;

  TimelineEntry({required this.resume, this.startDate, this.endDate});

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    return TimelineEntry(resume: json['resume'] ?? '', startDate: json['startDate'], endDate: json['endDate']);
  }

  Map<String, dynamic> toJson() => {
    'resume': resume,
    if (startDate != null) 'startDate': startDate,
    if (endDate != null) 'endDate': endDate,
  };
}
