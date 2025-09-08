/// Domain interface for image processing operations within chat bounded context.
/// Provides abstraction for image saving and manipulation capabilities.
abstract class IChatImageService {
  /// Saves a base64 encoded image to a local file.
  /// Returns the path to the saved file or null if failed.
  Future<String?> saveBase64ImageToFile(final String base64Data);
}
