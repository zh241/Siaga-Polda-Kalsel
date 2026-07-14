import 'package:flutter_test/flutter_test.dart';
import 'package:siaga_tracker/utils/gps_throttle.dart';

void main() {
  group('GpsThrottle Unit Tests', () {
    late GpsThrottle throttle;

    setUp(() {
      throttle = GpsThrottle();
    });

    test('should allow write on initial update', () {
      final now = DateTime(2026, 7, 14, 10, 0, 0);
      final allowed = throttle.shouldWrite(now, 10);
      
      expect(allowed, isTrue);
      expect(throttle.lastWriteTime, equals(now));
    });

    test('should block write if elapsed time is less than interval', () {
      final start = DateTime(2026, 7, 14, 10, 0, 0);
      throttle.shouldWrite(start, 10); // set initial write

      final fiveSecondsLater = start.add(const Duration(seconds: 5));
      final allowed = throttle.shouldWrite(fiveSecondsLater, 10);

      expect(allowed, isFalse);
      expect(throttle.lastWriteTime, equals(start)); // should keep original time
    });

    test('should allow write if elapsed time is equal to interval', () {
      final start = DateTime(2026, 7, 14, 10, 0, 0);
      throttle.shouldWrite(start, 10);

      final tenSecondsLater = start.add(const Duration(seconds: 10));
      final allowed = throttle.shouldWrite(tenSecondsLater, 10);

      expect(allowed, isTrue);
      expect(throttle.lastWriteTime, equals(tenSecondsLater)); // updates to new time
    });

    test('should allow write if elapsed time is greater than interval', () {
      final start = DateTime(2026, 7, 14, 10, 0, 0);
      throttle.shouldWrite(start, 10);

      final fifteenSecondsLater = start.add(const Duration(seconds: 15));
      final allowed = throttle.shouldWrite(fifteenSecondsLater, 10);

      expect(allowed, isTrue);
      expect(throttle.lastWriteTime, equals(fifteenSecondsLater));
    });

    test('should reset state correctly', () {
      final start = DateTime(2026, 7, 14, 10, 0, 0);
      throttle.shouldWrite(start, 10);

      throttle.reset();
      expect(throttle.lastWriteTime, isNull);

      // Now it should allow initial write again
      final allowed = throttle.shouldWrite(start, 10);
      expect(allowed, isTrue);
    });
  });
}
