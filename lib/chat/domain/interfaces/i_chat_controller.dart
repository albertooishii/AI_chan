import 'package:ai_chan/shared.dart';

/// 🎯 **Chat Controller Interface** - Domain Contract
///
/// Define the contract for chat controller operations without
/// depending on specific UI framework implementation.
///
/// **DDD Principles:**
/// - Port pattern: Interface defines what operations are available
/// - Framework independence: No Flutter dependencies
/// - Clean Architecture: Domain layer defines contracts
abstract class IChatController {
  // State getters
  List<Message> get messages;
  AiChanProfile? get profile;

  // Core operations
  Future<void> initialize();
  Future<void> clearMessages();
  Future<void> saveState();
  void dispose();

  // Message operations
  Future<void> sendMessage({
    required final String text,
    final String? model,
    final dynamic image,
  });

  // Sub-controller access (using dynamic to avoid circular dependencies)
  dynamic get dataController;
  dynamic get messageController;
  dynamic get callController;
  dynamic get audioController;
  dynamic get googleController;
}
