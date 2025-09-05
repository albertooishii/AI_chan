import 'package:ai_chan/core/models.dart';

abstract class IProfileService {
  Future<AiChanProfile> generateBiography({
    required String userName,
    required String aiName,
    required DateTime? userBirthdate,
    required String meetStory,
    String? userCountryCode,
    String? aiCountryCode,
  });

  Future<AiImage?> generateAppearance(AiChanProfile profile);

  Future<void> saveProfile(AiChanProfile profile);
}
