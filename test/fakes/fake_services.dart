// Centralized export for all fake services
// Import this file to get access to all fake implementations

// AI Services
export 'fake_ai_service.dart';

// Audio & Voice Services
export 'fake_voice_services.dart';

// Chat Services
export 'fake_chat_response_service.dart';
export 'fake_realtime_client.dart';

// Configuration Services
export 'fake_config_services.dart';

// Image Services
export 'fake_image_services.dart';

// Network Services
export 'fake_network_services.dart';

// Storage Services
export 'fake_storage_services.dart';

// Appearance Generator (from onboarding context)
export 'fake_appearance_generator.dart';

/// Available fake services:
///
/// AI Services:
/// - FakeAIService (with factories: forBiography(), forAppearance(), withError())
///
/// Voice Services:
/// - FakeTTSService (with factory: failure())
/// - FakeSTTService (with factory: failure())
///
/// Chat Services:
/// - FakeChatResponseService (with factory: withError())
/// - FakeRealtimeClient
///
/// Configuration Services:
/// - FakeConfigService (with factories: withDefaults(), failure())
/// - FakeSettingsRepository (with factory: failure())
/// - FakeThemeService (with factories: dark(), failure())
///
/// Image Services:
/// - FakeImageGeneratorService (with factories: success(), failure())
/// - FakeImageProcessorService (with factory: failure())
/// - FakeImageSaverService (with factory: failure())
///
/// Network Services:
/// - FakeNetworkService (with factories: offline(), failure())
/// - FakeHttpClient (with factories: slow(), failure(), notFound(), unauthorized())
/// - FakeWebSocketClient (with factory: failure())
///
/// Storage Services:
/// - FakeSharedPreferences (with factory: failure())
/// - FakeCacheService (with factory: failure())
/// - FakeFileStorage (with factory: failure())
///
/// Specialized Services:
/// - FakeAppearanceGenerator
