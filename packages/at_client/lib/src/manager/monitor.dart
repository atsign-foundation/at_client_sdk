import 'dart:async';

import 'package:at_client/src/lifecycle/at_connection.dart';
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
/// only this class can do: the watermark, the notification callback, the two
/// states, the retry of a first connect that failed, and the check for a
/// connection that is up and answering but delivering nothing.
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
  /// into one. ⚠️ Sharing is not safe yet, and that is not a matter of taste.
  /// No atServer implements `monitor:multiplexed`, so nothing holds a
  /// notification back while a verb response is in flight, and one written
  /// into the middle of a response is absorbed into it. Second reason:
  /// [_onNotification] pauses this connection while it hands a notification
  /// on, so on a shared one the handler's own put would wait for a response
  /// on the socket it has just paused.
  final AtLookupMuxable lookUp;

  Future<void> Function(String jsonEncoded) handleNotification;

  Future<int?> Function() getLastNotificationTime;

  /// When the last notification arrived, or null before the first.
  DateTime? lastReceipt;

  StreamSubscription<String>? _notificationSubscription;
  StreamSubscription<bool>? _connectionSubscription;

  /// Rebuilds a connection that answers heartbeats while delivering nothing.
  ///
  /// [lookUp] recovers a connection that DROPS - the socket ends, or a
  /// heartbeat goes unanswered - and that is the whole of what it can see. A
  /// socket that stays up and answers every noop while the atServer has
  /// stopped delivering on it looks healthy from there, and the client sits
  /// reporting `listening` while permanently deaf. Only this class knows when
  /// a notification last arrived, so only this class can tell the difference.
  ///
  /// Rebuilding means [stopNotifications] then [startNotifications] through
  /// the same seam [start] uses; the reconnect backoff stays at_lookup's.
  Timer? _silenceTimer;

  /// When the connection last came up, or null while it is down.
  DateTime? _connectedAt;

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

  /// Retry of the FIRST connect only.
  ///
  /// Once [lookUp] is notifying it owns reconnection, but until then it does
  /// not: `startNotifications` deliberately SURFACES a failure rather than
  /// retrying it - three of at_lookup's own tests pin that, on the grounds that
  /// failing loudly beats a connection that silently never receives anything.
  /// So the caller has to retry, and this is the caller. Without it one failed
  /// start - offline at `subscribe()`, or an atServer briefly unreachable -
  /// left the client deaf for the life of the process, because `start()`
  /// short-circuits on a `targetState` that is already `listening`.
  Timer? _startRetry;
  int _startRetryIx = 0;

  /// The same backoff at_lookup uses for a lost connection, so a failed first
  /// connect and a dropped one recover on one schedule rather than two.
  static const List<Duration> _startRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
    Duration(seconds: 21),
    Duration(seconds: 34),
  ];

  void _enqueue(Future<void> Function() step) {
    _lifecycle =
        _lifecycle.then((_) => step()).catchError((Object e, StackTrace st) {
      logger.shout('Monitor lifecycle step failed: $e\n$st');
    });
  }

  /// The client's connection state, told `online` each time this monitor
  /// reaches `listening`: a monitor that is receiving is an authenticated
  /// connection to the atServer, and it is the one connection a passive
  /// client keeps open, so it is how the network's return gets noticed. A
  /// monitor built without one tells nobody.
  final AtConnection? connection;

  Monitor({
    required this.atSign,
    required this.atClientPreference,
    required this.lookUp,
    required this.handleNotification,
    required this.getLastNotificationTime,
    this.connection,
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
    //
    // Handed down as the FUNCTION, not as a value read once here. The muxable
    // owns reconnection now, and it asks again on every reconnect - so the
    // command carries where this client has actually got to. Reading it here
    // and passing the number would pin every later reconnect to the position
    // held at start, re-requesting the whole retained backlog each time.
    Future<int?> currentWatermark() async {
      // NOTE: the muxable calls this after it authenticates and on every
      // reconnect, by when a stop() may have closed the store the watermark
      // lives in.
      if (_targetState != NotificationListenerState.listening) {
        logger.finer('Not reading the last-notification watermark: the '
            'monitor has been stopped');
        return null;
      }
      try {
        return await getLastNotificationTime();
      } catch (e) {
        logger.warning('Could not read the last-notification watermark, so the '
            'monitor is (re)starting without one: $e');
        return null;
      }
    }

    try {
      await lookUp.startNotifications(
          getLastNotificationTime: currentWatermark);
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
      _startRetryIx = 0;
      _armSilenceTimer();
      logger.info('monitor started');
    } catch (e) {
      logger.warning('Failed to start notifications: $e');
      _scheduleStartRetry();
    }
  }

  /// Tries the first connect again, while the caller still wants to listen.
  void _scheduleStartRetry() {
    _startRetry?.cancel();
    if (_targetState != NotificationListenerState.listening) return;
    final delay =
        _startRetryDelays[_startRetryIx.clamp(0, _startRetryDelays.length - 1)];
    _startRetryIx++;
    logger.info('retrying the notification start in ${delay.inSeconds}s');
    _startRetry = Timer(delay, () {
      if (_targetState == NotificationListenerState.listening) {
        _enqueue(_start);
      }
    });
  }

  void _onConnectionState(bool up) {
    // The budget restarts with the connection: a reconnect that has delivered
    // nothing yet is not evidence of silence.
    _connectedAt = up ? DateTime.now().toUtc() : null;
    if (up) lastReceipt = null;
    _setCurrentState(up
        ? NotificationListenerState.listening
        : NotificationListenerState.notConnected);
  }

  void _armSilenceTimer() {
    _silenceTimer?.cancel();
    final budget = atClientPreference.monitorSilenceTimeout;
    if (budget <= Duration.zero) return;
    _silenceTimer = Timer.periodic(budget, (_) => _checkSilence());
  }

  void _checkSilence() {
    if (_targetState != NotificationListenerState.listening) return;
    final connectedAt = _connectedAt;
    // Down is at_lookup's to recover, and it is already doing so.
    if (connectedAt == null) return;
    final budget = atClientPreference.monitorSilenceTimeout;
    final now = DateTime.now().toUtc();
    if (now.difference(connectedAt) <= budget) return;
    final last = lastReceipt;
    if (last != null && now.difference(last) <= budget) return;
    logger.warning('nothing received for $budget on a connection that is up '
        '- rebuilding it');
    _enqueue(_rebuild);
  }

  Future<void> _rebuild() async {
    await _teardown();
    await _start();
  }

  Future<void> _onNotification(String notification) async {
    lastReceipt = DateTime.now().toUtc();
    // Paused for the duration of the handler, as the socket-owning Monitor
    // was. `listen` discards the future an async callback returns, so without
    // this two notifications are handled at once: the watermark is written out
    // of arrival order, and a reconnect's retained backlog arrives as fast as
    // the atServer can send rather than as fast as this client can absorb.
    // at_lookup carries the pause down to the socket.
    //
    // NOTE Safe only while [lookUp] is this monitor's own: on one shared with
    // RemoteSecondary the handler's own put would wait for a response on the
    // socket it has just paused.
    final subscription = _notificationSubscription;
    subscription?.pause();
    try {
      await handleNotification(notification);
    } catch (e, st) {
      logger.shout('Caught $e while handling $notification\n$st');
    } finally {
      subscription?.resume();
    }
  }

  void _setCurrentState(NotificationListenerState state) {
    if (_currentState == state) return;
    logger.finer('currentState: $_currentState -> $state');
    _currentState = state;
    if (!currentStateStreamController.isClosed) {
      currentStateStreamController.add(_currentState);
    }
    // NOTE: only the transition to listening is reported. Losing this
    // connection says nothing about whether the atServer is reachable, and
    // the verb that next fails is what says so.
    if (state == NotificationListenerState.listening) {
      connection?.report(AtConnectionState.online());
    }
  }

  /// Stops the monitor. Call [start] to start it again.
  void stop() {
    logger.info('stop() called. Setting targetState to notConnected');
    _targetState = NotificationListenerState.notConnected;
    _startRetry?.cancel();
    _startRetry = null;
    _startRetryIx = 0;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    _enqueue(_stop);
  }

  Future<void> _stop() => _teardown();

  Future<void> _teardown() async {
    // Stop first, then cancel. `stopNotifications` closes the notification
    // stream, and a subscriber that has already gone gets no done event -
    // harmless here, but the order also means the muxable emits its final
    // `false` while this is still listening for it.
    await lookUp.stopNotifications();
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectedAt = null;
    _setCurrentState(NotificationListenerState.notConnected);
  }
}
