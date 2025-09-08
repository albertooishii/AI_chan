/// Enumeration of AI capabilities that providers can support.
///
/// This enum defines all the different types of AI capabilities that
/// can be provided by AI services in our dynamic provider system.
enum AICapability {
  /// Text generation capabilities (ChatGPT, Gemini text, Grok, etc.)
  textGeneration,

  /// Image generation capabilities (DALL-E, Imagen, etc.)
  imageGeneration,

  /// Image analysis/vision capabilities (GPT-4 Vision, Gemini Vision, etc.)
  imageAnalysis,

  /// Audio generation capabilities (text-to-speech, music generation, etc.)
  audioGeneration,

  /// Audio transcription capabilities (speech-to-text)
  audioTranscription,

  /// Embedding generation capabilities (text embeddings, image embeddings)
  embeddingGeneration,

  /// Code generation and analysis capabilities
  codeGeneration,

  /// Function calling capabilities (structured outputs, tool use)
  functionCalling,

  /// Real-time conversation capabilities
  realtimeConversation,

  /// Document analysis capabilities (PDF, document understanding)
  documentAnalysis,
}

/// Extension methods for AICapability enum
extension AICapabilityExtension on AICapability {
  /// Get a human-readable name for the capability
  String get displayName {
    switch (this) {
      case AICapability.textGeneration:
        return 'Text Generation';
      case AICapability.imageGeneration:
        return 'Image Generation';
      case AICapability.imageAnalysis:
        return 'Image Analysis';
      case AICapability.audioGeneration:
        return 'Audio Generation';
      case AICapability.audioTranscription:
        return 'Audio Transcription';
      case AICapability.embeddingGeneration:
        return 'Embedding Generation';
      case AICapability.codeGeneration:
        return 'Code Generation';
      case AICapability.functionCalling:
        return 'Function Calling';
      case AICapability.realtimeConversation:
        return 'Realtime Conversation';
      case AICapability.documentAnalysis:
        return 'Document Analysis';
    }
  }

  /// Get a string identifier for the capability (used in configuration)
  String get identifier {
    switch (this) {
      case AICapability.textGeneration:
        return 'text_generation';
      case AICapability.imageGeneration:
        return 'image_generation';
      case AICapability.imageAnalysis:
        return 'image_analysis';
      case AICapability.audioGeneration:
        return 'audio_generation';
      case AICapability.audioTranscription:
        return 'audio_transcription';
      case AICapability.embeddingGeneration:
        return 'embedding_generation';
      case AICapability.codeGeneration:
        return 'code_generation';
      case AICapability.functionCalling:
        return 'function_calling';
      case AICapability.realtimeConversation:
        return 'realtime_conversation';
      case AICapability.documentAnalysis:
        return 'document_analysis';
    }
  }

  /// Parse capability from string identifier
  static AICapability? fromIdentifier(final String identifier) {
    for (final capability in AICapability.values) {
      if (capability.identifier == identifier) {
        return capability;
      }
    }
    return null;
  }
}

/// Utility class for working with AI capabilities
class AICapabilityUtils {
  /// Get all capabilities as string identifiers
  static List<String> getAllIdentifiers() {
    return AICapability.values.map((final c) => c.identifier).toList();
  }

  /// Parse list of capability identifiers from strings
  static List<AICapability> parseCapabilities(final List<String> identifiers) {
    final capabilities = <AICapability>[];
    for (final identifier in identifiers) {
      final capability = AICapabilityExtension.fromIdentifier(identifier);
      if (capability != null) {
        capabilities.add(capability);
      }
    }
    return capabilities;
  }

  /// Convert capabilities to string identifiers
  static List<String> capabilitiesToIdentifiers(
    final List<AICapability> capabilities,
  ) {
    return capabilities.map((final c) => c.identifier).toList();
  }

  /// Check if a capability requires specific model types
  static bool requiresSpecializedModel(final AICapability capability) {
    switch (capability) {
      case AICapability.imageGeneration:
      case AICapability.imageAnalysis:
      case AICapability.audioGeneration:
      case AICapability.audioTranscription:
      case AICapability.embeddingGeneration:
        return true;
      case AICapability.textGeneration:
      case AICapability.codeGeneration:
      case AICapability.functionCalling:
      case AICapability.realtimeConversation:
      case AICapability.documentAnalysis:
        return false;
    }
  }
}
