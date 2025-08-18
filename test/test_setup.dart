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
      await dotenv.load();
    } catch (_) {}
  }
  SharedPreferences.setMockInitialValues(prefs ?? {});
}
