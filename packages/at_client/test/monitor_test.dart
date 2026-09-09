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
  /// Counted so a test can prove the back-pressure seam is actually reached,
  /// rather than inferring it from handling order.
  int pauses = 0;
  int resumes = 0;

  late StreamController<String> _notifications = _newNotifications();
  StreamController<bool> _up = StreamController<bool>.broadcast();

  StreamController<String> _newNotifications() => StreamController<String>(
      onPause: () => pauses++, onResume: () => resumes++);

  bool started = false;
  int? startedWithWatermark;
  int startCalls = 0;

  /// The function Monitor handed down, kept so a test can invoke it AGAIN —
  /// which is what a reconnect does. Holding only the value it first returned
  /// cannot tell a live callback from one that captured a stale number.
  Future<int?> Function()? heldWatermarkSource;

  /// Set to make [startNotifications] fail, as an unreachable or rejecting
  /// atServer does.
  Object? startError;

  /// Awaited between the start and the watermark read, where the real
  /// muxable authenticates, so a test can land a stop() in that window.
  Future<void>? startGate;

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
    if (startGate != null) await startGate;
    // Invoked, as the real muxable does on every (re)connect - so these
    // assertions also prove the callback the Monitor hands down is callable.
    heldWatermarkSource = getLastNotificationTime;
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
    _notifications = _newNotifications();
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
  var watermarkReads = 0;

  setUp(() {
    muxable = FakeMuxable();
    received = [];
    states = [];
    watermark = null;
    watermarkError = null;
    watermarkReads = 0;
    monitor = Monitor(
      atSign: '@alice',
      atClientPreference: AtClientPreference(),
      lookUp: muxable,
      handleNotification: (String n) async => received.add(n),
      getLastNotificationTime: () async {
        watermarkReads++;
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

    test('hands down a LIVE watermark source, not a value read once', () async {
      // The muxable owns reconnection, so it asks this function again on every
      // reconnect. Monitor must therefore pass the function itself: reading
      // the number here and passing that pins every later reconnect to the
      // position held at start, which is the frozen-watermark defect. Every
      // other test in this group would pass with that defect present, because
      // they only ever look at the FIRST call.
      watermark = 1755600000000;
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(muxable.startedWithWatermark, 1755600000000);

      // The client consumes notifications and its stored watermark advances.
      watermark = 1755600009999;

      expect(muxable.heldWatermarkSource, isNotNull,
          reason: 'Monitor must hand a function down at all - without one the '
              'muxable has nothing to re-ask and every reconnect goes out '
              'with no watermark');
      expect(await muxable.heldWatermarkSource!(), 1755600009999,
          reason: 'invoking it again - which is exactly what a reconnect '
              'does - must read the CURRENT watermark, not the number that '
              'was current when notifications started');
    });

    /// Reading the watermark is a local keystore operation, not part of
    /// connecting, so its failure must not abort the connect. A configuration
    /// cause never clears, so a monitor that retries on one is silently deaf
    /// with the absence of `listening` as its only symptom.
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

    test('a start that fails is retried, not abandoned', () async {
      // at_lookup SURFACES a failed start rather than retrying it - three of
      // its own tests pin that - so the retry has to live here. Before this,
      // one failed start left the client deaf for the life of the process:
      // start() short-circuits on a targetState that is already listening, so
      // nothing could ask again.
      muxable.startError = AtConnectException('mock - connection failed');

      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(muxable.startCalls, 1);
      expect(monitor.currentState, NotificationListenerState.notConnected);

      // The first backoff step is 1s; clear the fault and let it come round.
      muxable.startError = null;
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(muxable.startCalls, greaterThan(1),
          reason: 'the monitor asked again on its own, which is what the '
              'public contract promises: reconnect until successful or until '
              'stopListening');
      expect(monitor.currentState, NotificationListenerState.listening,
          reason: 'and once the fault cleared it actually got there');
    }, timeout: Timeout(Duration(seconds: 15)));

    test('a retry stops when stop() arrives', () async {
      muxable.startError = AtConnectException('mock - connection failed');
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));

      monitor.stop();
      muxable.startError = null;
      final callsAtStop = muxable.startCalls;
      await Future.delayed(const Duration(milliseconds: 1400));

      expect(muxable.startCalls, callsAtStop,
          reason: 'a pending retry must not resurrect a monitor the caller '
              'has stopped');
    }, timeout: Timeout(Duration(seconds: 15)));

    test(
        'a stop() that lands while the start is authenticating keeps the '
        'watermark unread', () async {
      final gate = Completer<void>();
      muxable.startGate = gate.future;
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(muxable.startCalls, 1,
          reason: 'the start is in flight, parked where the real muxable '
              'authenticates');

      monitor.stop();
      gate.complete();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(watermarkReads, 0,
          reason: 'the watermark lives in the client store, which stop() '
              'has closed by the time the start resumes; reading it there is '
              'the "Box not found" the live packs log');
      expect(muxable.startedWithWatermark, isNull,
          reason: 'the start still completes, without a watermark');
    }, timeout: Timeout(Duration(seconds: 15)));

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

    test('are handled one at a time, and pause the connection while they are',
        () async {
      final log = <String>[];
      monitor = Monitor(
        atSign: '@alice',
        atClientPreference: AtClientPreference(),
        lookUp: muxable,
        handleNotification: (String n) async {
          log.add('enter $n');
          await Future.delayed(const Duration(milliseconds: 20));
          log.add('exit $n');
        },
        getLastNotificationTime: () async => null,
      );
      monitor.logger.level = 'severe';

      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      muxable.deliver('A');
      muxable.deliver('B');
      await Future.delayed(const Duration(milliseconds: 120));

      expect(log, ['enter A', 'exit A', 'enter B', 'exit B'],
          reason: 'listen() discards the future an async handler returns, so '
              'without the pause both run at once - the watermark is then '
              'written out of arrival order and the atServer replays a window '
              'on the next reconnect');
      // The count is 1 and 1, not 2 and 2: the second notification is
      // delivered out of the controller's buffer while it is still draining,
      // and a pause during that does not re-fire onPause. What matters is that
      // the seam is reached at all and left balanced.
      expect(muxable.pauses, greaterThan(0),
          reason: 'the pause reached the connection rather than being an '
              'accident of handler timing: at_lookup carries it to the '
              'socket, which is what keeps a reconnect backlog arriving at '
              'the rate this client can absorb');
      expect(muxable.resumes, muxable.pauses,
          reason: 'and every pause was matched, so a handler cannot leave the '
              'connection stopped for good');
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

  /// at_lookup recovers a connection that DROPS. It cannot see one that stays
  /// up, answers every heartbeat, and delivers nothing - only this class knows
  /// when a notification last arrived. Without these the client reports
  /// `listening` for ever while deaf, which is what the public contract on
  /// `NotificationService.currentListenerState` promises it will not do.
  group('a connection that is up but silent', () {
    Monitor monitorWithBudget(Duration budget) {
      final m = Monitor(
        atSign: '@alice',
        atClientPreference: AtClientPreference()
          ..monitorSilenceTimeout = budget,
        lookUp: muxable,
        handleNotification: (String n) async => received.add(n),
        getLastNotificationTime: () async => null,
      );
      m.logger.level = 'severe';
      return m;
    }

    test('is rebuilt', () async {
      monitor = monitorWithBudget(const Duration(milliseconds: 40));
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(muxable.startCalls, 1);

      await Future.delayed(const Duration(milliseconds: 150));

      expect(muxable.startCalls, greaterThan(1),
          reason: 'nothing arrived for longer than the budget on a connection '
              'that never went down, so the monitor tore it down and asked '
              'for a new one - at_lookup sees a healthy socket here and will '
              'never do it');
      monitor.stop();
    });

    test('is left alone while notifications keep arriving', () async {
      // Budget comfortably longer than the delivery gap: the check fires one
      // budget after connect, so a gap anywhere near it races the first tick.
      monitor = monitorWithBudget(const Duration(milliseconds: 100));
      monitor.start();

      for (var i = 0; i < 12; i++) {
        await Future.delayed(const Duration(milliseconds: 25));
        muxable.deliver('notification: {"id":"$i"}');
      }

      expect(muxable.startCalls, 1,
          reason: 'the check is about SILENCE, not about elapsed time - a busy '
              'connection outlives many budgets and must not be rebuilt under '
              'a working client');
      // Handling is serialised now, so the last delivery is still in flight.
      await Future.delayed(const Duration(milliseconds: 40));
      expect(received, hasLength(12));
      monitor.stop();
    });

    test('is left alone when the budget is zero', () async {
      monitor = monitorWithBudget(Duration.zero);
      monitor.start();
      await Future.delayed(const Duration(milliseconds: 170));

      expect(muxable.startCalls, 1,
          reason: 'an atServer configured to send no stats notifications is '
              'silent when healthy, so an operator must be able to turn the '
              'check off rather than have it rebuild a good connection');
      monitor.stop();
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
