@TestOn('browser')
library;

import 'dart:async';

import 'package:at_lookup/at_lookup_web.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

/// The browser's own behaviour behind the shared-monitor ports: what the
/// in-memory ports imitate, checked against the real thing.
///
/// Catalogue: features/at_lookup/shared_monitor.feature
void main() {
  var n = 0;
  String freshName() =>
      'at-monitor-test:${DateTime.now().microsecondsSinceEpoch}:${n++}';

  group('BroadcastChannel', () {
    test('a post reaches every other channel of the name, never the poster',
        () async {
      final name = freshName();
      final a = BrowserMonitorChannel(name);
      final b = BrowserMonitorChannel(name);
      final other = BrowserMonitorChannel('$name-other');
      addTearDown(() {
        a.close();
        b.close();
        other.close();
      });
      final heardByA = <String>[];
      final heardByOther = <String>[];
      a.messages.listen(heardByA.add);
      other.messages.listen(heardByOther.add);
      final heardByB = b.messages.first;

      a.post(const HelloMessage().encode());
      expect(MonitorMessage.decode(await heardByB), isA<HelloMessage>());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(heardByA, isEmpty);
      expect(heardByOther, isEmpty);
    });
  });

  group('navigator.locks', () {
    const lock = BrowserMonitorLock();

    test('grants in request order, the next once the holder releases',
        () async {
      final name = freshName();
      final first = lock.request(name);
      final grant = await first.granted;
      final second = lock.request(name);
      var secondGranted = false;
      unawaited(second.granted.then((_) => secondGranted = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(secondGranted, isFalse, reason: 'the first still holds it');

      await grant.release();
      final secondGrant = await second.granted;
      expect(secondGranted, isTrue);
      await secondGrant.release();
    });

    test(
        'a waiting request aborted fails with LockRequestAborted and never '
        'takes the lock', () async {
      final name = freshName();
      final holder = await lock.request(name).granted;
      final waiting = lock.request(name);
      waiting.abort();
      await expectLater(waiting.granted, throwsA(isA<LockRequestAborted>()));

      await holder.release();
      // The lock is free: a new request is granted at once.
      final next = await lock.request(name).granted;
      await next.release();
    });

    test('a steal takes the lock from its holder, whose grant is lost',
        () async {
      final name = freshName();
      final holder = await lock.request(name).granted;
      var lost = false;
      unawaited(holder.lost.then((_) => lost = true));

      final thief = await lock.request(name, steal: true).granted;
      await holder.lost.timeout(const Duration(seconds: 2));
      expect(lost, isTrue);

      // Releasing a stolen grant is harmless and does not free the thief's.
      await holder.release();
      final waiting = lock.request(name);
      var waitingGranted = false;
      unawaited(waiting.granted.then((_) => waitingGranted = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(waitingGranted, isFalse, reason: 'the thief holds it');
      await thief.release();
      await (await waiting.granted).release();
    });
  });

  group('page lifecycle', () {
    test(
        'online and pageshow are reported; visibilitychange only when the '
        'page is visible', () async {
      final lifecycle = BrowserPageLifecycle();
      final events = <PageEvent>[];
      final subscription = lifecycle.events.listen(events.add);
      addTearDown(subscription.cancel);

      window.dispatchEvent(Event('online'));
      window.dispatchEvent(Event('pageshow'));
      document.dispatchEvent(Event('visibilitychange'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, [
        PageEvent.online,
        PageEvent.pageShow,
        if (document.visibilityState == 'visible') PageEvent.visible,
      ]);
    });
  });
}
