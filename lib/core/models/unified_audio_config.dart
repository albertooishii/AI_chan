// Placeholder for unified audio config shared model
class UnifiedAudioConfig {
  final String? languageCode;
  final String? voice;
  UnifiedAudioConfig({this.languageCode, this.voice});

  Map<String, dynamic> toJson() => {'languageCode': languageCode, 'voice': voice};

  factory UnifiedAudioConfig.fromJson(Map<String, dynamic> json) =>
      UnifiedAudioConfig(languageCode: json['languageCode'] as String?, voice: json['voice'] as String?);
}
