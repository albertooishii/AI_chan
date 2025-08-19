import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initializeTestEnvironment({Map<String, Object>? prefs, String? dotenvContents}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (dotenvContents != null) {
    // testLoad is synchronous and returns void
    dotenv.testLoad(fileInput: dotenvContents);
  } else {
    try {
      // Intentar cargar .env real si existe
      await dotenv.load();
    } catch (_) {
      // Si no hay .env disponible en el entorno de test, inyectar valores por defecto mínimos
      const defaultContents = '''
DEFAULT_TEXT_MODEL=gemini-2.5-flash
DEFAULT_IMAGE_MODEL=gpt-4.1-mini
APP_LOG_LEVEL=trace
''';
      dotenv.testLoad(fileInput: defaultContents);
    }
  }
  SharedPreferences.setMockInitialValues(prefs ?? {});
}
