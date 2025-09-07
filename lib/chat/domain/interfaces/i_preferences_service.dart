/// Preferences Service - Domain Port
/// Interfaz para almacenamiento de preferencias de usuario.
/// Abstrae el almacenamiento de configuraciones y preferencias no sensibles.
abstract class IPreferencesService {
  /// Obtiene el modelo seleccionado.
  Future<String?> getSelectedModel();

  /// Establece el modelo seleccionado.
  Future<void> setSelectedModel(final String model);

  /// Obtiene la información de la cuenta de Google.
  Future<Map<String, dynamic>?> getGoogleAccountInfo();

  /// Establece la información de la cuenta de Google.
  Future<void> setGoogleAccountInfo({
    final String? email,
    final String? avatar,
    final String? name,
    final bool? linked,
  });

  /// Limpia la información de la cuenta de Google.
  Future<void> clearGoogleAccountInfo();

  /// Obtiene el proveedor de audio seleccionado.
  Future<String?> getSelectedAudioProvider();

  /// Establece el proveedor de audio seleccionado.
  Future<void> setSelectedAudioProvider(final String provider);

  /// Obtiene los eventos guardados.
  Future<String?> getEvents();

  /// Establece los eventos.
  Future<void> setEvents(final String eventsJson);

  /// Obtiene el timestamp del último backup automático.
  Future<int?> getLastAutoBackupMs();

  /// Establece el timestamp del último backup automático.
  Future<void> setLastAutoBackupMs(final int timestamp);
}
