import 'dart:typed_data';

/// Domain interface for realtime transport services
/// Defines the contract for real-time communication with AI providers
abstract interface class RealtimeTransportService {
  /// Whether the transport is currently connected
  bool get isConnected;

  /// Connect to the realtime service with provider-specific options
  Future<void> connect({required Map<String, dynamic> options});

  /// Disconnect and cleanup resources
  Future<void> disconnect();

  /// Send a structured event to the transport
  void sendEvent(Map<String, dynamic> event);

  /// Append raw audio bytes for streaming
  void appendAudio(Uint8List bytes);

  /// Force commit (flush) of pending audio buffer
  Future<void> commitAudio();

  /// Message callback field
  void Function(Object message)? onMessage;

  /// Error callback field
  void Function(Object error)? onError;

  /// Completion callback field
  void Function()? onDone;
}
