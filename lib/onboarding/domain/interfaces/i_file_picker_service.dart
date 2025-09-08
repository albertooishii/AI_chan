/// 🎯 **File Picker Service Interface** - Domain Contract
///
/// Define the contract for file picking operations without
/// depending on specific external packages or UI frameworks.
///
/// **DDD Principles:**
/// - Port pattern: Interface defines what operations are available
/// - Framework independence: No external package dependencies
/// - Clean Architecture: Domain layer defines contracts
abstract class IFilePickerService {
  /// Pick files from the device
  Future<FilePickerResult?> pickFiles({
    final String? dialogTitle,
    final List<String>? allowedExtensions,
    final bool allowMultiple = false,
  });
}

/// Result object for file picking operations
class FilePickerResult {
  FilePickerResult({required this.files});

  final List<PickedFile> files;

  bool get isEmpty => files.isEmpty;
}

/// Represents a picked file
class PickedFile {
  PickedFile({required this.name, required this.path, this.size});

  final String name;
  final String? path;
  final int? size;
}
