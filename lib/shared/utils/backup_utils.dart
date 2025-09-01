import 'dart:convert';

import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';

/// Utilities for serializing/parsing chat exports independent of ChatProvider.
class BackupUtils {
  /// Serialize an ImportedChat to JSON. If [repository] is provided, delegate
  /// to it (some repos may return a path instead of raw JSON).
  static Future<String> exportImportedChatToJson(
    ImportedChat chat, {
    IChatRepository? repository,
  }) async {
    final map = chat.toJson();
    if (repository != null) {
      try {
        return await repository.exportAllToJson(map);
      } catch (_) {}
    }
    final encoder = const JsonEncoder.withIndent('  ');
    return encoder.convert(map);
  }

  /// Construct an ImportedChat from raw pieces and export to JSON.
  static Future<String> exportChatPartsToJson({
    required AiChanProfile profile,
    required List<Message> messages,
    required List<EventEntry> events,
    IChatRepository? repository,
  }) async {
    final imported = ImportedChat(
      profile: profile,
      messages: messages,
      events: events,
    );
    return await exportImportedChatToJson(imported, repository: repository);
  }
}
