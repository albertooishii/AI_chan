import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/config.dart';

void main() {
  test('Config.initialize provides defaults when no .env exists and overrides work', () async {
    // Initialize with no dotenvContents: should load defaultContents without throwing
    await Config.initialize();
    final defaultModel = Config.getDefaultTextModel();
    expect(defaultModel.isNotEmpty, true);

    // Test overrides
  Config.setOverrides({'DEFAULT_TEXT_MODEL': 'gemini-test'});
  expect(Config.getDefaultTextModel(), 'gemini-test');

    // Clean overrides
    Config.setOverrides(null);
  });
}
