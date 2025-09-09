import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/core/services/ia_meetstory_generator.dart';

void main() {
  test('IAMeetStoryGenerator instantiates correctly', () {
    final generator = IAMeetStoryGenerator();
    expect(generator, isNotNull);
  });

  test(
    'generateMeetStoryFromContext throws ArgumentError for empty userName',
    () async {
      final generator = IAMeetStoryGenerator();
      expect(
        () => generator.generateMeetStoryFromContext(
          userName: '',
          aiName: 'Yuna',
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );

  test(
    'generateMeetStoryFromContext throws ArgumentError for empty aiName',
    () async {
      final generator = IAMeetStoryGenerator();
      expect(
        () => generator.generateMeetStoryFromContext(
          userName: 'Alberto',
          aiName: '',
        ),
        throwsA(isA<ArgumentError>()),
      );
    },
  );
}
