import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/models.dart';

void main() {
  test('AiImage serialization roundtrip', () {
    final img = AiImage(base64: 'AAA', seed: 'seed1', url: 'path/to.png', prompt: 'a prompt');
    final json = img.toJson();
    final restored = AiImage.fromJson(json);
    expect(restored.base64, img.base64);
    expect(restored.seed, img.seed);
    expect(restored.url, img.url);
    expect(restored.prompt, img.prompt);
  });

  test('AiImage copyWith produces modified copy', () {
    final img = AiImage(base64: 'A', seed: 's', url: 'u', prompt: 'p');
    final changed = img.copyWith(url: 'new', prompt: 'newp');
    expect(changed.base64, img.base64);
    expect(changed.seed, img.seed);
    expect(changed.url, 'new');
    expect(changed.prompt, 'newp');
    // original unchanged
    expect(img.url, 'u');
  });

  test('AiImage.fromLegacy handles null and maps', () {
    final nullImg = AiImage.fromLegacy(null);
    expect(nullImg.base64, isNull);
    // legacy map
    final legacy = {'base64': 'B', 'seed': 's2', 'url': 'u2', 'prompt': 'pp'};
    final fromLegacy = AiImage.fromLegacy(legacy);
    expect(fromLegacy.base64, 'B');
    expect(fromLegacy.seed, 's2');
    expect(fromLegacy.url, 'u2');
    expect(fromLegacy.prompt, 'pp');
  });
}
