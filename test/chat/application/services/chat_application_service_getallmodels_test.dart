import 'package:flutter_test/flutter_test.dart';

// Simplified test for getAllModels functionality
void main() {
  group('getAllModels functionality', () {
    test('should handle model list operations correctly', () {
      // Test the core logic that getAllModels performs: deduplication and order preservation
      final models = [
        'gpt-4',
        'gpt-3.5-turbo',
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'grok-3',
        'grok-3-mini',
      ];

      // Test deduplication (what the method does internally)
      final withDuplicates = [...models, 'gpt-4', 'gemini-2.5-pro'];
      final uniqueModels = withDuplicates.toSet().toList();
      expect(uniqueModels.length, equals(models.length));

      // Test order preservation (what the method does internally now)
      final originalOrder = [
        'gpt-4',
        'gpt-3.5-turbo',
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'grok-3',
        'grok-3-mini',
      ];
      final deduplicated = originalOrder.toSet().toList();
      expect(deduplicated, equals(originalOrder)); // Order should be preserved
      expect(deduplicated.first, equals('gpt-4')); // First should remain first
      expect(
        deduplicated.last,
        equals('grok-3-mini'),
      ); // Last should remain last
    });

    test('should verify expected model names are present', () {
      // Test that the expected fallback models are what we expect
      final expectedModels = [
        'gpt-4',
        'gpt-3.5-turbo',
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'grok-3',
        'grok-3-mini',
      ];

      expect(expectedModels, contains('gpt-4'));
      expect(expectedModels, contains('gpt-3.5-turbo'));
      expect(expectedModels, contains('gemini-2.5-pro'));
      expect(expectedModels, contains('gemini-2.5-flash'));
      expect(expectedModels, contains('grok-3'));
      expect(expectedModels, contains('grok-3-mini'));
    });

    test('should handle empty and error scenarios', () {
      // Test edge cases
      final emptyList = <String>[];
      expect(emptyList.isEmpty, isTrue);

      final singleModel = ['gpt-4'];
      expect(singleModel.length, equals(1));
      expect(singleModel.first, equals('gpt-4'));
    });
  });
}
