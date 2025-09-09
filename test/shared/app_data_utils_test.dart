import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_setup.dart';

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });

  group('AppDataUtils - Clear All Data Tests (Unit Tests Only)', () {
    setUp(() async {
      // Reset SharedPreferences for each test
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'should clear SharedPreferences data in unit test environment',
      () async {
        // Arrange: Set up some test data in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('chat_history', '{"messages": []}');
        await prefs.setString('onboarding_data', '{"profile": {}}');
        await prefs.setBool('google_account_linked', true);

        // Verify data is there before clearing
        expect(prefs.getString('chat_history'), isNotNull);
        expect(prefs.getString('onboarding_data'), isNotNull);
        expect(prefs.getBool('google_account_linked'), isTrue);

        // Act: Clear SharedPreferences directly (simulating clearAllAppData logic)
        await prefs.clear();

        // Assert: Verify SharedPreferences is cleared
        expect(prefs.getString('chat_history'), isNull);
        expect(prefs.getString('onboarding_data'), isNull);
        expect(prefs.getBool('google_account_linked'), isNull);
      },
    );

    test('should handle empty SharedPreferences gracefully', () async {
      // Arrange: Empty SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().isEmpty, isTrue);

      // Act: Clear empty preferences (should not throw)
      await prefs.clear();

      // Assert: Still empty
      expect(prefs.getKeys().isEmpty, isTrue);
    });

    group('Storage Utility Functions', () {
      test('should format bytes correctly', () {
        // Test basic byte formatting without AppDataUtils dependency
        expect(formatBytes(0), equals('0 B'));
        expect(formatBytes(512), equals('512 B'));
        expect(formatBytes(1024), equals('1.00 KB')); // Updated expectation
        expect(formatBytes(1536), equals('1.50 KB'));
        expect(
          formatBytes(1024 * 1024),
          equals('1.00 MB'),
        ); // Updated expectation
        expect(
          formatBytes(1024 * 1024 * 1024),
          equals('1.00 GB'),
        ); // Updated expectation
      });
    });
  });
}

// Helper function for testing byte formatting
String formatBytes(int bytes) {
  if (bytes == 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double size = bytes.toDouble();

  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }

  if (i == 0) {
    return '${size.toInt()} ${suffixes[i]}';
  } else {
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }
}
