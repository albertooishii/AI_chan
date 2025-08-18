import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/models.dart';
import 'package:ai_chan/core/interfaces/i_chat_repository.dart';

void main() {
  test('core shared modules import and types exist', () {
    // Referencing types ensures the imports compile and the symbols exist.
    final Type t1 = IChatRepository;
    final Type t2 = AiImage;

    expect(t1, isNotNull);
    expect(t2, isNotNull);
  });
}
