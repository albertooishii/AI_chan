import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Minimal helper to initialize Firebase using the bundled google-services.json
/// (Android) when running locally. In production you should use platform
/// specific setup per Firebase docs. This helper only attempts a best-effort
/// local initialization for tools and tests.
/// Ensures Firebase is initialized. Returns true on success, false otherwise.
///
/// On desktop platforms (Linux, macOS, Windows), Firebase is disabled by default
/// as it's primarily designed for mobile and web platforms.
Future<bool> ensureFirebaseInitialized() async {
  // Skip Firebase initialization on desktop platforms
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    debugPrint(
      'firebase_init: Skipping Firebase on desktop platform (${Platform.operatingSystem})',
    );
    return false;
  }

  if (Firebase.apps.isNotEmpty) return true;

  // Limit retry attempts to avoid excessive logs
  const maxAttempts = 1;

  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    debugPrint('firebase_init: initialize attempt $attempt/$maxAttempts');
    try {
      // Standard initialize; this will pick up native configuration when
      // running on device/emulator with google-services.json / GoogleService-Info.plist
      await Firebase.initializeApp();
      debugPrint('firebase_init: Firebase initialized successfully');
      return true;
    } catch (e) {
      debugPrint('Firebase.initializeApp() failed: $e');
      if (attempt == maxAttempts) {
        debugPrint('firebase_init: All attempts failed, trying fallback');
      }
      // Continue to fallback attempt on last iteration
    }
  }

  try {
    if (kIsWeb) {
      return false; // web should use default Firebase config in index.html
    }
    final file = File('google-services.json');
    if (!file.existsSync()) {
      debugPrint('firebase_init: google-services.json not found');
      return false;
    }
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final projectInfo = data['project_info'] as Map<String, dynamic>?;
    final clients =
        (data['client'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    String? apiKey;
    String? appId;
    String? projectId;
    if (projectInfo != null) projectId = projectInfo['project_id'] as String?;
    if (clients.isNotEmpty) {
      final first = clients.first;
      final apiKeys = (first['api_key'] as List<dynamic>?)
          ?.cast<Map<String, dynamic>>();
      if (apiKeys != null && apiKeys.isNotEmpty) {
        apiKey = apiKeys.first['current_key'] as String?;
      }
      final clientInfo = first['client_info'] as Map<String, dynamic>?;
      if (clientInfo != null) appId = clientInfo['mobilesdk_app_id'] as String?;
    }

    // Validate that we have the minimal required fields. If not, fail fast.
    if ((apiKey == null || apiKey.isEmpty) ||
        (appId == null || appId.isEmpty) ||
        (projectId == null || projectId.isEmpty)) {
      debugPrint(
        'firebase_init: google-services.json missing required fields apiKey/appId/projectId',
      );
      return false;
    }

    final options = FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: '',
      projectId: projectId,
    );
    await Firebase.initializeApp(options: options);
    debugPrint('firebase_init: Firebase initialized via fallback');
    return true;
  } catch (e) {
    debugPrint('firebase_init fallback failed: $e');
    debugPrint('firebase_init: Firebase initialization completely failed');
    return false;
  }
}
