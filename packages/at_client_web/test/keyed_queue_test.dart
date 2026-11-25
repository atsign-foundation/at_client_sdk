import 'dart:async';

import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/keyed_queue.dart';
import 'package:test/test.dart';

void main() {
  test('a cap below 1 is refused, naming maxQueuedPerKey', () {
    for (final cap in [0, -1]) {
      expect(
          () => KeyedQueue<String>(maxQueuedPerKey: cap),
          throwsA(isA<ArgumentError>()
              .having((e) => e.name, 'name', 'maxQueuedPerKey')
              .having((e) => e.invalidValue, 'invalidValue', cap)));
    }
  });

  test('runs on one key start in the order they were queued and never overlap',
      () async {
    final queue = KeyedQueue<String>();
    final log = <String>[];
    final firstGate = Completer<void>();

    final first = queue.run('k', () async {
      log.add('a start');
      await firstGate.future;
      log.add('a end');
    });
    final second = queue.run('k', () async {
      log.add('b start');
      log.add('b end');
    });
    final third = queue.run('k', () async {
      log.add('c start');
      log.add('c end');
    });

    await pumpEventQueue();
    expect(log, ['a start'], reason: 'nothing after the first run has started');

    firstGate.complete();
    await Future.wait([first, second, third]);
    expect(log, ['a start', 'a end', 'b start', 'b end', 'c start', 'c end']);
  });

  test('the first run on a key starts before its future is awaited', () async {
    final queue = KeyedQueue<String>();
    var started = false;

    final run = queue.run('k', () async {
      started = true;
    });

    expect(started, isTrue);
    await run;
    expect(queue.length, 0);
  });

  test('length counts a held key once, not the runs queued behind it',
      () async {
    final queue = KeyedQueue<String>();
    final release = Completer<void>();
    final held = queue.run('k', () => release.future);
    expect(queue.length, 1);

    final queued = queue.run('k', () async {});
    expect(queue.length, 1, reason: 'waiters share their key entry');

    await queue.run('other', () async {});
    expect(queue.length, 1, reason: 'a finished key leaves the map');

    release.complete();
    await Future.wait([held, queued]);
    expect(queue.length, 0);
  });

  test('a run beyond the cap rejects, and the key takes runs once it drains',
      () async {
    final queue = KeyedQueue<String>(maxQueuedPerKey: 2);
    final release = Completer<void>();
    final held = queue.run('k', () => release.future);
    final first = queue.run('k', () async {});
    final second = queue.run('k', () async {});

    await expectLater(
        queue.run('k', () async {}), throwsA(isA<QueueLimitException>()));

    release.complete();
    await Future.wait([held, first, second]);

    await queue.run('k', () async {});
    expect(queue.length, 0);
  });

  test('a throw from the held run does not strand the key or its waiters',
      () async {
    final queue = KeyedQueue<String>(maxQueuedPerKey: 1);
    final release = Completer<void>();
    final held = queue.run<String>('k', () async {
      await release.future;
      throw StateError('body failed');
    });
    final queued = queue.run('k', () async => 'ran');

    await expectLater(
        queue.run('k', () async {}), throwsA(isA<QueueLimitException>()));

    release.complete();
    await expectLater(held, throwsStateError);
    expect(await queued, 'ran');
    expect(await queue.run('k', () async => 'again'), 'again');
    expect(queue.length, 0);
  });

  test('a saturated key neither rejects nor delays a run on another key',
      () async {
    final queue = KeyedQueue<String>(maxQueuedPerKey: 1);
    final release = Completer<void>();
    final held = queue.run('k', () => release.future);
    final queued = queue.run('k', () async {});

    await expectLater(
        queue.run('k', () async {}), throwsA(isA<QueueLimitException>()));

    expect(await queue.run('other', () async => 'ran'), 'ran');

    release.complete();
    await Future.wait([held, queued]);
  });

  test(
      'clear lets a held run and its queued waiters finish in order, then the key runs again',
      () async {
    final queue = KeyedQueue<String>();
    final log = <String>[];
    final release = Completer<void>();
    final held = queue.run('k', () async {
      log.add('held start');
      await release.future;
      log.add('held end');
    });
    final first = queue.run('k', () async {
      log.add('first');
    });
    final second = queue.run('k', () async {
      log.add('second');
    });

    queue.clear();
    expect(queue.length, 0);

    var freshStarted = false;
    final fresh = queue.run('k', () async {
      freshStarted = true;
    });
    expect(freshStarted, isTrue, reason: 'a cleared key takes a run at once');

    expect(log, ['held start']);
    release.complete();
    await Future.wait([held, first, second, fresh]);
    expect(log, ['held start', 'held end', 'first', 'second']);
    expect(queue.length, 0);
  });
}
