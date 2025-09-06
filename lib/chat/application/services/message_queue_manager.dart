import 'dart:async';

class QueuedSendOptions {
  QueuedSendOptions({
    this.model,
    this.callPrompt,
    this.image,
    this.imageMimeType,
    this.preTranscribedText,
    this.userAudioPath,
  });
  final String? model;
  final String? callPrompt;
  final dynamic image;
  final String? imageMimeType;
  final String? preTranscribedText;
  final String? userAudioPath;
}

/// Manages a queue of localIds representing messages pending automatic send.
/// It only exposes an API to enqueue and flush; actual sending is delegated
/// to the provided callback `onFlush` which receives the last enqueued localId
/// and the last provided options.
class MessageQueueManager {
  MessageQueueManager({
    required this.onFlush,
    this.queuedSendDelay = const Duration(seconds: 5),
  });
  final Duration queuedSendDelay;
  // onFlush receives the full list of queued ids (in order), the last id and the options
  // that were associated with the last enqueued message.
  final void Function(
    List<String> ids,
    String lastLocalId,
    QueuedSendOptions? options,
  )
  onFlush;

  final List<String> _queued = [];
  QueuedSendOptions? _options;
  Timer? _timer;

  int get queuedCount => _queued.length;

  void enqueue(final String localId, {final QueuedSendOptions? options}) {
    if (!_queued.contains(localId)) _queued.add(localId);
    if (options != null) _options = options;
    _startOrResetTimer();
  }

  void _startOrResetTimer() {
    _timer?.cancel();
    if (_queued.isEmpty) return;
    _timer = Timer(queuedSendDelay, () {
      _flushInternal();
    });
  }

  /// Ensures the internal timer is running if there are queued items.
  void ensureTimer() => _startOrResetTimer();

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _flushInternal() {
    if (_queued.isEmpty) return;
    final ids = List<String>.from(_queued);
    _queued.clear();
    final last = ids.isNotEmpty ? ids.last : null;
    final opts = _options;
    _options = null;
    if (last != null) {
      try {
        onFlush(ids, last, opts);
      } on Exception catch (_) {}
    }
  }

  /// Force immediate flush; does not wait for timer. Will call onFlush synchronously.
  void flushNow() {
    _timer?.cancel();
    _flushInternal();
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _queued.clear();
    _options = null;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
