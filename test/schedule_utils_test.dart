import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chan/utils/schedule_utils.dart';

void main() {
  group('ScheduleUtils.parseHmToMinutes', () {
    test('valid HH:mm', () {
      expect(ScheduleUtils.parseHmToMinutes('00:00'), 0);
      expect(ScheduleUtils.parseHmToMinutes('01:30'), 90);
      expect(ScheduleUtils.parseHmToMinutes('23:59'), 23 * 60 + 59);
    });

    test('invalid formats', () {
      expect(ScheduleUtils.parseHmToMinutes('24:00'), isNull);
      expect(ScheduleUtils.parseHmToMinutes('12:60'), isNull);
      expect(ScheduleUtils.parseHmToMinutes('abc'), isNull);
      expect(ScheduleUtils.parseHmToMinutes('12'), isNull);
    });
  });

  group('ScheduleUtils.parseDiasToWeekdaySet', () {
    test('null on empty => apply all days', () {
      expect(ScheduleUtils.parseDiasToWeekdaySet(''), isNull);
      expect(ScheduleUtils.parseDiasToWeekdaySet('   '), isNull);
    });

    test('individual days and accents', () {
      final set = ScheduleUtils.parseDiasToWeekdaySet('lunes, miércoles, sábado');
      expect(set, containsAll(<int>{1, 3, 6}));
    });

    test('range lun-vie', () {
      final set = ScheduleUtils.parseDiasToWeekdaySet('lun-vie');
      expect(set, containsAll(<int>{1, 2, 3, 4, 5}));
      expect(set, isNot(contains(6)));
      expect(set, isNot(contains(7)));
    });

    test('wrap around vie-lun', () {
      final set = ScheduleUtils.parseDiasToWeekdaySet('vie-lun');
      expect(set, containsAll(<int>{5, 6, 7, 1}));
    });
  });

  group('ScheduleUtils.isTimeInRange', () {
    test('simple range', () {
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 9 * 60, from: '08:00', to: '17:00'), isTrue);
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 7 * 60 + 59, from: '08:00', to: '17:00'), isFalse);
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 17 * 60, from: '08:00', to: '17:00'), isFalse);
    });

    test('cross midnight', () {
      // 23:30-02:00
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 23 * 60 + 30, from: '23:00', to: '02:00'), isTrue);
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 1 * 60 + 30, from: '23:00', to: '02:00'), isTrue);
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 2 * 60, from: '23:00', to: '02:00'), isFalse);
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 22 * 60, from: '23:00', to: '02:00'), isFalse);
    });

    test('invalid inputs return null', () {
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 0, from: '', to: '02:00'), isNull);
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 0, from: '23:00', to: ''), isNull);
      expect(ScheduleUtils.isTimeInRange(currentMinutes: 0, from: 'aa:bb', to: '02:00'), isNull);
    });
  });
}
