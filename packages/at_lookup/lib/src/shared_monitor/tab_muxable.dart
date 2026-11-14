/// One monitor connection shared by every tab of an origin.
///
/// Each tab builds its own [TabMuxable] over a muxable of its own. The tabs
/// race for a [MonitorLock]; the holder (the *leader*) starts notifications
/// on its inner muxable and relays every line and every connection-state
/// change on a [MonitorChannel]; the others (the *followers*) feed what they
/// hear into their own `notifications` and `notificationConnectionUp`, so the
/// `Monitor` above each of them sees one connection that is up.
///
/// When the leader stops, the lock passes to the next tab in line, which
/// starts its inner muxable with the arguments it was itself started with;
/// its watermark callback is its own, so it resumes from the last line it
/// relayed. A leader that freezes (a hidden tab the browser suspended) keeps
/// the lock, so a follower that misses [TabMuxable.beaconInterval] beacons
/// three times over and gets no answer to a hello steals it; the thawed
/// leader learns its grant was lost, drops its connection and follows.
library;

import 'dart:async';

import 'package:at_commons/at_builders.dart' show VerbBuilder;
import 'package:at_commons/at_commons.dart' show AtRootDomain;
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/at_connection.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart' show visibleForTesting;

/// The part a tab plays for its lock's name.
enum TabRole {
  /// Not notifying.
  idle,

  /// Waiting for the lock; hearing the leader on the channel.
  follower,

  /// Holding the lock; running the connection and relaying it.
  leader,
}

/// Wraps [inner] so that one of the tabs sharing the lock called [name]
/// keeps a monitor connection and the rest listen to it. See the library
/// doc for the roles.
///
/// Verbs go to [inner] as they are: a follower's inner muxable opens a
/// connection of its own the first time one is sent, which `Monitor` never
/// does.
class TabMuxable implements AtLookupMuxable {
  TabMuxable(
    this.inner, {
    required MonitorLock lock,
    required MonitorChannelFactory channels,
    required PageLifecycle lifecycle,
    required this.name,
    this.beaconInterval = const Duration(seconds: 30),
    this.staleAfter = const Duration(seconds: 60),
    this.steal = true,
    this.startRetryDelays = defaultStartRetryDelays,
  })  : _lock = lock,
        _channels = channels,
        _lifecycle = lifecycle;

  /// The waits between a leader's failed `startNotifications` on its inner
  /// muxable and the next try: the same capped list the inner muxable and
  /// `Monitor` use to reconnect.
  static const defaultStartRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
    Duration(seconds: 21),
    Duration(seconds: 34),
  ];

  /// How many beacons a follower misses before it asks the leader to speak,
  /// and then waits one more interval before stealing.
  static const missedBeaconsBeforeHello = 3;

  final AtLookupMuxable inner;
  final MonitorLock _lock;
  final MonitorChannelFactory _channels;
  final PageLifecycle _lifecycle;

  /// The lock's and the channel's name; the same in every tab that shares.
  final String name;

  /// How often the leader says it is alive.
  final Duration beaconInterval;

  /// How long a leader may hear nothing on its connection before a page
  /// coming back into view makes it drop and reconnect.
  final Duration staleAfter;

  /// Whether a follower takes the lock from a leader that has gone silent.
  final bool steal;

  final List<Duration> startRetryDelays;

  final logger = AtSignLogger('TabMuxable');

  TabRole get role => _role;
  TabRole _role = TabRole.idle;

  bool _started = false;

  /// Bumped by every stop and every role change, so a continuation from
  /// before it finds itself stale and does nothing.
  int _generation = 0;

  _StartArgs? _args;
  MonitorChannel? _channel;
  StreamSubscription<String>? _channelSub;
  StreamSubscription<PageEvent>? _lifecycleSub;

  LockRequest? _request;
  LockGrant? _grant;
  StreamSubscription<String>? _innerLines;
  StreamSubscription<bool>? _innerUp;
  Timer? _beaconTimer;
  Timer? _staleTimer;
  Timer? _retryTimer;

  /// A follower's count of beacon intervals with nothing from the leader.
  Timer? _silenceTimer;
  int _silentIntervals = 0;
  bool _helloUnanswered = false;

  /// The leader's connection state as last known: this tab's own inner
  /// muxable's when leading, the relayed one when following.
  bool _leaderUp = false;

  /// Whether the leader has heard nothing from its connection for
  /// [staleAfter].
  bool _stale = false;

  StreamController<String>? _notificationController;
  StreamController<bool>? _upController;

  // ---------------------------------------------------------------- streams

  @override
  Stream<String> get notifications =>
      (_notificationController ??= StreamController<String>()).stream;

  @override
  Stream<bool> get notificationConnectionUp =>
      (_upController ??= StreamController<bool>.broadcast()).stream;

  @override
  bool get isNotifying => _started;

  @override
  bool get isReconnectingNotifications => switch (_role) {
        TabRole.leader => inner.isReconnectingNotifications,
        TabRole.follower => !_leaderUp,
        TabRole.idle => false,
      };

  // ------------------------------------------------------------- start/stop

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {
    if (_started) return;
    _started = true;
    _args =
        _StartArgs(regex, getLastNotificationTime, selfNotificationsEnabled);
    _channel = _channels(name);
    _channelSub = _channel!.messages.listen(_onChannelMessage);
    _lifecycleSub = _lifecycle.events.listen(_onPageEvent);
    _follow();
  }

  @override
  Future<void> stopNotifications() async {
    if (!_started) return;
    _started = false;
    _generation++;
    final wasLeader = _role == TabRole.leader;
    _role = TabRole.idle;
    await _leaveLeadership(announce: wasLeader);
    _request?.abort();
    _request = null;
    _stopSilenceClock();
    _cancel(_lifecycleSub);
    _lifecycleSub = null;
    _cancel(_channelSub);
    _channelSub = null;
    _channel?.close();
    _channel = null;
    _leaderUp = false;
    // Closed and replaced on the next read, as the inner muxable's are, so a
    // subscriber that stops and starts again reads them again. Not awaited:
    // a single-subscription controller nobody listened to never delivers its
    // done event, so awaiting would hang.
    final notifications = _notificationController;
    _notificationController = null;
    unawaited(notifications?.close() ?? Future<void>.value());
    final up = _upController;
    _upController = null;
    unawaited(up?.close() ?? Future<void>.value());
  }

  @override
  Future<void> stop() async {
    await stopNotifications();
    await inner.stop();
  }

  @override
  Future<void> close() => inner.close();

  @override
  Future<void> dropConnection() async {
    if (_role == TabRole.leader) return inner.dropConnection();
    if (_role == TabRole.follower) _post(const HelloMessage());
  }

  // --------------------------------------------------------------- follower

  void _follow() {
    _role = TabRole.follower;
    _post(const HelloMessage());
    _startSilenceClock();
    _requestLock(steal: false);
  }

  void _requestLock({required bool steal}) {
    final generation = _generation;
    final request = _lock.request(name, steal: steal);
    _request = request;
    request.granted.then((grant) {
      if (generation != _generation || !identical(_request, request)) {
        // Stopped, or superseded by a steal, while this was pending.
        unawaited(grant.release());
        return;
      }
      _request = null;
      unawaited(_lead(grant));
    }, onError: (Object e) {
      if (e is! LockRequestAborted) {
        logger.warning('Lock request for $name failed: $e');
      }
    });
  }

  void _onChannelMessage(String text) {
    final message = MonitorMessage.decode(text);
    if (message == null) return;
    switch (_role) {
      case TabRole.idle:
        return;
      case TabRole.leader:
        if (message is HelloMessage) {
          _post(UpMessage(_leaderUp));
          _post(const BeaconMessage());
        }
      case TabRole.follower:
        switch (message) {
          case LineMessage(:final line):
            _heardLeader();
            _notificationController?.add(line);
          case UpMessage(:final up):
            _heardLeader();
            _mirrorUp(up);
          case BeaconMessage():
            _heardLeader();
          case HelloMessage():
            break;
        }
    }
  }

  void _heardLeader() {
    _silentIntervals = 0;
    _helloUnanswered = false;
  }

  /// Surfaces the leader's connection state when it changes. The leader
  /// answers every hello on the channel with its state, so a follower hears
  /// the same value again whenever another tab asks; the `Monitor` above
  /// sees one event per change, as it would from its own connection.
  void _mirrorUp(bool up) {
    if (up == _leaderUp) return;
    _leaderUp = up;
    _upController?.add(up);
  }

  /// Cancels a controller subscription without awaiting it. The cancel takes
  /// effect at once; its future belongs to the zone the stream was made in,
  /// so awaiting it would stall this wrapper under a test's fake clock.
  void _cancel(StreamSubscription<Object?>? subscription) =>
      unawaited(subscription?.cancel() ?? Future<void>.value());

  void _startSilenceClock() {
    if (!steal) return;
    _silentIntervals = 0;
    _helloUnanswered = false;
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(beaconInterval, (_) => _silenceTick());
  }

  void _stopSilenceClock() {
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _silenceTick() {
    if (_role != TabRole.follower) return;
    _silentIntervals++;
    if (_silentIntervals < missedBeaconsBeforeHello) return;
    if (!_helloUnanswered) {
      // Three beacons missed: one chance for the leader to answer before
      // its lock is taken.
      _helloUnanswered = true;
      _post(const HelloMessage());
      return;
    }
    logger.info('No beacon on $name for $_silentIntervals intervals and no '
        'answer to hello: taking the lock from the leader');
    _stopSilenceClock();
    _request?.abort();
    _requestLock(steal: true);
  }

  // ----------------------------------------------------------------- leader

  Future<void> _lead(LockGrant grant) async {
    _generation++;
    final generation = _generation;
    _role = TabRole.leader;
    _grant = grant;
    _stopSilenceClock();
    unawaited(grant.lost.then((_) {
      if (generation != _generation) return;
      logger.info('The lock for $name was taken: following');
      unawaited(_demote());
    }));
    _innerUp = inner.notificationConnectionUp.listen((up) {
      _activity();
      _leaderUp = up;
      _upController?.add(up);
      _post(UpMessage(up));
    });
    _innerLines = inner.notifications.listen((line) {
      _activity();
      _notificationController?.add(line);
      _post(LineMessage(line));
    });
    _beaconTimer =
        Timer.periodic(beaconInterval, (_) => _post(const BeaconMessage()));
    _activity();
    await _startInner(generation, attempt: 0);
  }

  Future<void> _startInner(int generation, {required int attempt}) async {
    final args = _args!;
    try {
      await inner.startNotifications(
          regex: args.regex,
          getLastNotificationTime: args.getLastNotificationTime,
          selfNotificationsEnabled: args.selfNotificationsEnabled);
    } catch (e) {
      if (generation != _generation) return;
      final delay =
          startRetryDelays[attempt.clamp(0, startRetryDelays.length - 1)];
      logger.warning('Could not start notifications on $name ($e); '
          'retrying in ${delay.inSeconds}s');
      _retryTimer = Timer(delay, () {
        if (generation != _generation) return;
        unawaited(_startInner(generation, attempt: attempt + 1));
      });
    }
  }

  /// A leader whose lock was stolen: ends its connection and follows the
  /// new leader.
  Future<void> _demote() async {
    _generation++;
    _role = TabRole.follower;
    await _leaveLeadership(announce: false);
    _mirrorUp(false);
    if (!_started) return;
    _follow();
  }

  /// Ends everything leadership holds. With [announce], tells the followers
  /// the connection is down, as it is until the next leader connects.
  Future<void> _leaveLeadership({required bool announce}) async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _staleTimer?.cancel();
    _staleTimer = null;
    _stale = false;
    _cancel(_innerLines);
    _innerLines = null;
    _cancel(_innerUp);
    _innerUp = null;
    final grant = _grant;
    _grant = null;
    if (grant == null) return;
    await inner.stopNotifications();
    if (announce) _post(const UpMessage(false));
    await grant.release();
  }

  /// The connection showed life: a line, or a state change.
  void _activity() {
    _stale = false;
    _staleTimer?.cancel();
    _staleTimer = Timer(staleAfter, () => _stale = true);
  }

  // --------------------------------------------------------------- liveness

  void _onPageEvent(PageEvent event) {
    switch (_role) {
      case TabRole.idle:
        return;
      case TabRole.follower:
        // The leader answers with its state; a leader that does not is on
        // the silence clock.
        _post(const HelloMessage());
      case TabRole.leader:
        switch (event) {
          case PageEvent.online:
            // A connection from before the network went away is dead or
            // waiting out a backoff; dropping it reconnects now.
            unawaited(inner.dropConnection());
          case PageEvent.visible || PageEvent.pageShow:
            if (!_stale) return;
            _activity();
            unawaited(inner.dropConnection());
        }
    }
  }

  void _post(MonitorMessage message) => _channel?.post(message.encode());

  // ------------------------------------------------------- forwarded verbs

  @override
  Future<String?> executeVerb(VerbBuilder builder) =>
      inner.executeVerb(builder);

  @override
  Future<String?> executeCommand(String command, {bool auth = false}) =>
      inner.executeCommand(command, auth: auth);

  @override
  Future<bool> pkamAuthenticate() => inner.pkamAuthenticate();

  @override
  AtConnection? get connection => inner.connection;

  @override
  AtAuthenticator? get authenticator => inner.authenticator;

  @override
  set authenticator(AtAuthenticator? value) => inner.authenticator = value;

  @override
  SecondaryAddressFinder get secondaryAddressFinder =>
      inner.secondaryAddressFinder;

  @override
  bool isConnectionAvailable() => inner.isConnectionAvailable();

  @override
  Duration get heartbeatInterval => inner.heartbeatInterval;

  @override
  set heartbeatInterval(Duration value) => inner.heartbeatInterval = value;

  @override
  Duration get heartbeatResponseTimeout => inner.heartbeatResponseTimeout;

  @override
  set heartbeatResponseTimeout(Duration value) =>
      inner.heartbeatResponseTimeout = value;

  /// The lock and channel name for [atSign] shared under [scope].
  @visibleForTesting
  static String nameFor(String atSign, String scope) =>
      'at-monitor:$atSign:$scope';
}

class _StartArgs {
  const _StartArgs(
      this.regex, this.getLastNotificationTime, this.selfNotificationsEnabled);

  final String? regex;
  final Future<int?> Function()? getLastNotificationTime;
  final bool selfNotificationsEnabled;
}

/// An [AtLookUpFactory] whose muxables share one monitor connection per
/// atSign and [scope] across the tabs on [lock] and [channels].
///
/// [scope] separates the clients of one atSign that must not share: pass
/// the enrollment id the client runs as, or `'primary'`. The tabs that are
/// to share must pass the same value. The other arguments are
/// [TabMuxable]'s.
AtLookUpFactory sharedMonitorLookUps(
  AtLookUpFactory inner, {
  required MonitorLock lock,
  required MonitorChannelFactory channels,
  required PageLifecycle lifecycle,
  required String scope,
  Duration beaconInterval = const Duration(seconds: 30),
  Duration staleAfter = const Duration(seconds: 60),
  bool steal = true,
}) =>
    ({
      required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder,
    }) =>
        TabMuxable(
          inner(
              atSign: atSign,
              rootDomain: rootDomain,
              authenticator: authenticator,
              secondaryAddressFinder: secondaryAddressFinder),
          lock: lock,
          channels: channels,
          lifecycle: lifecycle,
          name: TabMuxable.nameFor(atSign, scope),
          beaconInterval: beaconInterval,
          staleAfter: staleAfter,
          steal: steal,
        );
