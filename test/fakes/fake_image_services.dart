/// Fake Image Generator Service for testing image generation
class FakeImageGeneratorService {
  FakeImageGeneratorService({
    this.base64Response,
    this.shouldFail = false,
    this.errorMessage = 'Image generation failed',
  });

  /// Factory for successful image generation
  factory FakeImageGeneratorService.success([final String? customBase64]) {
    return FakeImageGeneratorService(base64Response: customBase64);
  }

  /// Factory for failed image generation
  factory FakeImageGeneratorService.failure([final String? errorMsg]) {
    return FakeImageGeneratorService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Image generation failed',
    );
  }
  final String? base64Response;
  final bool shouldFail;
  final String errorMessage;

  Future<Map<String, dynamic>> generateImage({
    required final String prompt,
    final String? model,
    final Map<String, dynamic>? options,
  }) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    const defaultBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAAWgmWQ0AAAAASUVORK5CYII=';

    return {
      'image': {
        'base64': base64Response ?? defaultBase64,
        'seed': 'fake-seed',
        'prompt': prompt,
      },
      'text': '',
    };
  }
}

/// Fake Image Processing Service for testing image operations
class FakeImageProcessorService {
  FakeImageProcessorService({
    this.shouldFail = false,
    this.errorMessage = 'Image processing failed',
  });

  factory FakeImageProcessorService.failure([final String? errorMsg]) {
    return FakeImageProcessorService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Image processing failed',
    );
  }
  final bool shouldFail;
  final String errorMessage;

  Future<String> processImage({
    required final String base64Image,
    final Map<String, dynamic>? options,
  }) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    // Return the same image or a processed version
    return base64Image;
  }

  Future<Map<String, dynamic>> analyzeImage({
    required final String base64Image,
  }) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    return {'width': 256, 'height': 256, 'format': 'PNG', 'size': 1024};
  }
}

/// Fake Image Saver Service for testing image saving operations
class FakeImageSaverService {
  FakeImageSaverService({
    this.shouldFail = false,
    this.errorMessage = 'Image save failed',
  });

  factory FakeImageSaverService.failure([final String? errorMsg]) {
    return FakeImageSaverService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Image save failed',
    );
  }
  static final Map<String, String> _savedImages = <String, String>{};
  final bool shouldFail;
  final String errorMessage;

  static void clear() {
    _savedImages.clear();
  }

  static Map<String, String> get savedImages => Map.from(_savedImages);

  Future<String> saveImage({
    required final String base64Image,
    final String? filename,
    final String? directory,
  }) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    final path =
        '${directory ?? 'images'}/${filename ?? 'image_${DateTime.now().millisecondsSinceEpoch}.png'}'; // Mantener PNG para tests
    _savedImages[path] = base64Image;
    return path;
  }

  Future<bool> deleteImage(final String path) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    return _savedImages.remove(path) != null;
  }

  Future<bool> imageExists(final String path) async {
    return _savedImages.containsKey(path);
  }

  Future<String?> loadImage(final String path) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    return _savedImages[path];
  }
}
