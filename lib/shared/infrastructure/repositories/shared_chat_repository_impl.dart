import 'dart:convert';
import 'package:ai_chan/shared.dart';

/// Implementation of shared chat repository using infrastructure services
class SharedChatRepositoryImpl implements ISharedChatRepository {
  static const String _chatDataKey = 'shared_chat_data';

  @override
  Future<void> saveAll(final Map<String, dynamic> exportedJson) async {
    final jsonString = json.encode(exportedJson);
    await PrefsUtils.setRawString(_chatDataKey, jsonString);
  }

  @override
  Future<Map<String, dynamic>?> loadAll() async {
    final jsonString = await PrefsUtils.getRawString(_chatDataKey);
    if (jsonString == null || jsonString.isEmpty) {
      return null;
    }

    try {
      return json.decode(jsonString) as Map<String, dynamic>;
    } on FormatException catch (e) {
      Log.e('Failed to parse saved chat data: $e');
      return null;
    }
  }

  @override
  Future<void> clearAll() async {
    await PrefsUtils.removeKey(_chatDataKey);
  }

  @override
  Future<String> exportAllToJson(
    final Map<String, dynamic> exportedJson,
  ) async {
    return json.encode(exportedJson);
  }

  @override
  Future<Map<String, dynamic>?> importAllFromJson(final String jsonStr) async {
    try {
      return json.decode(jsonStr) as Map<String, dynamic>;
    } on FormatException catch (e) {
      Log.e('Failed to parse JSON for import: $e');
      return null;
    }
  }
}
