import 'package:ai_chan/chat/domain/interfaces/i_chat_message_queue_manager.dart';
import 'package:ai_chan/chat/domain/models/chat_queued_send_options.dart';
import 'package:ai_chan/chat/application/services/message_queue_manager.dart';

/// Complete implementation of IChatMessageQueueManager using MessageQueueManager
class CompleteChatMessageQueueManager implements IChatMessageQueueManager {
  CompleteChatMessageQueueManager({
    final Duration queuedSendDelay = const Duration(seconds: 5),
  }) : _queuedSendDelay = queuedSendDelay;

  final Duration _queuedSendDelay;
  late final MessageQueueManager _messageQueueManager;
  bool _isInitialized = false;

  void setOnFlushCallback(
    final void Function(
      List<String> ids,
      String lastLocalId,
      ChatQueuedSendOptions? options,
    )
    callback,
  ) {
    if (_isInitialized) return; // Prevent re-initialization

    _messageQueueManager = MessageQueueManager(
      onFlush: (final ids, final lastLocalId, final options) =>
          _handleFlush(ids, lastLocalId, options),
      queuedSendDelay: _queuedSendDelay,
    );
    _onFlushCallback = callback;
    _isInitialized = true;
  }

  void _handleFlush(
    final List<String> ids,
    final String lastLocalId,
    final QueuedSendOptions? options,
  ) {
    if (_onFlushCallback == null) return;

    // Convert QueuedSendOptions to ChatQueuedSendOptions
    ChatQueuedSendOptions? chatOptions;
    if (options != null) {
      chatOptions = ChatQueuedSendOptions(
        callPrompt: options.callPrompt,
        image: options.image,
        imageMimeType: options.imageMimeType,
        preTranscribedText: options.preTranscribedText,
        userAudioPath: options.userAudioPath,
      );
    }

    _onFlushCallback!(ids, lastLocalId, chatOptions);
  }

  void Function(
    List<String> ids,
    String lastLocalId,
    ChatQueuedSendOptions? options,
  )?
  _onFlushCallback;

  @override
  int get queuedCount => _isInitialized ? _messageQueueManager.queuedCount : 0;

  @override
  void enqueue(final String messageId, {final ChatQueuedSendOptions? options}) {
    if (!_isInitialized) return; // Don't enqueue if not initialized

    // Convert ChatQueuedSendOptions to QueuedSendOptions
    QueuedSendOptions? queueOptions;
    if (options != null) {
      queueOptions = QueuedSendOptions(
        callPrompt: options.callPrompt,
        image: options.image,
        imageMimeType: options.imageMimeType,
        preTranscribedText: options.preTranscribedText,
        userAudioPath: options.userAudioPath,
      );
    }

    _messageQueueManager.enqueue(messageId, options: queueOptions);
  }

  @override
  void cancelTimer() {
    if (_isInitialized) {
      _messageQueueManager.cancelTimer();
    }
  }

  @override
  void ensureTimer() {
    if (_isInitialized) {
      _messageQueueManager.ensureTimer();
    }
  }

  @override
  void flushNow() {
    if (_isInitialized) {
      _messageQueueManager.flushNow();
    }
  }

  @override
  void dispose() {
    if (_isInitialized) {
      _messageQueueManager.dispose();
    }
  }
}

/// Basic implementation of IChatMessageQueueManager for dependency injection
class BasicChatMessageQueueManager implements IChatMessageQueueManager {
  @override
  int get queuedCount => 0;

  @override
  void enqueue(final String messageId, {final ChatQueuedSendOptions? options}) {
    // Basic implementation - do nothing
  }

  @override
  void cancelTimer() {
    // Basic implementation - do nothing
  }

  @override
  void ensureTimer() {
    // Basic implementation - do nothing
  }

  @override
  void flushNow() {
    // Basic implementation - do nothing
  }

  @override
  void dispose() {
    // Basic implementation - do nothing
  }
}
