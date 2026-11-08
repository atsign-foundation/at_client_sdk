import 'package:at_lookup/at_lookup.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'fake_tab_rig.dart';

/// Catalogue: features/at_lookup/shared_monitor.feature
void main() {
  const beacon = Duration(seconds: 30);
  const stale = Duration(seconds: 60);

  /// Runs [body] under a fake clock with a rig of [count] started tabs, in
  /// start order, microtasks flushed so roles have settled.
  void withTabs(int count,
      void Function(FakeAsync async, TabRig rig, List<Tab> tabs) body) {
    fakeAsync((async) {
      final rig = TabRig(beaconInterval: beacon, staleAfter: stale);
      final tabs = [for (var i = 0; i < count; i++) rig.tab()];
      for (final tab in tabs) {
        tab.start();
        async.flushMicrotasks();
      }
      body(async, rig, tabs);
    });
  }

  group('T2 one connection', () {
    test('three tabs on one name start the inner muxable once, on the leader',
        () {
      withTabs(3, (async, rig, tabs) {
        expect(tabs.map((t) => t.muxable.role),
            [TabRole.leader, TabRole.follower, TabRole.follower]);
        expect(tabs[0].inner.startCalls, 1);
        expect(tabs[1].inner.startCalls, 0);
        expect(tabs[2].inner.startCalls, 0);
        expect(rig.locks.queued(rig.name), 2,
            reason: 'both followers wait in the lock queue');
      });
    });
  });

  group('T3 relay', () {
    test('a line on the leader reaches every tab once; up mirrors the leader',
        () {
      withTabs(3, (async, rig, tabs) {
        tabs[0].inner.deliver('notification: {"id":"1"}');
        async.flushMicrotasks();
        for (final tab in tabs) {
          expect(tab.lines, ['notification: {"id":"1"}'],
              reason: 'tab ${tabs.indexOf(tab)}');
          expect(tab.ups, [true], reason: 'tab ${tabs.indexOf(tab)}');
        }

        tabs[0].inner.dropConnection();
        async.flushMicrotasks();
        tabs[0].inner.reconnected();
        async.flushMicrotasks();
        for (final tab in tabs) {
          expect(tab.ups, [true, false, true]);
        }
      });
    });
  });

  group('T4 late joiner', () {
    test('a tab starting after the leader is up learns the state at once', () {
      withTabs(1, (async, rig, tabs) {
        final late = rig.tab();
        late.start();
        async.flushMicrotasks();
        expect(late.muxable.role, TabRole.follower);
        expect(late.ups, [true],
            reason: 'the leader answers hello with its current state');
        expect(late.inner.startCalls, 0);
      });
    });
  });

  group('T5 handoff', () {
    test(
        'the leader stopping passes the lock to the next tab, which starts its '
        'inner muxable with the watermark callback it was given', () {
      withTabs(3, (async, rig, tabs) {
        tabs[0].muxable.stopNotifications();
        async.flushMicrotasks();

        expect(tabs[0].muxable.role, TabRole.idle);
        expect(tabs[0].inner.stopCalls, 1);
        expect(tabs[1].muxable.role, TabRole.leader);
        expect(tabs[2].muxable.role, TabRole.follower);
        expect(tabs[1].inner.startCalls, 1);
        // Tear-offs of one method on one object are equal, never identical.
        expect(tabs[1].inner.heldWatermarkSource, equals(tabs[1].watermark),
            reason: 'the promoted tab resumes from its own cursor');
        expect(tabs[1].inner.heldWatermarkSource,
            isNot(equals(tabs[0].watermark)));
        expect(tabs[1].inner.startedWithWatermark, 42);
        expect(tabs[2].inner.startCalls, 0);
        expect(tabs[2].ups, [true, false, true],
            reason: 'the follower saw the old leader go down and the new one '
                'come up');
      });
    });
  });

  group('T7 follower stop', () {
    test(
        'a follower stopping aborts its request; starting again re-queues, '
        'its inner muxable untouched', () {
      withTabs(2, (async, rig, tabs) {
        final follower = tabs[1];
        follower.muxable.stopNotifications();
        async.flushMicrotasks();
        expect(rig.locks.aborted, 1);
        expect(rig.locks.queued(rig.name), 0);
        expect(follower.muxable.role, TabRole.idle);

        follower.start();
        async.flushMicrotasks();
        expect(rig.locks.queued(rig.name), 1);
        expect(follower.muxable.role, TabRole.follower);
        expect(follower.inner.startCalls, 0);
        expect(tabs[0].inner.startCalls, 1, reason: 'the leader is untouched');
      });
    });
  });

  group('T8 frozen leader', () {
    test(
        'three missed beacons and an unanswered hello make a follower steal; '
        'the old leader drops its connection and follows', () {
      withTabs(3, (async, rig, tabs) {
        final frozen = tabs[0];
        frozen.channel!.suspended = true;
        final hellosBefore =
            rig.hub.posted.where((m) => m.$2 is HelloMessage).length;

        async.elapse(beacon * 3);
        expect(rig.locks.steals, 0,
            reason: 'hello first, then one more interval');
        expect(rig.hub.posted.where((m) => m.$2 is HelloMessage).length,
            greaterThan(hellosBefore));

        async.elapse(beacon);
        async.flushMicrotasks();
        expect(rig.locks.steals, 1);
        final leaders =
            tabs.where((t) => t.muxable.role == TabRole.leader).toList();
        expect(leaders, hasLength(1));
        expect(leaders.single, isNot(same(frozen)));
        expect(leaders.single.inner.startCalls, 1);

        // The thaw: the old leader finds its grant lost.
        frozen.channel!.resume();
        async.flushMicrotasks();
        expect(frozen.muxable.role, TabRole.follower);
        expect(frozen.inner.stopCalls, 1, reason: 'its connection is dropped');
        expect(frozen.ups.last, true,
            reason: 'down on demotion, then the new leader\'s state');
        expect(frozen.ups, containsAllInOrder([true, false, true]));
      });
    });

    test('with steal off a follower waits however long the leader is silent',
        () {
      fakeAsync((async) {
        final rig = TabRig(beaconInterval: beacon, staleAfter: stale);
        final leader = rig.tab()..start();
        final follower = Tab(rig, steal: false)..start();
        async.flushMicrotasks();
        leader.channel!.suspended = true;
        async.elapse(beacon * 10);
        expect(rig.locks.steals, 0);
        expect(follower.muxable.role, TabRole.follower);
      });
    });
  });

  group('T9 liveness', () {
    test(
        'a stale leader drops its connection once when the page shows; a '
        'fresh one does not; online drops regardless', () {
      withTabs(1, (async, rig, tabs) {
        final leader = tabs[0];
        async.elapse(stale + const Duration(seconds: 1));
        leader.lifecycle.emit(PageEvent.visible);
        async.flushMicrotasks();
        expect(leader.inner.drops, 1);

        leader.lifecycle.emit(PageEvent.visible);
        async.flushMicrotasks();
        expect(leader.inner.drops, 1,
            reason: 'the drop itself counts as activity');

        leader.inner.reconnected();
        leader.inner.deliver('notification: fresh');
        async.elapse(stale ~/ 2);
        leader.lifecycle.emit(PageEvent.pageShow);
        async.flushMicrotasks();
        expect(leader.inner.drops, 1, reason: 'fresh lines, nothing to do');

        leader.lifecycle.emit(PageEvent.online);
        async.flushMicrotasks();
        expect(leader.inner.drops, 2);
      });
    });

    test('a follower coming back into view asks the leader to speak', () {
      withTabs(2, (async, rig, tabs) {
        final before = rig.hub.posted.length;
        tabs[1].lifecycle.emit(PageEvent.visible);
        async.flushMicrotasks();
        final since = rig.hub.posted.skip(before).map((m) => m.$2).toList();
        expect(since, [
          isA<HelloMessage>(),
          isA<UpMessage>().having((m) => m.up, 'up', isTrue),
          isA<BeaconMessage>(),
        ]);
        expect(tabs[1].ups, [true],
            reason: 'the state has not changed, so nothing is re-surfaced');
        expect(tabs[0].inner.drops, 0);
      });
    });
  });

  group('leader start failure', () {
    test(
        'a leader whose inner start fails keeps the lock and retries on the '
        'capped backoff', () {
      fakeAsync((async) {
        final rig = TabRig(beaconInterval: beacon, staleAfter: stale);
        final tab = rig.tab();
        tab.inner.startError = StateError('atServer unreachable');
        tab.start();
        async.flushMicrotasks();
        expect(tab.inner.startCalls, 1);
        expect(tab.muxable.role, TabRole.leader);

        async.elapse(const Duration(seconds: 1));
        expect(tab.inner.startCalls, 2);
        async.elapse(const Duration(seconds: 2));
        expect(tab.inner.startCalls, 3);

        tab.inner.startError = null;
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(tab.inner.startCalls, 4);
        expect(tab.inner.started, isTrue);
        expect(tab.ups, [true]);
        async.elapse(const Duration(minutes: 1));
        expect(tab.inner.startCalls, 4, reason: 'no retry once up');
      });
    });
  });

  group('message codec', () {
    test('round-trips every message and ignores what it does not know', () {
      for (final message in const [
        LineMessage('notification: {"id":"x"}'),
        UpMessage(true),
        UpMessage(false),
        HelloMessage(),
        BeaconMessage(),
      ]) {
        final decoded = MonitorMessage.decode(message.encode());
        expect(decoded.runtimeType, message.runtimeType);
        expect(decoded!.encode(), message.encode());
      }
      expect(MonitorMessage.decode('not json'), isNull);
      expect(MonitorMessage.decode('{"t":"later-version"}'), isNull);
      expect(MonitorMessage.decode('{"t":"line","v":7}'), isNull);
      expect(MonitorMessage.decode('[]'), isNull);
    });
  });
}
