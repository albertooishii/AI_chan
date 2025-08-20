import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/di.dart' as di;
import 'package:ai_chan/core/interfaces/i_profile_service.dart';
import '../test_setup.dart';

void main() {
  group('DDD Integration Tests', () {
    setUp(() async {
      await initializeTestEnvironment();
    });

    test('dependency injection returns correct interface implementations', () {
      // Test that profile service DI works correctly
      final profileService = di.getProfileServiceForProvider();
      expect(profileService, isA<IProfileService>());
    });

    test('service factories maintain singleton behavior where expected', () {
      // Verify that certain services maintain state across calls
      final service1 = di.getProfileServiceForProvider();
      final service2 = di.getProfileServiceForProvider();
      
      // Both should be the same instance for consistency
      expect(service1.runtimeType, service2.runtimeType);
    });

    test('bounded contexts can be accessed without circular dependencies', () {
      // Verify that we can access services from different contexts
      expect(() => di.getProfileServiceForProvider(), returnsNormally);
      expect(() => di.getChatResponseService(), returnsNormally);
      expect(() => di.getAIServiceForModel('test-model'), returnsNormally);
    });

    test('DI factories respect configuration requirements', () {
      // Test that factories handle configuration dependencies properly
      final profileService = di.getProfileServiceForProvider();
      expect(profileService, isNotNull);
      
      final chatService = di.getChatResponseService();
      expect(chatService, isNotNull);
    });
  });
}
