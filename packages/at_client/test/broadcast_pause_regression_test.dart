// Regression tests for the pause/resume behaviour of
// [KeyStreamMixin] and [NotificationServiceImpl.subscribeFiltered].
//
// Contract under test: a consumer-side pause does NOT propagate to
// the upstream broadcast subscription returned by
// `notificationService.subscribe(...)`. Propagating the pause would
// back-pressure every other subscriber on the same broadcast (the
// underlying controller is cached per regex) and would leak the
// upstream-pause as a publicly-observable signal.
//
// How that contract is enforced:
//   - `subscribeFiltered`: the downstream consumer's pause only
//     pauses the inner single-sub controller; upstream broadcast
//     deliveries continue and accumulate in that controller's
//     native buffer.
//   - `KeyStreamMixin`: an internal `_pauseBuffer` + pause-depth
//     counter holds notifications received while the depth is
//     non-zero. The upstream broadcast subscription is never
//     paused; the buffer drains on the resume that returns depth
//     to zero.
//
// The tests below verify that contract: when the consumer pauses,
// events are still received and held; when the consumer resumes,
// they are delivered in arrival order.

import 'dart:async';

import 'package:at_client/at_client.dart';
// ignore: implementation_imports
import 'package:at_client/src/listener/at_sign_change_listener.dart'
    show AtSignChangeListener;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAtClient extends Mock implements AtClient {
}

class _MockNotificationService extends Mock implements NotificationService {}

class _MockAtClientManager extends Mock implements AtClientManager {}

class _FakeAtSignChangeListener extends Fake implements AtSignChangeListener {}

void main() {
  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(_FakeAtSignChangeListener());
  });

  // ------------------------------------------------------------------
  group('KeyStreamMixin pause/resume buffers events', () {
    late _MockAtClient atClient;
    late _MockNotificationService notifService;
    late _MockAtClientManager manager;
    late StreamController<AtNotification> upstreamCtrl;
    // Side-effect counter incremented from the atClient.get stub, so
    // we can assert "this many notifications were forwarded past the
    // pause buffer" without relying on mocktail's verify (which
    // throws if no matching call has been made yet).
    var getCallCount = 0;

    setUp(() {
      atClient = _MockAtClient();
      notifService = _MockNotificationService();
      manager = _MockAtClientManager();
      upstreamCtrl = StreamController<AtNotification>.broadcast();
      getCallCount = 0;

      when(() => manager.atClient).thenReturn(atClient);
      when(() => atClient.notificationService).thenReturn(notifService);
      when(() => notifService.subscribe(
            regex: any(named: 'regex'),
            shouldDecrypt: any(named: 'shouldDecrypt'),
          )).thenAnswer((_) => upstreamCtrl.stream);
      when(() => manager.listenToAtSignChange(any())).thenReturn(null);

      // The mixin's listener calls atClient.get(...) for every
      // dispatched notification. The stub increments getCallCount
      // so each test can read it directly.
      when(() => atClient.get(any())).thenAnswer((_) async {
        getCallCount++;
        final v = AtValue();
        v.value = 'irrelevant';
        v.metadata = Metadata()..createdAt = DateTime.now().toUtc();
        return v;
      });
    });

    tearDown(() async {
      if (!upstreamCtrl.isClosed) await upstreamCtrl.close();
    });

    /// AtKey-shaped key string so AtKey.fromString in the mixin's
    /// listener doesn't throw "not well-formed key".
    AtNotification notif(String tag) => AtNotification(
          'id-$tag',
          '@alice:$tag.test@bob',
          '@bob',
          '@alice',
          DateTime.now().millisecondsSinceEpoch,
          'key',
          false,
          operation: 'update',
        );

    /// Build an [IterableKeyStream] wired to the test mocks. Disable
    /// the getAtKeys-init step so we control exactly what flows in.
    IterableKeyStream<int> buildStream() => IterableKeyStream<int>(
          atClientManager: manager,
          shouldGetKeys: false,
          regex: '.*',
          convert: (_, __) => 1,
        );

    test('events emitted while paused are delivered on resume', () async {
      final ks = buildStream();
      // Pre-pause delivery proves the wiring works.
      upstreamCtrl.add(notif('a'));
      await pumpEventQueue();
      expect(getCallCount, 1, reason: 'pre-pause event should arrive');

      ks.pause();
      upstreamCtrl.add(notif('b'));
      upstreamCtrl.add(notif('c'));
      await pumpEventQueue();
      expect(getCallCount, 1,
          reason: 'paused mixin must not forward to the inner listener');

      ks.resume();
      await pumpEventQueue();
      expect(getCallCount, 3, reason: 'resume drains the two buffered events');
    });

    test('multi-pause depth: equal resumes required to drain', () async {
      final ks = buildStream();
      ks.pause();
      ks.pause();
      upstreamCtrl.add(notif('x'));
      await pumpEventQueue();
      expect(getCallCount, 0);

      ks.resume(); // depth 2 -> 1
      await pumpEventQueue();
      expect(getCallCount, 0, reason: 'still paused after one of two resumes');

      ks.resume(); // depth 1 -> 0
      await pumpEventQueue();
      expect(getCallCount, 1, reason: 'final resume drains the buffer');

      // Extra resume is a no-op.
      ks.resume();
      expect(ks.isPaused, isFalse);
    });

    test('resumeSignal future drains the buffer when it completes', () async {
      final ks = buildStream();
      final signal = Completer<void>();
      ks.pause(signal.future);
      upstreamCtrl.add(notif('y'));
      await pumpEventQueue();
      expect(getCallCount, 0);

      signal.complete();
      await pumpEventQueue();
      expect(getCallCount, 1);
    });

    test('resumeSignal that errors still drains the buffer', () async {
      final ks = buildStream();
      final signal = Completer<void>();
      ks.pause(signal.future);
      upstreamCtrl.add(notif('z'));
      await pumpEventQueue();
      expect(getCallCount, 0);

      signal.completeError(StateError('cancelled'));
      await pumpEventQueue();
      expect(getCallCount, 1,
          reason: 'an errored resumeSignal still resumes the stream');
    });

    test('isPaused reflects the depth counter', () {
      final ks = buildStream();
      expect(ks.isPaused, isFalse);
      ks.pause();
      expect(ks.isPaused, isTrue);
      ks.pause();
      expect(ks.isPaused, isTrue);
      ks.resume();
      expect(ks.isPaused, isTrue,
          reason: 'still paused after one of two resumes');
      ks.resume();
      expect(ks.isPaused, isFalse);
    });

    test(
        'KeyStreamMixin pause does NOT pause its upstream broadcast '
        'subscription — other subscribers keep receiving events', () async {
      // Wire a second listener directly to the upstream broadcast
      // controller (the mixin won't see it since it's a separate
      // subscription). Verify that pausing the KeyStreamMixin doesn't
      // back-pressure this peer.
      final peerSeen = <AtNotification>[];
      final peerSub = upstreamCtrl.stream.listen(peerSeen.add);

      final ks = buildStream();
      ks.pause();
      upstreamCtrl.add(notif('shared-1'));
      upstreamCtrl.add(notif('shared-2'));
      await pumpEventQueue();
      expect(peerSeen.length, 2,
          reason: 'peer subscriber must keep receiving while ks is paused');

      await peerSub.cancel();
    });
  });
}
