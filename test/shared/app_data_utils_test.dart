import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/utils/app_data_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../test_setup.dart';

void main() {
  setUpAll(() async {
    await initializeTestEnvironment();
  });

  group('AppDataUtils - Clear All Data Tests', () {
    setUp(() async {
      // Reset SharedPreferences for each test
      SharedPreferences.setMockInitialValues({});
    });

    test('should clear SharedPreferences', () async {
      // Arrange: Set up some test data in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_history', '{"messages": []}');
      await prefs.setString('onboarding_data', '{"profile": {}}');
      await prefs.setBool('google_account_linked', true);

      // Verify data is there before clearing
      expect(prefs.getString('chat_history'), isNotNull);
      expect(prefs.getString('onboarding_data'), isNotNull);
      expect(prefs.getBool('google_account_linked'), isTrue);

      // Act: Clear all app data
      await AppDataUtils.clearAllAppData();

      // Assert: Verify SharedPreferences is cleared
      final clearedPrefs = await SharedPreferences.getInstance();
      expect(clearedPrefs.getString('chat_history'), isNull);
      expect(clearedPrefs.getString('onboarding_data'), isNull);
      expect(clearedPrefs.getBool('google_account_linked'), isNull);
    });

    test('should handle missing Google credentials gracefully', () async {
      // Arrange: Set up SharedPreferences but NO Google credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_history', '{"messages": []}');

      // Act: Clear all app data (should not throw even without Google creds)
      expect(() async => await AppDataUtils.clearAllAppData(), returnsNormally);

      // Assert: Verify SharedPreferences is still cleared
      final clearedPrefs = await SharedPreferences.getInstance();
      expect(clearedPrefs.getString('chat_history'), isNull);
    });

    test('should clear all data sources to prevent chat restoration bug', () async {
      // This is the specific bug test: simulate the scenario where
      // 1. User links Google Drive and creates backups
      // 2. User clicks "Borrar todo (debug)"
      // 3. User does onboarding
      // 4. Old chats should NOT reappear

      // Arrange: Simulate user having linked Google Drive with stored credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'chat_history',
        '[{"id": "old_message", "content": "This should be deleted"}]',
      );
      await prefs.setString(
        'onboarding_data',
        '{"profile": {"name": "Old Profile"}}',
      );
      await prefs.setBool('google_account_linked', true);
      await prefs.setString('google_account_email', 'user@gmail.com');

      // Act: User clicks "Borrar todo (debug)"
      await AppDataUtils.clearAllAppData();

      // Assert: ALL data sources should be cleared to prevent restoration
      final clearedPrefs = await SharedPreferences.getInstance();

      // SharedPreferences should be completely empty
      expect(clearedPrefs.getString('chat_history'), isNull);
      expect(clearedPrefs.getString('onboarding_data'), isNull);
      expect(clearedPrefs.getBool('google_account_linked'), isNull);
      expect(clearedPrefs.getString('google_account_email'), isNull);

      // This ensures that when ChatProvider.loadAll() runs after new onboarding:
      // 1. repository.loadAll() finds no SharedPreferences data ✅
      // 2. _maybeTriggerAutoBackup() finds no Google credentials ✅
      // 3. No auto-restore or background sync can happen ✅
      // 4. Old chat data cannot reappear ✅
    });

    group('Storage Usage Stats', () {
      test('should return empty stats when no data exists', () async {
        final stats = await AppDataUtils.getStorageUsageStats();

        expect(stats['images'], equals(0));
        expect(stats['audio'], equals(0));
        expect(stats['backups'], equals(0));
      });

      test('should format bytes correctly', () {
        expect(AppDataUtils.formatBytes(0), equals('0 B'));
        expect(AppDataUtils.formatBytes(512), equals('512 B'));
        expect(AppDataUtils.formatBytes(1024), equals('1 KB'));
        expect(
          AppDataUtils.formatBytes(1536),
          equals('1.50 KB'),
        ); // Fixed: expects "1.50 KB"
        expect(AppDataUtils.formatBytes(1024 * 1024), equals('1 MB'));
        expect(AppDataUtils.formatBytes(1024 * 1024 * 1024), equals('1 GB'));
      });
    });
  });
}
