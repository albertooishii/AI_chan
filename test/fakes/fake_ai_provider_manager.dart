import 'package:ai_chan/shared/domain/models/index.dart';
import 'package:ai_chan/shared/ai_providers/core/models/ai_capability.dart';
import 'package:ai_chan/shared/ai_providers/core/models/provider_response.dart';

/// Fake implementation of AIProviderManager for testing onboarding flows
class FakeAIProviderManager {
  /// Create a fake instance with custom response
  factory FakeAIProviderManager.withResponse(Map<String, dynamic>? response) {
    _customResponse = response;
    _shouldFail = response == null;
    _instance ??= FakeAIProviderManager._internal();
    return _instance!;
  }

  FakeAIProviderManager._internal();
  static FakeAIProviderManager? _instance;
  static Map<String, dynamic>? _customResponse;
  static bool _shouldFail = false;

  /// Reset the fake instance
  static void reset() {
    _instance = null;
    _customResponse = null;
    _shouldFail = false;
  }

  Future<ProviderResponse> sendMessage({
    required List<Map<String, String>> history,
    required SystemPrompt systemPrompt,
    required AICapability capability,
    String? preferredProviderId,
    String? preferredModel,
    String? imageBase64,
    String? imageMimeType,
    Map<String, dynamic>? additionalParams,
  }) async {
    if (_shouldFail) {
      throw Exception('Simulated AI failure for testing');
    }

    if (_customResponse != null) {
      // If test provided an explicit file name, include it in the simulated response
      return ProviderResponse(
        text:
            '{"dataType":"${_customResponse!['dataType']}","extractedValue":"${_customResponse!['extractedValue']}","aiResponse":"${_customResponse!['aiResponse']}","confidence":${_customResponse!['confidence'] ?? 0.9}}',
      );
    }

    // Default fake response
    return ProviderResponse(
      text:
          '{"dataType":"userName","extractedValue":"Test User","aiResponse":"Hello Test User","confidence":0.9}',
    );
  }

  Future<List<String>> getAvailableModels(
    AICapability capability, {
    String? providerId,
  }) async {
    return ['fake-model'];
  }

  bool get isInitialized => true;
}
