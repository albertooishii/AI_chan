import 'dart:convert';

import 'package:ai_chan/shared.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';

/// Utilities for serializing/parsing chat exports independent of ChatProvider.
class BackupUtils {
  /// Serialize a ChatExport to JSON. If [repository] is provided, delegate
  /// to it (some repos may return a path instead of raw JSON).
  static Future<String> exportImportedChatToJson(
    final ChatExport chat, {
    final IChatRepository? repository,
  }) async {
    final map = chat.toJson();
    if (repository != null) {
      try {
        return await repository.exportAllToJson(map);
      } on Exception catch (_) {}
    }
    final encoder = const JsonEncoder.withIndent('  ');
    return encoder.convert(map);
  }

  /// Construct a ChatExport from raw pieces and export to JSON.
  static Future<String> exportChatPartsToJson({
    required final AiChanProfile profile,
    required final List<Message> messages,
    required final List<ChatEvent> events,
    required final List<TimelineEntry> timeline,
    final IChatRepository? repository,
  }) async {
    final imported = ChatExport(
      profile: profile,
      messages: messages,
      events: events,
      timeline: timeline,
    );
    return await exportImportedChatToJson(imported, repository: repository);
  }
}
