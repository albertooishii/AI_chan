import 'package:ai_chan/core/models.dart';

/// Interfaz para servicios de perfil específica del dominio core
abstract interface class IProfileService {
  Future<AiChanProfile> generateBiography({
    required final String userName,
    required final String aiName,
    required final DateTime? userBirthdate,
    required final String meetStory,
    final String? userCountryCode,
    final String? aiCountryCode,
  });

  Future<AiImage?> generateAppearance(final AiChanProfile profile);

  Future<void> saveProfile(final AiChanProfile profile);
}
