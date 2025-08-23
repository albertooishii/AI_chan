import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/voice/infrastructure/adapters/call_strategy.dart';

void main() {
  test('provider mapping: openai -> realtime', () {
    expect(callModeForProvider('openai'), CallMode.realtime);
    expect(callModeForProvider('OPENAI'), CallMode.realtime);
  });

  test('provider mapping: google/gemini -> buffered', () {
    expect(callModeForProvider('google'), CallMode.buffered);
    expect(callModeForProvider('gemini'), CallMode.buffered);
    expect(callModeForProvider('something-else'), CallMode.buffered);
  });
}
