abstract class ITtsService {
  /// Genera un archivo de audio para el texto y devuelve la ruta local.
  Future<String?> synthesizeToFile({
    required final String text,
    final Map<String, dynamic>? options,
  });

  /// Opcional: obtener lista de voces disponibles.
  Future<List<Map<String, dynamic>>> getAvailableVoices();
}
