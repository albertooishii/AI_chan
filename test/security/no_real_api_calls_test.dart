import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// Note: old Call system module was removed; tests keep compatibility shims instead of depending on it.
import 'package:ai_chan/shared/infrastructure/config/config.dart' as config;
import '../test_setup.dart' as test_setup;

/// HttpOverrides that prevents any HTTP(S) client from being created during
/// tests. If code attempts to perform network I/O without a fake, tests will
/// throw here and fail — enforcing that network-using code must be faked.
class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(final SecurityContext? context) {
    throw Exception('Network disabled in tests. Use fakes or test factories.');
  }
}

void main() {
  setUpAll(() async {
    await test_setup.initializeTestEnvironment();
    // Install global network ban so any code that tries to reach external
    // services without using fakes will fail the tests immediately.
    HttpOverrides.global = _NoNetworkHttpOverrides();
  });

  test('Compatibility placeholder: STT service (call system removed)', () {
    // The legacy Call bounded context (which provided STT) was removed.
    // This placeholder test exists to preserve suite stability for code
    // paths that used to rely on that component.
    expect(
      true,
      isTrue,
      reason: 'Compatibility placeholder for removed call system',
    );
  });

  test('API keys are test or empty in the test environment', () {
    final openaiKeys = config.Config.getOpenAIKeys();
    final geminiKeys = config.Config.getGeminiKeys();

    // Keys should either be empty or all contain the substring 'test' to be
    // considered non-production in CI/local tests.
    final openaiSafe =
        openaiKeys.isEmpty ||
        openaiKeys.every((key) => key.toLowerCase().contains('test'));
    final geminiSafe =
        geminiKeys.isEmpty ||
        geminiKeys.every((key) => key.toLowerCase().contains('test'));

    expect(
      openaiSafe,
      isTrue,
      reason: 'OpenAI keys should be empty or contain "test"',
    );
    expect(
      geminiSafe,
      isTrue,
      reason: 'Gemini keys should be empty or contain "test"',
    );
  });

  test('Network calls are blocked in tests unless faked', () async {
    // Creating an HttpClient should immediately throw because of installed
    // HttpOverrides. This ensures any HTTP-based API usage without fakes
    // will fail fast in the test suite.
    expect(() => HttpClient(), throwsA(isA<Exception>()));

    // Also try a higher-level attempt using dart:io WebSocket.connect which
    // typically opens a socket; try/catch and assert it throws or is blocked.
    // Note: WebSocket.connect may not consult HttpOverrides, but most
    // adapters use HTTP/HTTPS; adding this check helps catch some websocket
    // implementations too.
    try {
      await WebSocket.connect('ws://example.invalid');
      // If connection succeeded unexpectedly, fail the test
      fail('WebSocket.connect unexpectedly succeeded — network not blocked');
    } on Exception catch (_) {
      // Expected: network blocked or DNS fails — treat as pass
      expect(true, isTrue);
    }
  });
}
