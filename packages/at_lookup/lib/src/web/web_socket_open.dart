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

/// How long a connect waits for its pre-flight before opening the first
/// socket anyway.
const webSocketPreflightWait = Duration(seconds: 2);

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

/// The URL a connect must have reached before it opens a socket to [host] on
/// [port] with [scheme], or null when no pre-flight is wanted.
///
/// Only `wss` needs one: its https origin, which is what answers the client
/// certificate an atServer's TLS listener asks for. A host that is an IPv6
/// literal is bracketed.
@internal
String? preflightUri(String scheme, String host, String port) {
  if (scheme != 'wss') return null;
  final authority = host.contains(':') ? '[$host]' : host;
  return 'https://$authority:$port/';
}

/// The `prepare` step for a connect to [host] on [port] with [scheme]: null
/// when it needs no pre-flight, otherwise a step that runs [fetch] on its
/// [preflightUri].
///
/// It exists so the factory's wiring has no browser dependency to test.
@internal
Future<void> Function()? preflightStep(String scheme, String host, String port,
    Future<void> Function(String origin) fetch) {
  final origin = preflightUri(scheme, host, port);
  return origin == null ? null : () => fetch(origin);
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
/// [prepare], when given, is called once before the first socket. The ladder
/// waits for it, for at most [preflightWait] or half of what [timeout] leaves,
/// then opens whether it answered, failed or was given up on: its result and
/// its errors are ignored, and it is never cancelled nor awaited again.
///
/// [timeout] caps the whole ladder; with none it lasts at most
/// `preflightWait + 3 * attemptTimeout + 1 s + 2 s`. On the last failure
/// throws [SecondaryConnectException] naming the host, port, last cause and
/// how many attempts it made.
@internal
Future<S> openWithRetry<S extends OpeningWebSocket>(
    S Function() open, String host, String port,
    {Duration? timeout,
    Future<void> Function()? prepare,
    @visibleForTesting Duration attemptTimeout = webSocketAttemptTimeout,
    @visibleForTesting List<Duration> backoff = webSocketRetryBackoff,
    @visibleForTesting Duration preflightWait = webSocketPreflightWait}) async {
  assert(webSocketOpenAttempts == backoff.length + 1,
      'one attempt, then one more after each pause');
  final abandonment = Abandonment.current;
  final clock = timeout == null ? null : (Stopwatch()..start());
  SecondaryConnectException abandoned() =>
      SecondaryConnectException('unable to connect to atServer on '
          '$host:$port - '
          '${_openFailureCause(_OpenOutcome.abandoned, Duration.zero)}');

  if (prepare != null) {
    if (abandonment?.isAbandoned ?? false) throw abandoned();
    Future<void>? preflight;
    try {
      preflight = prepare();
    } catch (_) {
      // A pre-flight that throws where it starts has already answered: the
      // ladder opens without waiting for it.
    }
    if (preflight != null) {
      // The pre-flight is never cancelled and never awaited twice, so a
      // rejection that lands after the wait must find this handler instead of
      // the zone.
      unawaited(preflight.then((_) {}, onError: (_) {}));
      var wait = preflightWait;
      if (clock != null) {
        final half = (timeout! - clock.elapsed) ~/ 2;
        wait = half < wait ? half : wait;
        if (wait < Duration.zero) wait = Duration.zero;
      }
      if (!await _awaitPreflight(preflight, wait, abandonment)) {
        throw abandoned();
      }
    }
  }

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

/// Waits at most [wait] for [preflight] to answer, with a value or an error,
/// completing false at once when [abandonment] ends first.
Future<bool> _awaitPreflight(
    Future<void> preflight, Duration wait, Abandonment? abandonment) async {
  if (wait <= Duration.zero) {
    return !(abandonment?.isAbandoned ?? false);
  }
  final answered = Completer<bool>();
  final timer = Timer(wait, () {
    if (!answered.isCompleted) answered.complete(true);
  });
  final unregister = abandonment?.onAbandon(() {
    if (!answered.isCompleted) answered.complete(false);
  });
  unawaited(preflight.then((_) {
    if (!answered.isCompleted) answered.complete(true);
  }, onError: (_) {
    if (!answered.isCompleted) answered.complete(true);
  }));
  final elapsed = await answered.future;
  timer.cancel();
  unregister?.call();
  return elapsed;
}
