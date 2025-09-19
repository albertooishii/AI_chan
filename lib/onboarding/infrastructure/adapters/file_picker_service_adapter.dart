/// 🔌 **File Picker Service Adapter** - Infrastructure Implementation
///
/// Adapter that implements IFilePickerService using the file_picker package.
/// Bridges the domain interface with the external file_picker dependency.
///
/// **Hexagonal Architecture:**
/// - ✅ Adapter pattern: Converts external package interface to domain interface
/// - ✅ Dependency inversion: Domain defines interface, infrastructure implements
/// - ✅ Isolation: External package dependency contained in infrastructure layer
library;

import 'package:file_picker/file_picker.dart' as fp;
import 'package:ai_chan/onboarding/domain/interfaces/i_file_picker_service.dart';

class FilePickerServiceAdapter implements IFilePickerService {
  @override
  Future<FilePickerResult?> pickFiles({
    final String? dialogTitle,
    final List<String>? allowedExtensions,
    final bool allowMultiple = false,
  }) async {
    final result = await fp.FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
    );

    if (result == null) return null;

    final pickedFiles = result.files
        .map(
          (final file) =>
              PickedFile(name: file.name, path: file.path, size: file.size),
        )
        .toList();

    return FilePickerResult(files: pickedFiles);
  }
}
