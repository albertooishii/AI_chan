import 'dart:convert';

import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/chat/domain/interfaces/i_chat_repository.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';
import 'package:ai_chan/shared/utils/storage_utils.dart';
import 'package:ai_chan/shared/utils/log_utils.dart';

class ProviderPersistUtils {
  /// Persist an ImportedChat using the provided repository if available,
  /// falling back to SharedPreferences via StorageUtils.
  static Future<void> saveImportedChat(ImportedChat imported, {IChatRepository? repository}) async {
    if (repository != null) {
      try {
        await repository.saveAll(imported.toJson());
        return;
      } catch (e) {
        Log.w('IChatRepository.saveAll failed, falling back to SharedPreferences: $e', tag: 'PERSIST');
      }
    }

    try {
      await StorageUtils.saveImportedChatToPrefs(imported);
    } catch (e) {
      Log.w('StorageUtils.saveImportedChatToPrefs failed: $e', tag: 'PERSIST');
    }
  }

  /// Lightweight loader: try repository first, then prefs; returns null if nothing found or parse fails.
  static Future<ImportedChat?> loadImportedChat({IChatRepository? repository}) async {
    if (repository != null) {
      try {
        final Map<String, dynamic>? data = await repository.loadAll();
        if (data != null) return ImportedChat.fromJson(data);
      } catch (e) {
        Log.w('IChatRepository.loadAll failed, falling back to Prefs: $e', tag: 'PERSIST');
      }
    }

    try {
      final bioString = await PrefsUtils.getOnboardingData();
      final jsonString = await PrefsUtils.getChatHistory();
      final eventsString = await PrefsUtils.getEvents();
      if (bioString == null && jsonString == null && eventsString == null) return null;
      final profile = bioString != null
          ? AiChanProfile.fromJson(jsonDecode(bioString))
          : AiChanProfile(
              userName: '',
              aiName: '',
              userBirthday: null,
              aiBirthday: null,
              biography: <String, dynamic>{},
              appearance: <String, dynamic>{},
              timeline: <TimelineEntry>[],
            );
      final messages = <Message>[];
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        for (var e in jsonList) {
          messages.add(Message.fromJson(e));
        }
      }
      final events = <EventEntry>[];
      if (eventsString != null) {
        final List<dynamic> ev = jsonDecode(eventsString);
        for (var e in ev) {
          events.add(EventEntry.fromJson(e));
        }
      }
      return ImportedChat(profile: profile, messages: messages, events: events);
    } catch (e) {
      Log.w('Failed to load ImportedChat from prefs: $e', tag: 'PERSIST');
      return null;
    }
  }
}
