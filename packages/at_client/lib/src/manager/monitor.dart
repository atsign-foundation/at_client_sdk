import 'dart:async';

import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

/// Receives notifications from the atServer.
///
/// [start] runs until [stop] is called, surviving network weather. Two
/// statuses are surfaced: [currentState] (what is true now) and [targetState]
/// (what was asked for).
///
/// ## What this class no longer does
///
/// It used to open its own socket, authenticate it with PKAM, buffer the
/// bytes, frame them, strip prompts, check for overflow, heartbeat the
/// connection and reconnect it on an
/// `[1, 2, 3, 5, 8, 13, 21, 34]`-second backoff. Every one of those existed
/// twice - once here and once in at_lookup - and the duplication was being
/// paid for in current work, not historical work: at_lookup's own
/// `authenticatedAsEnrollmentId` change had to be written a second time in
/// this file, with a comment explaining why.
///
/// All of it now lives once, in [AtLookupMuxable]. What remains here is what
/// was only ever Monitor's: the watermark, the notification callback, and the
/// two states.
class Monitor {
  NotificationListenerState _currentState =
      NotificationListenerState.notConnected;
  NotificationListenerState _targetState =
      NotificationListenerState.notConnected;

  NotificationListenerState get currentState => _currentState;

  NotificationListenerState get targetState => _targetState;

  StreamController<NotificationListenerState> currentStateStreamController =
      StreamController.broadcast();

  Stream<NotificationListenerState> get currentStateStream =>
      currentStateStreamController.stream;

  late final AtSignLogger logger;

  final String atSign;

  final AtClientPreference atClientPreference;

  /// The connection, and everything that keeps it alive.
  ///
  /// Hand this a **fresh** instance to keep today's two-connection
  /// arrangement, or the one `RemoteSecondary` already holds to collapse them
  /// into one. ⚠️ Sharing is not safe yet, and that is not a matter of taste:
  /// no atServer implements `monitor:multiplexed`, so nothing holds a
  /// notification back while a verb response is in flight, and one written
  /// into the middle of a response is absorbed into it.
  final AtLookupMuxable lookUp;

  Future<void> Function(String jsonEncoded) handleNotification;

  Future<int?> Function() getLastNotificationTime;

  /// When the last notification arrived. Read by callers checking liveness.
  DateTime? lastReceipt;

  StreamSubscription<String>? _notificationSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  /// Serialises [start] and [stop] so their bodies cannot interleave.
  ///
  /// Both are fire-and-forget to the caller and both await at_lookup partway
  /// through, so without this a `stop()` immediately followed by a `start()`
  /// runs the subscribe step of one while the teardown of the other is still
  /// in flight. `stopNotifications` closes at_lookup's controllers and builds
  /// fresh ones on next use, so the interleaving left this class holding
  /// subscriptions to the CLOSED pair while at_lookup connected and notified
  /// into the new ones - a monitor that is connected at one end and deaf at
  /// the other, reporting `notConnected` for ever.
  ///
  /// `NotificationService.stopListening()`/`startListening()` expose exactly
  /// that pair to application code, and the failure is silent: it looks like
  /// an atServer with nothing to say.
  Future<void> _lifecycle = Future<void>.value();

  void _enqueue(Future<void> Function() step) {
    _lifecycle = _lifecycle.then((_) => step()).catchError(
        (Object e, StackTrace st) {
      logger.shout('Monitor lifecycle step failed: $e\n$st');
    });
  }

  Monitor({
    required this.atSign,
    required this.atClientPreference,
    required this.lookUp,
    required this.handleNotification,
    required this.getLastNotificationTime,
  }) {
    logger = AtSignLogger('Monitor ($atSign)');
  }

  /// Sets [targetState] to `listening` and asks the atServer to start sending.
  ///
  /// Reconnection is [lookUp]'s, so this does not loop: it subscribes once and
  /// the connection state arrives as events.
  void start() {
    if (targetState == NotificationListenerState.listening) {
      logger.shout('start() called, but targetState is already "listening"');
      return;
    }
    _targetState = NotificationListenerState.listening;
    _enqueue(_start);
  }

  Future<void> _start() async {
    // Subscribed before `monitor:` goes out, not after. The notification
    // stream buffers, so nothing is lost either way, but the connection-state
    // stream is broadcast and does not replay - attaching afterwards would
    // miss the very "up" this call is about to cause.
    _connectionSubscription ??=
        lookUp.notificationConnectionUp.listen(_onConnectionState);
    _notificationSubscription ??= lookUp.notifications.listen(
      _onNotification,
      onError: (Object e) =>
          logger.warning('Error on the notification stream: $e'),
    );

    // Its own guard: reading the watermark is a local keystore operation, not
    // part of connecting, so a failure here must neither be reported as nor
    // abort a failed connection. Starting without one costs a replayed window.
    int? lastNotificationTime;
    try {
      lastNotificationTime = await getLastNotificationTime();
    } catch (e) {
      logger.warning('Could not read the last-notification watermark, so the '
          'monitor is starting without one: $e');
    }

    try {
      await lookUp.startNotifications(
          lastNotificationTime: lastNotificationTime);
      // Re-checked AFTER the await, not only before it. stop() can land while
      // this is in flight - it sets targetState and tears down, and then this
      // await completes and puts the connection straight back up. The old
      // implementation needed a done-completer to close the same race; here it
      // is one comparison, but it is just as necessary.
      if (_targetState != NotificationListenerState.listening) {
        logger.info('stop() arrived while starting - tearing down again');
        await lookUp.stopNotifications();
        return;
      }
      logger.info('monitor started, last notification time: '
          '$lastNotificationTime');
    } catch (e) {
      // Not fatal, and deliberately not retried here: the muxable reconnects
      // on its own backoff, and a second retry loop on top of it would
      // compound the delays rather than shorten them.
      logger.warning('Failed to start notifications: $e');
    }
  }

  void _onConnectionState(bool up) {
    _setCurrentState(up
        ? NotificationListenerState.listening
        : NotificationListenerState.notConnected);
  }

  Future<void> _onNotification(String notification) async {
    lastReceipt = DateTime.now().toUtc();
    try {
      await handleNotification(notification);
    } catch (e, st) {
      logger.shout('Caught $e while handling $notification\n$st');
    }
  }

  void _setCurrentState(NotificationListenerState state) {
    if (_currentState == state) return;
    logger.finer('currentState: $_currentState -> $state');
    _currentState = state;
    if (!currentStateStreamController.isClosed) {
      currentStateStreamController.add(_currentState);
    }
  }

  /// Stops the monitor. Call [start] to start it again.
  void stop() {
    logger.info('stop() called. Setting targetState to notConnected');
    _targetState = NotificationListenerState.notConnected;
    _enqueue(_stop);
  }

  Future<void> _stop() async {
    // Stop first, then cancel. `stopNotifications` closes the notification
    // stream, and a subscriber that has already gone gets no done event -
    // harmless here, but the order also means the muxable emits its final
    // `false` while this is still listening for it.
    await lookUp.stopNotifications();
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _setCurrentState(NotificationListenerState.notConnected);
  }
}
