import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/shared/utils/cache_utils.dart';
import '../test_setup.dart' as ts;
import 'package:ai_chan/core/config.dart';

void main() {
  setUpAll(() async {
    await ts.initializeTestEnvironment();
  });

  test('getLocalCacheDir respects TEST_CACHE_DIR override', () async {
    final expected = Config.get('TEST_CACHE_DIR', '');
    expect(
      expected.isNotEmpty,
      isTrue,
      reason: 'test setup must provide TEST_CACHE_DIR',
    );

    final dir = await getLocalCacheDir();
    expect(dir.path, equals(expected));
    expect(dir.existsSync(), isTrue);
  });
}
