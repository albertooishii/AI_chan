/// 🎯 **Chat Queued Send Options** - Domain Model for Queued Message Options
///
/// Defines the structure for options when queuing messages within the chat bounded context.
/// This ensures bounded context isolation while providing message queuing options.
///
/// **Clean Architecture Compliance:**
/// ✅ Chat domain defines its own models
/// ✅ No direct dependencies on shared context
/// ✅ Bounded context isolation maintained
class ChatQueuedSendOptions {
  /// Constructor
  const ChatQueuedSendOptions({
    this.model,
    this.callPrompt,
    this.image,
    this.imageMimeType,
    this.preTranscribedText,
    this.userAudioPath,
  });

  /// The model to use for sending
  final String? model;

  /// Call prompt for the message
  final String? callPrompt;

  /// Image data for the message
  final dynamic image;

  /// MIME type of the image
  final String? imageMimeType;

  /// Pre-transcribed text
  final String? preTranscribedText;

  /// User audio path
  final String? userAudioPath;
}
