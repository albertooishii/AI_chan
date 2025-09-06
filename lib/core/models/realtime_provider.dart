/// Enum for realtime audio providers
enum RealtimeProvider { openai, gemini }

/// Extension for RealtimeProvider
extension RealtimeProviderExtension on RealtimeProvider {
  String get name {
    switch (this) {
      case RealtimeProvider.openai:
        return 'openai';
      case RealtimeProvider.gemini:
        return 'gemini';
    }
  }
}

/// Helper functions for RealtimeProvider
class RealtimeProviderHelper {
  static RealtimeProvider fromString(final String value) {
    switch (value.toLowerCase()) {
      case 'openai':
        return RealtimeProvider.openai;
      case 'gemini':
        return RealtimeProvider.gemini;
      default:
        return RealtimeProvider.gemini; // Default fallback
    }
  }
}
