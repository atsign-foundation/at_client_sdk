import 'dart:async';

import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart';

import '../util/abandonment.dart';

/// How many sockets one connect may open: the first and, after each of
/// [webSocketRetryBackoff]'s pauses, a fresh one.
const webSocketOpenAttempts = 3;

/// How long one attempt waits for its socket to open.
const webSocketAttemptTimeout = Duration(seconds: 5);

/// The pause before each retry: one second, then two.
const webSocketRetryBackoff = [Duration(seconds: 1), Duration(seconds: 2)];

/// The parts of a WebSocket that is still opening that [awaitOpen] watches.
@internal
abstract interface class OpeningWebSocket {
  /// Fires once the socket is `OPEN`.
  Stream<void> get onOpen;

  /// Fires when the socket fails.
  Stream<void> get onError;

  /// Fires once, when the socket closes.
  Stream<void> get onClose;

  void close();
}

/// How one attempt ended.
enum _OpenOutcome {
  opened,
  errored,
  closedBeforeOpen,
  timedOut,
  abandoned,
}

/// The cause [outcome] reports, worded as [awaitOpen] has always worded it.
String _openFailureCause(_OpenOutcome outcome, Duration bound) =>
    switch (outcome) {
      _OpenOutcome.errored => 'WebSocket error',
      _OpenOutcome.closedBeforeOpen => 'WebSocket closed before open',
      _OpenOutcome.timedOut => 'no answer within $bound',
      _OpenOutcome.abandoned => 'abandoned: its owner has closed',
      _OpenOutcome.opened =>
        throw StateError('an open attempt that opened has no cause'),
    };

/// One attempt: waits for [socket], opened to [host] on [port], to open,
/// closing it on every failure.
///
/// The outcome says how the attempt ended, so a caller that retries decides
/// from the attempt itself and never from message text.
Future<_OpenOutcome> _awaitOpenOnce(
    OpeningWebSocket socket, String host, String port, Duration bound) async {
  final opening = Completer<_OpenOutcome>();
  void settle(_OpenOutcome outcome) {
    if (!opening.isCompleted) opening.complete(outcome);
  }

  final subscriptions = [
    socket.onOpen.listen((_) => settle(_OpenOutcome.opened)),
    socket.onError.listen((_) => settle(_OpenOutcome.errored)),
    socket.onClose.listen((_) => settle(_OpenOutcome.closedBeforeOpen)),
  ];
  final timer = Timer(bound, () => settle(_OpenOutcome.timedOut));
  final unregister =
      Abandonment.current?.onAbandon(() => settle(_OpenOutcome.abandoned));
  final _OpenOutcome outcome;
  try {
    outcome = await opening.future;
  } finally {
    timer.cancel();
    unregister?.call();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
  if (outcome != _OpenOutcome.opened) socket.close();
  return outcome;
}

/// Completes once [socket], opened to [host] on [port], is open.
///
/// Throws [SecondaryConnectException], having closed [socket], when it fails
/// or closes first, when [timeout] elapses, the network default with none,
/// or when the work this runs inside is abandoned.
@internal
Future<void> awaitOpen(OpeningWebSocket socket, String host, String port,
    {Duration? timeout}) async {
  final bound =
      AtNetworkTimeouts.cap(timeout ?? AtNetworkTimeouts.defaultTimeout);
  final outcome = await _awaitOpenOnce(socket, host, port, bound);
  if (outcome == _OpenOutcome.opened) return;
  throw SecondaryConnectException('unable to connect to atServer on '
      '$host:$port - ${_openFailureCause(outcome, bound)}');
}

/// Opens a socket to [host] on [port] with [open], giving a transient
/// failure three attempts with a fresh socket each: [attemptTimeout] bounds
/// each attempt, and [webSocketRetryBackoff] pauses between them.
///
/// Retries an `error` or a `close` before open, and an attempt that times
/// out. A throw from [open] (a URL the browser refuses) propagates at once,
/// and an abandonment ends the ladder at once, during a pause as during an
/// attempt, so no further socket is opened after it.
///
/// [timeout] caps the whole ladder; with none it lasts at most
/// `3 * attemptTimeout + 1 s + 2 s`. On the last failure throws
/// [SecondaryConnectException] naming the host, port, last cause and how
/// many attempts it made.
@internal
Future<S> openWithRetry<S extends OpeningWebSocket>(
    S Function() open, String host, String port,
    {Duration? timeout,
    @visibleForTesting Duration attemptTimeout = webSocketAttemptTimeout,
    @visibleForTesting List<Duration> backoff = webSocketRetryBackoff}) async {
  assert(webSocketOpenAttempts == backoff.length + 1,
      'one attempt, then one more after each pause');
  final abandonment = Abandonment.current;
  final clock = timeout == null ? null : (Stopwatch()..start());
  SecondaryConnectException abandoned() =>
      SecondaryConnectException('unable to connect to atServer on '
          '$host:$port - '
          '${_openFailureCause(_OpenOutcome.abandoned, Duration.zero)}');

  String? cause;
  var attempts = 0;
  while (attempts < webSocketOpenAttempts) {
    if (abandonment?.isAbandoned ?? false) throw abandoned();
    var bound = attemptTimeout;
    if (clock != null) {
      final remaining = timeout! - clock.elapsed;
      if (remaining <= Duration.zero) {
        cause = 'no answer within $timeout';
        break;
      }
      if (remaining < bound) bound = remaining;
    }
    attempts++;
    final socket = open();
    final outcome = await _awaitOpenOnce(socket, host, port, bound);
    if (outcome == _OpenOutcome.opened) return socket;
    if (outcome == _OpenOutcome.abandoned) throw abandoned();
    cause = _openFailureCause(outcome, bound);
    if (attempts == webSocketOpenAttempts) break;
    var pause = backoff[attempts - 1];
    if (clock != null) {
      final remaining = timeout! - clock.elapsed;
      if (remaining <= Duration.zero) {
        cause = 'no answer within $timeout';
        break;
      }
      if (remaining < pause) pause = remaining;
    }
    if (!await _pause(pause, abandonment)) throw abandoned();
  }
  throw SecondaryConnectException('unable to connect to atServer on '
      '$host:$port - $cause after $attempts attempts');
}

/// Waits [pause], completing false at once when [abandonment] ends first.
Future<bool> _pause(Duration pause, Abandonment? abandonment) async {
  if (pause <= Duration.zero) {
    return !(abandonment?.isAbandoned ?? false);
  }
  final paused = Completer<bool>();
  final timer = Timer(pause, () {
    if (!paused.isCompleted) paused.complete(true);
  });
  final unregister = abandonment?.onAbandon(() {
    if (!paused.isCompleted) paused.complete(false);
  });
  final elapsed = await paused.future;
  timer.cancel();
  unregister?.call();
  return elapsed;
}
