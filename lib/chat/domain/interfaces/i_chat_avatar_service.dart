import 'package:ai_chan/core/models.dart';

/// Interfaz de aplicación para operaciones de avatar en chat
/// Permite al layer de aplicación interactuar con el controlador sin depender de presentation
abstract interface class IChatAvatarService {
  /// Obtiene el perfil actual
  AiChanProfile? get currentProfile;

  /// Actualiza el perfil con un nuevo avatar
  Future<void> updateProfileWithAvatar(final AiImage avatar);

  /// Obtiene la lista de avatares del perfil
  List<AiImage> get profileAvatars;

  /// Añade un avatar al perfil
  Future<void> addAvatar(final AiImage avatar);

  /// Persiste el perfil actual
  Future<void> persistProfile();

  /// Notifica a los listeners de cambios
  void notifyProfileChanged();
}
