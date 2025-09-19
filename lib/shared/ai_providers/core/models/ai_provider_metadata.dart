import 'package:ai_chan/shared.dart';

/// Metadata information about an AI provider.
///
/// Contains comprehensive information about a provider including
/// its capabilities, configuration, rate limits, and other metadata.
class AIProviderMetadata {
  const AIProviderMetadata({
    required this.providerId,
    required this.providerName,
    required this.company,
    required this.version,
    required this.description,
    this.homepageUrl,
    this.documentationUrl,
    required this.supportedCapabilities,
    required this.defaultModels,
    required this.availableModels,
    required this.rateLimits,
    required this.requiresAuthentication,
    required this.requiredConfigKeys,
    this.maxContextTokens,
    this.maxOutputTokens,
    required this.supportsStreaming,
    required this.supportsFunctionCalling,
    this.pricing,
    this.additionalMetadata = const {},
  });

  /// Create metadata from JSON configuration
  factory AIProviderMetadata.fromJson(final Map<String, dynamic> json) {
    // Parse supported capabilities from string identifiers
    final capabilityStrings = List<String>.from(
      json['supported_capabilities'] ?? [],
    );
    final capabilities = AICapabilityUtils.parseCapabilities(capabilityStrings);

    // Parse default models
    final defaultModelsJson = Map<String, dynamic>.from(
      json['default_models'] ?? {},
    );
    final defaultModels = <AICapability, String>{};
    for (final entry in defaultModelsJson.entries) {
      final capability = AICapabilityExtension.fromIdentifier(entry.key);
      if (capability != null) {
        defaultModels[capability] = entry.value.toString();
      }
    }

    // Parse available models
    final availableModelsJson = Map<String, dynamic>.from(
      json['available_models'] ?? {},
    );
    final availableModels = <AICapability, List<String>>{};
    for (final entry in availableModelsJson.entries) {
      final capability = AICapabilityExtension.fromIdentifier(entry.key);
      if (capability != null) {
        availableModels[capability] = List<String>.from(entry.value ?? []);
      }
    }

    return AIProviderMetadata(
      providerId: json['provider_id']?.toString() ?? '',
      providerName: json['provider_name']?.toString() ?? '',
      company: json['company']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      description: json['description']?.toString() ?? '',
      homepageUrl: json['homepage_url']?.toString(),
      documentationUrl: json['documentation_url']?.toString(),
      supportedCapabilities: capabilities,
      defaultModels: defaultModels,
      availableModels: availableModels,
      rateLimits: Map<String, int>.from(json['rate_limits'] ?? {}),
      requiresAuthentication: json['requires_authentication'] == true,
      requiredConfigKeys: List<String>.from(json['required_config_keys'] ?? []),
      maxContextTokens: json['max_context_tokens']?.toInt(),
      maxOutputTokens: json['max_output_tokens']?.toInt(),
      supportsStreaming: json['supports_streaming'] == true,
      supportsFunctionCalling: json['supports_function_calling'] == true,
      pricing: json['pricing'] as Map<String, dynamic>?,
      additionalMetadata: Map<String, dynamic>.from(
        json['additional_metadata'] ?? {},
      ),
    );
  }

  /// Unique identifier for the provider
  final String providerId;

  /// Human-readable name of the provider
  final String providerName;

  /// Provider company/organization name
  final String company;

  /// Version of the provider implementation
  final String version;

  /// Brief description of the provider
  final String description;

  /// Homepage URL for the provider
  final String? homepageUrl;

  /// API documentation URL
  final String? documentationUrl;

  /// List of capabilities this provider supports
  final List<AICapability> supportedCapabilities;

  /// Default models for each capability
  final Map<AICapability, String> defaultModels;

  /// All available models grouped by capability
  final Map<AICapability, List<String>> availableModels;

  /// Rate limit information (requests per minute, tokens per minute, etc.)
  final Map<String, int> rateLimits;

  /// Whether this provider requires authentication
  final bool requiresAuthentication;

  /// List of required configuration keys
  final List<String> requiredConfigKeys;

  /// Maximum context window size (in tokens) for text models
  final int? maxContextTokens;

  /// Maximum tokens that can be generated in a single request
  final int? maxOutputTokens;

  /// Whether the provider supports streaming responses
  final bool supportsStreaming;

  /// Whether the provider supports function calling
  final bool supportsFunctionCalling;

  /// Pricing information (if available)
  final Map<String, dynamic>? pricing;

  /// Additional metadata as key-value pairs
  final Map<String, dynamic> additionalMetadata;

  /// Convert metadata to JSON
  Map<String, dynamic> toJson() {
    return {
      'provider_id': providerId,
      'provider_name': providerName,
      'company': company,
      'version': version,
      'description': description,
      'homepage_url': homepageUrl,
      'documentation_url': documentationUrl,
      'supported_capabilities': AICapabilityUtils.capabilitiesToIdentifiers(
        supportedCapabilities,
      ),
      'default_models': defaultModels.map(
        (final key, final value) => MapEntry(key.identifier, value),
      ),
      'available_models': availableModels.map(
        (final key, final value) => MapEntry(key.identifier, value),
      ),
      'rate_limits': rateLimits,
      'requires_authentication': requiresAuthentication,
      'required_config_keys': requiredConfigKeys,
      'max_context_tokens': maxContextTokens,
      'max_output_tokens': maxOutputTokens,
      'supports_streaming': supportsStreaming,
      'supports_function_calling': supportsFunctionCalling,
      'pricing': pricing,
      'additional_metadata': additionalMetadata,
    };
  }

  /// Check if this provider supports a specific capability
  bool supportsCapability(final AICapability capability) {
    return supportedCapabilities.contains(capability);
  }

  /// Get the default model for a capability
  String? getDefaultModel(final AICapability capability) {
    return defaultModels[capability];
  }

  /// Get available models for a capability
  List<String> getAvailableModels(final AICapability capability) {
    return availableModels[capability] ?? [];
  }

  /// Check if a specific model is supported for a capability
  bool supportsModel(final AICapability capability, final String model) {
    final models = getAvailableModels(capability);
    return models.contains(model);
  }

  /// Create a copy with modified fields
  AIProviderMetadata copyWith({
    final String? providerId,
    final String? providerName,
    final String? company,
    final String? version,
    final String? description,
    final String? homepageUrl,
    final String? documentationUrl,
    final List<AICapability>? supportedCapabilities,
    final Map<AICapability, String>? defaultModels,
    final Map<AICapability, List<String>>? availableModels,
    final Map<String, int>? rateLimits,
    final bool? requiresAuthentication,
    final List<String>? requiredConfigKeys,
    final int? maxContextTokens,
    final int? maxOutputTokens,
    final bool? supportsStreaming,
    final bool? supportsFunctionCalling,
    final Map<String, dynamic>? pricing,
    final Map<String, dynamic>? additionalMetadata,
  }) {
    return AIProviderMetadata(
      providerId: providerId ?? this.providerId,
      providerName: providerName ?? this.providerName,
      company: company ?? this.company,
      version: version ?? this.version,
      description: description ?? this.description,
      homepageUrl: homepageUrl ?? this.homepageUrl,
      documentationUrl: documentationUrl ?? this.documentationUrl,
      supportedCapabilities:
          supportedCapabilities ?? this.supportedCapabilities,
      defaultModels: defaultModels ?? this.defaultModels,
      availableModels: availableModels ?? this.availableModels,
      rateLimits: rateLimits ?? this.rateLimits,
      requiresAuthentication:
          requiresAuthentication ?? this.requiresAuthentication,
      requiredConfigKeys: requiredConfigKeys ?? this.requiredConfigKeys,
      maxContextTokens: maxContextTokens ?? this.maxContextTokens,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      supportsStreaming: supportsStreaming ?? this.supportsStreaming,
      supportsFunctionCalling:
          supportsFunctionCalling ?? this.supportsFunctionCalling,
      pricing: pricing ?? this.pricing,
      additionalMetadata: additionalMetadata ?? this.additionalMetadata,
    );
  }

  @override
  String toString() {
    return 'AIProviderMetadata(providerId: $providerId, providerName: $providerName, company: $company, version: $version)';
  }

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) return true;
    return other is AIProviderMetadata &&
        other.providerId == providerId &&
        other.version == version;
  }

  @override
  int get hashCode => providerId.hashCode ^ version.hashCode;
}
