import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Simple logging utility
class Log {
  static bool get _debugEnabled {
    return dotenv.env['APP_DEBUG_LOGS']?.toLowerCase() == 'true' || kDebugMode;
  }

  /// Debug log
  static void d(String message) {
    if (_debugEnabled) {
      debugPrint('[DEBUG] $message');
    }
  }

  /// Error log
  static void e(String message) {
    if (_debugEnabled) {
      debugPrint('[ERROR] $message');
    }
  }

  /// Info log
  static void i(String message) {
    if (_debugEnabled) {
      debugPrint('[INFO] $message');
    }
  }

  /// Warning log
  static void w(String message) {
    if (_debugEnabled) {
      debugPrint('[WARNING] $message');
    }
  }
}
