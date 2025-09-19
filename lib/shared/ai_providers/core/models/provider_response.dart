/// Internal response returned by providers to the `AIProviderManager`.
///
/// Providers MUST return semantic fields (`text`, `seed`, `prompt`) and MAY
/// return raw binary payloads as base64 (`imageBase64` / `audioBase64`). The
/// `AIProviderManager` is responsible for persisting those payloads and
/// exposing final filenames via the returned `AIResponse` when applicable.
class ProviderResponse {
  ProviderResponse({
    required this.text,
    this.seed = '',
    this.prompt = '',
    this.imageBase64,
    this.audioBase64,
  });

  /// Semantic response text from the provider
  final String text;

  /// Optional seed or response identifier returned by provider
  final String seed;

  /// Optional revised prompt or image prompt metadata
  final String prompt;

  /// Optional image payload encoded as base64 (may be a data URI)
  final String? imageBase64;

  /// Optional audio payload encoded as base64 (no data URI expected)
  final String? audioBase64;
}
