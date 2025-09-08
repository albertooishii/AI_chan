import 'package:ai_chan/chat/domain/interfaces/i_chat_preferences_service.dart';
import 'package:ai_chan/shared/utils/prefs_utils.dart';

/// Infrastructure adapter that implements IChatPreferencesService
/// using the shared preferences utilities.
///
/// This adapter maintains bounded context isolation by implementing
/// the chat domain interface while delegating to shared infrastructure.
class ChatPreferencesServiceAdapter implements IChatPreferencesService {
  @override
  Future<String> getPreferredVoice({final String fallback = 'nova'}) async {
    return await PrefsUtils.getPreferredVoice(fallback: fallback);
  }
}
