import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

/// Monitor's own concerns, and only those.
///
/// This file used to hold eighteen tests, most of them about a socket, a byte
/// buffer, PKAM authentication, a heartbeat and an
/// `[1,2,3,5,8,13,21,34]`-second backoff that Monitor no longer has - all of
/// that moved into at_lookup's `AtLookupMuxable`, where it exists once and is
/// covered by `muxable_notifications_test.dart` and `socket_delivery_test.dart`.
///
/// Two of those tests had no equivalent there and were **ported before being
/// deleted here**: a failure to connect, and a reachable atServer that rejects
/// the write. They are now
/// `muxable_notifications_test.dart`'s "a connection that cannot be
/// established" group.
///
/// What is left is what was always Monitor's: the watermark, the notification
/// callback, and the two states.
class FakeMuxable extends Fake implements AtLookupMuxable {
  // Recreated on demand, exactly as AtLookupImpl does: stopNotifications()
  // nulls AND closes both controllers, so the next read of `notifications` or
  // `notificationConnectionUp` builds a fresh one. A fake that reused a single
  // controller could not reproduce a stop-then-start race at all - the
  // subscriptions would keep working and the bug would be invisible.
  StreamController<String> _notifications = StreamController<String>();
  StreamController<bool> _up = StreamController<bool>.broadcast();

  bool started = false;
  int? startedWithWatermark;
  int startCalls = 0;

  /// Set to make [startNotifications] fail, as an unreachable or rejecting
  /// atServer does.
  Object? startError;

  @override
  Stream<String> get notifications => _notifications.stream;

  @override
  Stream<bool> get notificationConnectionUp => _up.stream;

  @override
  bool get isNotifying => started;

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {
    startCalls++;
    if (startError != null) throw startError!;
    started = true;
    // Invoked, as the real muxable does on every (re)connect - so these
    // assertions also prove the callback the Monitor hands down is callable.
    startedWithWatermark = await getLastNotificationTime?.call();
    _up.add(true);
  }

  @override
  Future<void> stopNotifications() async {
    started = false;
    if (!_up.isClosed) _up.add(false);
    // Closed and replaced, as the real one does.
    final n = _notifications;
    final u = _up;
    _notifications = StreamController<String>();
    _up = StreamController<bool>.broadcast();
    unawaited(n.close());
    unawaited(u.close());
  }

  /// The atServer sends one.
  void deliver(String notification) => _notifications.add(notification);

  /// The connection drops under us - the muxable reports it and reconnects.
  void dropConnection() => _up.add(false);

  void reconnected() => _up.add(true);

  Future<void> dispose() async {
    // NOT awaited: close() on a single-subscription controller returns a
    // `done` that only completes once a subscriber has taken the event, and
    // after stopNotifications these are fresh controllers with no listener.
    // Awaiting hangs forever - the same trap that made the real
    // stopNotifications hang before it was fixed.
    if (!_notifications.isClosed) unawaited(_notifications.close());
    if (!_up.isClosed) unawaited(_up.close());
  }
}

void main() {
  late FakeMuxable muxable;
  late Monitor monitor;
  late List<String> received;
  late List<NotificationListenerState> states;
  int? watermark;
  Object? watermarkError;

  setUp(() {
    muxable = FakeMuxable();
    received = [];
    states = [];
    watermark = null;
    watermarkError = null;
    monitor = Monitor(
      atSign: '@alice',
      atClientPreference: AtClientPreference(),
      lookUp: muxable,
      handleNotification: (String n) async => received.add(n),
      getLastNotificationTime: () async {
        if (watermarkError != null) throw watermarkError!;
        return watermark;
      },
    );
    monitor.logger.level = 'severe';
    monitor.currentStateStream.listen(states.add);
  });

  tearDown(() async => muxable.dispose());

  group('start', () {
    test('reaches listening, and passes a null watermark through', () async {
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(monitor.targetState, NotificationListenerState.listening);
      expect(monitor.currentState, NotificationListenerState.listening);
      expect(states, [NotificationListenerState.listening]);
      expect(muxable.started, isTrue);
      expect(muxable.startedWithWatermark, isNull);
    });

    test('passes a real watermark through', () async {
      watermark = 1755600000000;

      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(muxable.startedWithWatermark, 1755600000000,
          reason: 'the watermark is what stops the atServer replaying every '
              'notification it has ever held');
    });

    /// Reading the watermark is a local keystore operation, not part of
    /// connecting, so its failure must not abort the connect. A client that
    /// refused legacy encryption had its own watermark write refused, the
    /// exception reached the connect handler, and the monitor retried with
    /// backoff for as long as the cause persisted - which, for a configuration
    /// flag, is forever. The client was silently deaf and the only symptom was
    /// the absence of `listening`.
    test('a watermark read that throws does not stop it connecting', () async {
      watermarkError = LegacyEncryptionRefusedException(
          'lastreceivednotification',
          'the configured provider cannot handle this key');

      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(monitor.currentState, NotificationListenerState.listening,
          reason: 'a failed watermark read must not abort the connect');
      expect(muxable.startedWithWatermark, isNull,
          reason: 'and it starts with NO watermark rather than a stale one: '
              'starting without one replays a window, which is recoverable, '
              'where starting from a wrong one loses notifications');
    });

    test('a second start is refused rather than doubling up', () async {
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(muxable.startCalls, 1,
          reason: 'a second monitor: on the same connection would duplicate '
              'every notification');
    });

    test('a start that fails leaves it notConnected', () async {
      // Ported in spirit from "secondary not available" and "secondary
      // reachable but rejecting commands", both of which now fail inside the
      // muxable. What matters HERE is only that Monitor does not claim to be
      // listening when the start did not succeed.
      muxable.startError = AtConnectException('mock - connection failed');

      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(monitor.currentState, NotificationListenerState.notConnected);
      expect(states, isEmpty,
          reason: 'no state change was published, because none happened - a '
              'listener that saw `listening` here would wait forever');
    });
  });

  group('notifications', () {
    test('reach handleNotification, and stamp lastReceipt', () async {
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(monitor.lastReceipt, isNull);

      muxable.deliver('notification: {"id":"abc"}');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(received, ['notification: {"id":"abc"}']);
      expect(monitor.lastReceipt, isNotNull);
    });

    test('a handler that throws does not kill the stream', () async {
      monitor = Monitor(
        atSign: '@alice',
        atClientPreference: AtClientPreference(),
        lookUp: muxable,
        handleNotification: (String n) async {
          received.add(n);
          throw StateError('handler blew up on $n');
        },
        getLastNotificationTime: () async => null,
      );
      monitor.logger.level = 'severe';

      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      muxable.deliver('notification: {"id":"one"}');
      await Future.delayed(const Duration(milliseconds: 20));
      muxable.deliver('notification: {"id":"two"}');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(2),
          reason: 'one bad notification must not deafen the client to every '
              'notification after it');
    });
  });

  group('connection state', () {
    test('a dropped connection surfaces, and so does the recovery', () async {
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      muxable.dropConnection();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(monitor.currentState, NotificationListenerState.notConnected);

      muxable.reconnected();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(monitor.currentState, NotificationListenerState.listening);

      expect(
          states,
          [
            NotificationListenerState.listening,
            NotificationListenerState.notConnected,
            NotificationListenerState.listening,
          ],
          reason: 'noports subscribes to this stream for the life of its '
              'daemon; every transition has to reach it');
    });

    test('an unchanged state is not republished', () async {
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      muxable.reconnected(); // already up
      await Future.delayed(const Duration(milliseconds: 20));

      expect(states, [NotificationListenerState.listening],
          reason: 'a repeated identical state is noise on a stream something '
              'reacts to');
    });
  });

  group('stop', () {
    test('stops the muxable and reports notConnected', () async {
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      monitor.stop();
      await Future.delayed(const Duration(milliseconds: 20));

      expect(monitor.targetState, NotificationListenerState.notConnected);
      expect(monitor.currentState, NotificationListenerState.notConnected);
      expect(muxable.started, isFalse);
    });

    test('start immediately after stop does not leave it deaf', () async {
      // The MIRROR of the race above, and the one _start's post-await
      // re-check does NOT cover. _stop awaits stopNotifications, which closes
      // both controllers; if _start runs meanwhile its `??=` sees non-null
      // subscription fields and keeps the OLD ones, pointed at controllers
      // that are about to close - so at_lookup reconnects and notifies into a
      // stream nobody is listening to.
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      monitor.stop();
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 60));

      muxable.deliver('notification: {"id":"after-restart"}');
      await Future.delayed(const Duration(milliseconds: 20));

      expect(received, ['notification: {"id":"after-restart"}'],
          reason: 'a restarted monitor must still hear the atServer - the '
              'failure here is silent, and looks exactly like an atServer '
              'with nothing to say');
      expect(monitor.currentState, NotificationListenerState.listening,
          reason: 'and it must not report notConnected while at_lookup is '
              'connected and notifying');
    });

    test('stop during start does not leave it listening', () async {
      // The race the old implementation needed a done-completer for: stop()
      // arriving while the connection is still being established. Here the
      // ordering is the muxable's, but the observable requirement is the same
      // - when the dust settles, nothing is listening.
      monitor.start();
      monitor.stop();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(monitor.targetState, NotificationListenerState.notConnected);
      expect(monitor.currentState, NotificationListenerState.notConnected);
      expect(muxable.started, isFalse,
          reason: 'a connection established after stop() was called must not '
              'be left running');
    });
  });
}
