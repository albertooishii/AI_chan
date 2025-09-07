import 'package:ai_chan/chat/domain/interfaces/i_chat_promise_service.dart';

/// Basic implementation of IChatPromiseService for dependency injection
class BasicChatPromiseService implements IChatPromiseService {
  @override
  Future<T> execute<T>(final Future<T> Function() operation) async {
    return await operation();
  }

  @override
  Future<List<T>> executeAll<T>(
    final List<Future<T> Function()> operations,
  ) async {
    return await Future.wait(operations.map((final op) => op()));
  }

  @override
  Future<void> delay(final Duration duration) async {
    await Future.delayed(duration);
  }

  @override
  Future<T> timeout<T>(
    final Future<T> Function() operation,
    final Duration timeout,
  ) async {
    return await operation().timeout(timeout);
  }

  @override
  void schedulePromiseEvent(final dynamic event) {
    // Basic implementation - do nothing
  }

  @override
  void restoreFromEvents() {
    // Basic implementation - do nothing
  }

  @override
  void analyzeAfterIaMessage(final List<dynamic> messages) {
    // Basic implementation - do nothing
  }

  @override
  void dispose() {
    // Basic implementation - do nothing
  }
}
