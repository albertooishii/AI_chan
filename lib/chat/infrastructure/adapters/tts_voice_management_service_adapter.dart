import 'package:ai_chan/chat/domain/interfaces/i_tts_voice_management_service.dart';
import 'package:ai_chan/chat/application/services/tts_voice_management_service.dart';
import 'package:ai_chan/shared.dart';

/// Infrastructure adapter for TTS voice management service
/// Implements the domain interface and delegates to application service
/// PROVIDER-AGNOSTIC: No hardcoded providers
class TtsVoiceManagementServiceAdapter implements ITtsVoiceManagementService {
  /// Constructor with dependency injection
  TtsVoiceManagementServiceAdapter() {
    _applicationService = TtsVoiceManagementService(
      providerManager: AIProviderManager.instance,
    );
  }
  late final TtsVoiceManagementService _applicationService;

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getAvailableVoices({
    final List<String>? languageCodes,
    final bool forceRefresh = false,
  }) => _applicationService.getAvailableVoices(
    languageCodes: languageCodes,
    forceRefresh: forceRefresh,
  );

  @override
  Future<List<Map<String, dynamic>>> getVoicesForProvider(
    final String providerId, {
    final List<String>? languageCodes,
    final bool forceRefresh = false,
  }) => _applicationService.getVoicesForProvider(
    providerId,
    languageCodes: languageCodes,
    forceRefresh: forceRefresh,
  );

  @override
  Future<bool> isProviderAvailable(final String providerId) =>
      _applicationService.isProviderAvailable(providerId);

  @override
  Future<List<String>> getAvailableProviders() =>
      _applicationService.getAvailableProviders();

  @override
  Future<void> clearVoicesCache() => _applicationService.clearVoicesCache();

  @override
  Future<void> clearVoicesCacheForProvider(final String providerId) =>
      _applicationService.clearVoicesCacheForProvider(providerId);

  @override
  Future<int> getCacheSize() => _applicationService.getCacheSize();

  @override
  Future<void> clearAudioCache() => _applicationService.clearAudioCache();

  @override
  String formatCacheSize(final int bytes) =>
      _applicationService.formatCacheSize(bytes);
}
