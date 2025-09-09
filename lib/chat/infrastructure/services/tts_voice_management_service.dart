import 'dart:io';
import 'package:ai_chan/chat/domain/interfaces/i_tts_voice_management_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ai_chan/core/config.dart';

/// Infrastructure implementation of TTS voice management service
/// Implements the domain interface for voice-related operations
class TtsVoiceManagementService implements ITtsVoiceManagementService {
  final FlutterTts _flutterTts = FlutterTts();

  // Cache for voices to avoid repeated API calls
  List<Map<String, dynamic>>? _cachedAndroidVoices;
  List<Map<String, dynamic>>? _cachedGoogleVoices;
  List<Map<String, dynamic>>? _cachedOpenAiVoices;

  @override
  Future<List<Map<String, dynamic>>> getAndroidNativeVoices({
    final List<String>? userLangCodes,
    final List<String>? aiLangCodes,
  }) async {
    try {
      if (_cachedAndroidVoices != null) {
        return _cachedAndroidVoices!;
      }

      if (!Platform.isAndroid) {
        return [];
      }

      final voices = await _flutterTts.getVoices;
      if (voices == null) {
        return [];
      }

      final voiceList = List<Map<String, dynamic>>.from(voices);

      // Filter by language codes if provided
      List<Map<String, dynamic>> filteredVoices = voiceList;

      if (userLangCodes != null || aiLangCodes != null) {
        final allLangCodes = <String>{...?userLangCodes, ...?aiLangCodes};

        filteredVoices = voiceList.where((final voice) {
          final locale = voice['locale'] as String?;
          if (locale == null) return false;

          return allLangCodes.any(
            (final lang) => locale.toLowerCase().startsWith(lang.toLowerCase()),
          );
        }).toList();
      }

      _cachedAndroidVoices = filteredVoices;
      return filteredVoices;
    } on Exception {
      return [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getGoogleVoices({
    final bool forceRefresh = false,
  }) async {
    try {
      if (!forceRefresh && _cachedGoogleVoices != null) {
        return _cachedGoogleVoices!;
      }

      if (!isGoogleTtsConfigured()) {
        return [];
      }

      // TODO: Implement Google Cloud TTS API call
      // For now, return mock data for testing
      final googleVoices = <Map<String, dynamic>>[
        {
          'name': 'es-ES-Neural2-A',
          'displayName': 'es-ES-Neural2-A (Spanish)',
          'languageCodes': ['es-ES'],
          'ssmlGender': 'FEMALE',
        },
        {
          'name': 'en-US-Neural2-D',
          'displayName': 'en-US-Neural2-D (English)',
          'languageCodes': ['en-US'],
          'ssmlGender': 'MALE',
        },
      ];

      _cachedGoogleVoices = googleVoices;
      return googleVoices;
    } on Exception {
      return [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getOpenAiVoices() async {
    try {
      if (_cachedOpenAiVoices != null) {
        return _cachedOpenAiVoices!;
      }

      // OpenAI TTS voices are predefined
      final openAiVoices = <Map<String, dynamic>>[
        {
          'name': 'alloy',
          'displayName': 'Alloy',
          'description': 'Neutral, balanced voice',
          'languageCodes': ['en-US', 'es-ES'],
        },
        {
          'name': 'echo',
          'displayName': 'Echo',
          'description': 'Male voice',
          'languageCodes': ['en-US', 'es-ES'],
        },
        {
          'name': 'fable',
          'displayName': 'Fable',
          'description': 'British accent',
          'languageCodes': ['en-US', 'es-ES'],
        },
        {
          'name': 'onyx',
          'displayName': 'Onyx',
          'description': 'Deep male voice',
          'languageCodes': ['en-US', 'es-ES'],
        },
        {
          'name': 'nova',
          'displayName': 'Nova',
          'description': 'Young female voice',
          'languageCodes': ['en-US', 'es-ES'],
        },
        {
          'name': 'shimmer',
          'displayName': 'Shimmer',
          'description': 'Warm female voice',
          'languageCodes': ['en-US', 'es-ES'],
        },
      ];

      _cachedOpenAiVoices = openAiVoices;
      return openAiVoices;
    } on Exception {
      return [];
    }
  }

  @override
  bool isAndroidNativeTtsAvailable() {
    return Platform.isAndroid;
  }

  @override
  bool isGoogleTtsConfigured() {
    try {
      final googleCredentials = Config.get(
        'GOOGLE_APPLICATION_CREDENTIALS',
        '',
      );
      return googleCredentials.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> clearVoicesCache() async {
    try {
      _cachedAndroidVoices = null;
      _cachedGoogleVoices = null;
      _cachedOpenAiVoices = null;
    } on Exception {
      // Silently handle cache clearing errors
    }
  }

  @override
  Future<int> getCacheSize() async {
    try {
      // Calculate approximate cache size
      int size = 0;

      if (_cachedAndroidVoices != null) {
        size +=
            _cachedAndroidVoices!.length * 100; // Approximate bytes per voice
      }

      if (_cachedGoogleVoices != null) {
        size += _cachedGoogleVoices!.length * 100;
      }

      if (_cachedOpenAiVoices != null) {
        size += _cachedOpenAiVoices!.length * 100;
      }

      return size;
    } on Exception {
      return 0;
    }
  }

  @override
  Future<void> clearAudioCache() async {
    try {
      // TODO: Implement audio cache clearing logic
      // This would clear cached TTS audio files
    } on Exception {
      // Silently handle audio cache clearing errors
    }
  }

  @override
  String formatCacheSize(final int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
