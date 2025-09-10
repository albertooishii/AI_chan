import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_provider_metadata.dart';
import 'package:ai_chan/core/models/ai_response.dart';
import 'package:ai_chan/core/models/system_prompt.dart';
import 'package:ai_chan/core/interfaces/i_realtime_client.dart';
import 'dart:typed_data';

/// Core interface for all AI providers in the dynamic provider system.
///
/// This interface defines the contract that all AI providers must implement
/// to participate in the plugin architecture system. Providers can support
/// different capabilities like text generation, image generation, etc.
abstract class IAIProvider {
  /// Unique identifier for this provider (e.g., "openai", "google", "xai")
  String get providerId;

  /// Human-readable name for this provider
  String get providerName;

  /// Version of this provider implementation
  String get version;

  /// Metadata about this provider including supported capabilities
  AIProviderMetadata get metadata;

  /// List of capabilities this provider supports
  List<AICapability> get supportedCapabilities;

  /// List of models available for each capability
  Map<AICapability, List<String>> get availableModels;

  /// Initialize the provider with configuration
  /// Returns true if initialization was successful
  Future<bool> initialize(final Map<String, dynamic> config);

  /// Check if provider is currently healthy and available
  Future<bool> isHealthy();

  /// Check if provider supports a specific capability
  bool supportsCapability(final AICapability capability);

  /// Check if provider supports a specific model for a capability
  bool supportsModel(final AICapability capability, final String model);

  /// Get the default model for a specific capability
  String? getDefaultModel(final AICapability capability);

  /// Send a message/request to the AI provider
  ///
  /// [history] - Previous conversation messages
  /// [systemPrompt] - System prompt with instructions
  /// [model] - Specific model to use (if null, uses default for capability)
  /// [capability] - The AI capability being requested
  /// [imageBase64] - Optional base64 encoded image for vision tasks
  /// [imageMimeType] - MIME type of the image
  /// [additionalParams] - Provider-specific parameters
  Future<AIResponse> sendMessage({
    required final List<Map<String, String>> history,
    required final SystemPrompt systemPrompt,
    required final AICapability capability,
    final String? model,
    final String? imageBase64,
    final String? imageMimeType,
    final Map<String, dynamic>? additionalParams,
  });

  /// Get available models for a specific capability
  /// This may involve API calls to get real-time model availability
  Future<List<String>> getAvailableModelsForCapability(
    final AICapability capability,
  );

  /// Get rate limit information for this provider
  Map<String, int> getRateLimits();

  /// Generate audio from text (Text-to-Speech)
  /// [text] - Text to convert to speech
  /// [voice] - Voice to use (provider-specific)
  /// [model] - TTS model to use
  /// [additionalParams] - Provider-specific parameters (speed, format, etc.)
  /// Returns AIResponse with base64 encoded audio data
  Future<AIResponse> generateAudio({
    required final String text,
    final String? voice,
    final String? model,
    final Map<String, dynamic>? additionalParams,
  });

  /// Transcribe audio to text (Speech-to-Text)
  /// [audioBase64] - Base64 encoded audio data
  /// [audioFormat] - Audio format (mp3, wav, etc.)
  /// [model] - STT model to use
  /// [language] - Language code for transcription
  /// [additionalParams] - Provider-specific parameters
  /// Returns AIResponse with transcribed text
  Future<AIResponse> transcribeAudio({
    required final String audioBase64,
    final String? audioFormat,
    final String? model,
    final String? language,
    final Map<String, dynamic>? additionalParams,
  });

  /// Create a realtime client for real-time conversation
  /// Returns null if this provider doesn't support realtime for the given model
  ///
  /// [model] - Specific model to use for realtime (if null, uses default)
  /// [onText] - Callback for text responses from the AI
  /// [onAudio] - Callback for audio responses from the AI
  /// [onCompleted] - Callback when response is completed
  /// [onError] - Callback for errors
  /// [onUserTranscription] - Callback for user speech transcription
  /// [additionalParams] - Provider-specific parameters
  IRealtimeClient? createRealtimeClient({
    final String? model,
    final void Function(String)? onText,
    final void Function(Uint8List)? onAudio,
    final void Function()? onCompleted,
    final void Function(Object)? onError,
    final void Function(String)? onUserTranscription,
    final Map<String, dynamic>? additionalParams,
  });

  /// Check if this provider supports realtime conversation for a specific model
  /// [model] - Model to check (if null, checks if provider supports realtime at all)
  bool supportsRealtimeForModel(final String? model);

  /// Get available realtime models for this provider
  /// Returns list of model IDs that support realtime conversation
  List<String> getAvailableRealtimeModels();

  /// Dispose of any resources used by this provider
  Future<void> dispose();
}
