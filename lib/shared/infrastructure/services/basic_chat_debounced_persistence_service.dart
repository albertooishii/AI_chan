import 'package:ai_chan/chat/domain/interfaces/i_chat_debounced_persistence_service.dart';

/// Basic implementation of IChatDebouncedPersistenceService for dependency injection
class BasicChatDebouncedPersistenceService
    implements IChatDebouncedPersistenceService {
  @override
  void trigger() {
    // Basic implementation - do nothing
  }

  @override
  void dispose() {
    // Basic implementation - do nothing
  }
}
