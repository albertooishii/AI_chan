/// Service responsible for sanitizing and cleaning message content
class MessageSanitizationService {
  /// Sanitize message by removing forbidden tags and cleaning content
  String sanitizeMessage(String text) {
    // Remove any tags that are not in the allowed list
    String sanitized = text.replaceAll(RegExp(r'\[(?!/?(?:audio|img_caption|call|end_call)\b)[^\]\[]+\]'), '');

    return sanitized.trim();
  }

  /// Check if response indicates an API error that should throw exception
  bool isApiError(String text) {
    final errorPatterns = [
      RegExp(r'error.*\d{3}'), // HTTP error codes
      RegExp(r'unknown variant'), // Deserialization errors
      RegExp(r'failed to deserialize'), // JSON errors
      RegExp(r'invalid.*request'), // Invalid requests
      RegExp(r'unauthorized'), // Unauthorized
      RegExp(r'forbidden'), // Forbidden
      RegExp(r'rate limit'), // Rate limit
      RegExp(r'quota exceeded'), // Quota exceeded
      RegExp(r'insufficient.*funds'), // Insufficient funds
    ];

    return errorPatterns.any((pattern) => pattern.hasMatch(text.toLowerCase()));
  }
}
