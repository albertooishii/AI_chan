import 'package:flutter_test/flutter_test.dart';

// NOTA: Estos tests se movieron a test/shared/google_backup_service_simple_test.dart
// para evitar dependencias de FlutterSecureStorage que fallan en el entorno de testing.
//
// Los tests originales usaban FlutterSecureStorage que causa MissingPluginException.
// Los tests simples proporcionan la misma cobertura usando solo mocks HTTP.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleBackupService - Referencia', () {
    test('Los tests reales están en google_backup_service_simple_test.dart', () {
      // Este test es solo un recordatorio
      expect(
        true,
        isTrue,
        reason:
            'Ver test/shared/google_backup_service_simple_test.dart para tests funcionales',
      );
    });
  });
}
