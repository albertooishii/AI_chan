/// Fake Image Generator Service for testing image generation
class FakeImageGeneratorService {
  final String? base64Response;
  final bool shouldFail;
  final String errorMessage;

  FakeImageGeneratorService({
    this.base64Response,
    this.shouldFail = false,
    this.errorMessage = 'Image generation failed',
  });

  Future<Map<String, dynamic>> generateImage({
    required String prompt,
    String? model,
    Map<String, dynamic>? options,
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

  /// Factory for successful image generation
  factory FakeImageGeneratorService.success([String? customBase64]) {
    return FakeImageGeneratorService(base64Response: customBase64);
  }

  /// Factory for failed image generation
  factory FakeImageGeneratorService.failure([String? errorMsg]) {
    return FakeImageGeneratorService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Image generation failed',
    );
  }
}

/// Fake Image Processing Service for testing image operations
class FakeImageProcessorService {
  final bool shouldFail;
  final String errorMessage;

  FakeImageProcessorService({
    this.shouldFail = false,
    this.errorMessage = 'Image processing failed',
  });

  Future<String> processImage({
    required String base64Image,
    Map<String, dynamic>? options,
  }) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    // Return the same image or a processed version
    return base64Image;
  }

  Future<Map<String, dynamic>> analyzeImage({
    required String base64Image,
  }) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    return {'width': 256, 'height': 256, 'format': 'PNG', 'size': 1024};
  }

  factory FakeImageProcessorService.failure([String? errorMsg]) {
    return FakeImageProcessorService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Image processing failed',
    );
  }
}

/// Fake Image Saver Service for testing image saving operations
class FakeImageSaverService {
  static final Map<String, String> _savedImages = <String, String>{};
  final bool shouldFail;
  final String errorMessage;

  FakeImageSaverService({
    this.shouldFail = false,
    this.errorMessage = 'Image save failed',
  });

  static void clear() {
    _savedImages.clear();
  }

  static Map<String, String> get savedImages => Map.from(_savedImages);

  Future<String> saveImage({
    required String base64Image,
    String? filename,
    String? directory,
  }) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    final path =
        '${directory ?? 'images'}/${filename ?? 'image_${DateTime.now().millisecondsSinceEpoch}.png'}';
    _savedImages[path] = base64Image;
    return path;
  }

  Future<bool> deleteImage(String path) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    return _savedImages.remove(path) != null;
  }

  Future<bool> imageExists(String path) async {
    return _savedImages.containsKey(path);
  }

  Future<String?> loadImage(String path) async {
    if (shouldFail) {
      throw Exception(errorMessage);
    }

    return _savedImages[path];
  }

  factory FakeImageSaverService.failure([String? errorMsg]) {
    return FakeImageSaverService(
      shouldFail: true,
      errorMessage: errorMsg ?? 'Image save failed',
    );
  }
}
