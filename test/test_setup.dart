import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initializeTestEnvironment({Map<String, Object>? prefs, String? dotenvContents}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (dotenvContents != null) {
    await Config.initialize(dotenvContents: dotenvContents);
  } else {
    await Config.initialize();
  }
  SharedPreferences.setMockInitialValues(prefs ?? {});
}
