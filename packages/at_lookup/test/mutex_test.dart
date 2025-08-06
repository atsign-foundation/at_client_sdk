import 'dart:async';

import 'package:mutex/mutex.dart';
import 'package:test/test.dart';

void main() {
  List<String> criticalSectionEvents = [];
  Future<void> criticalSection(
      String eventName, Mutex m, int delayInMillis) async {
    try {
      print('criticalSection $eventName trying to acquire mutex');
      await m.acquire();
      criticalSectionEvents.add("$eventName acquired mutex");

      print("criticalSection $eventName acquired mutex");
      await Future.delayed(Duration(milliseconds: 10));

      print(
          "criticalSection $eventName delaying for $delayInMillis milliseconds");
      await Future.delayed(Duration(milliseconds: delayInMillis));

      criticalSectionEvents.add("$eventName criticalSection completed");
    } finally {
      print("criticalSection $eventName released mutex");
      m.release();
      criticalSectionEvents.add("$eventName released mutex");
    }
  }

  test('Verify mutex core behaviour', () async {
    Mutex m = Mutex();
    unawaited(criticalSection("One", m,
        100)); // delay for 100 milliseconds so next 'criticalSection' gets a chance to run
    unawaited(criticalSection("Two", m, 10));

    await Future.delayed(Duration(milliseconds: 200));

    expect(criticalSectionEvents.length, 6);
    expect(criticalSectionEvents[0], "One acquired mutex");
    expect(criticalSectionEvents[1], "One criticalSection completed");
    expect(criticalSectionEvents[2], "One released mutex");
    expect(criticalSectionEvents[3], "Two acquired mutex");
    expect(criticalSectionEvents[4], "Two criticalSection completed");
    expect(criticalSectionEvents[5], "Two released mutex");
  });
}
