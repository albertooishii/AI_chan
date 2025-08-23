import 'dart:typed_data';

/// Transport abstraction for realtime providers.
/// Transport implementations handle protocol/transport specifics (WebSocket,
/// gRPC, etc.) and expose raw messages/events to adapters.
abstract class RealtimeTransport {
  /// Whether the transport is currently connected.
  bool get isConnected;

  /// Connect to provider; options are provider-specific.
  Future<void> connect({required Map<String, dynamic> options});

  /// Disconnect and cleanup.
  Future<void> disconnect();

  /// Send a JSON-like event to the transport (will be encoded as needed).
  void sendEvent(Map<String, dynamic> event);

  /// Append raw audio bytes (binary) to the transport.
  void appendAudio(Uint8List bytes);

  /// Force commit (flush) of pending audio buffer.
  Future<void> commitAudio();

  /// Subscribe to raw incoming messages (JSON decoded or binary chunks).
  void Function(Object message)? onMessage;

  /// Error callback
  void Function(Object error)? onError;

  /// Completion callback
  void Function()? onDone;
}
