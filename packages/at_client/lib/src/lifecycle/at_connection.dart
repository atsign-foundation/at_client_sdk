import 'dart:async';
import 'dart:io' show SocketException, HandshakeException;

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;
import 'package:at_utils/at_logger.dart';

/// How far a client got towards its atServer.
enum AtConnectionOutcome {
  /// Connected, and the atServer accepted this client's credentials.
  online,

  /// No atServer was reached: no network, or the atDirectory or atServer is
  /// unreachable. The client serves what its local storage holds.
  offline,

  /// The atServer was reached and rejected this client's credentials.
  /// [AtConnectionState.cause] says why.
  refused,
}

/// Why a connection is not [AtConnectionOutcome.online].
enum AtConnectionCause {
  /// Nothing has tried yet: the client was built and no verb has gone out.
  unattempted,

  /// The atDirectory or the atServer could not be reached.
  unreachable,

  /// The atDirectory was reached and answered that this atSign has no
  /// atServer: never provisioned, or reset.
  noAtServer,

  /// The atServer answered `AT0027`: this enrollment's access is revoked.
  revoked,

  /// The atServer answered `AT0401`: the credentials did not authenticate.
  unauthenticated,

  /// The atServer answered `AT0029`: the enrollment has expired.
  invalidEnrollment,

  /// The atServer answered `AT0025` or `AT0026`: the enrollment was denied,
  /// or is not yet approved.
  enrollmentNotApproved,

  /// A refusal the atServer gave no code this build knows for.
  otherRefusal,
}

/// What a client's connection to its atServer is, and why.
class AtConnectionState {
  final AtConnectionOutcome outcome;

  /// Why the outcome is not online; null when it is.
  final AtConnectionCause? cause;

  /// What threw, when something did.
  final Object? error;

  /// When this state was reached, in UTC.
  final DateTime at;

  AtConnectionState._(this.outcome, this.cause, this.error)
      : at = DateTime.now().toUtc();

  AtConnectionState.online() : this._(AtConnectionOutcome.online, null, null);

  AtConnectionState.offline(AtConnectionCause cause, {Object? error})
      : this._(AtConnectionOutcome.offline, cause, error);

  AtConnectionState.refused(AtConnectionCause cause, {Object? error})
      : this._(AtConnectionOutcome.refused, cause, error);

  bool get isOnline => outcome == AtConnectionOutcome.online;

  bool get isOffline => outcome == AtConnectionOutcome.offline;

  bool get isRefused => outcome == AtConnectionOutcome.refused;

  /// Whether [other] describes the same situation: outcome and cause, not
  /// the moment or the exception object.
  bool sameAs(AtConnectionState other) =>
      outcome == other.outcome && cause == other.cause;

  @override
  String toString() => 'AtConnectionState(${outcome.name}'
      '${cause == null ? '' : ', ${cause!.name}'}'
      '${error == null ? '' : ', $error'})';
}

/// A client's connection state: the current value, the transitions, and a
/// way to try again now.
///
/// The value moves when the client hears from the atServer, or fails to: a
/// verb that comes back moves it to online, one that cannot get out moves it
/// to offline, and one the atServer refuses moves it to refused. Nothing here
/// polls, so a client that talks to nobody stays where its last attempt left
/// it; [attempt] is for a caller that wants to know now.
class AtConnection {
  final AtSignLogger _logger;
  final Future<AtConnectionState> Function(Duration budget) _attempt;
  final FutureOr<void> Function()? _onOnline;
  final StreamController<AtConnectionState> _changes =
      StreamController<AtConnectionState>.broadcast();
  AtConnectionState _current =
      AtConnectionState.offline(AtConnectionCause.unattempted);

  /// How long [attempt] waits by default before reporting offline.
  static const Duration defaultBudget = Duration(seconds: 5);

  /// [attempt] performs one bounded connect and authenticate; [onOnline] runs
  /// on each transition INTO online, and its failure is logged rather than
  /// raised, since the connection is up whatever the callback did.
  AtConnection({
    required String atSign,
    required Future<AtConnectionState> Function(Duration budget) attempt,
    FutureOr<void> Function()? onOnline,
  })  : _logger = AtSignLogger('AtConnection ($atSign)'),
        _attempt = attempt,
        _onOnline = onOnline;

  AtConnectionState get current => _current;

  /// Every change of outcome or cause, in order. A report that repeats the
  /// current situation is not a change and is not emitted.
  Stream<AtConnectionState> get changes => _changes.stream;

  /// One bounded attempt to reach the atServer and authenticate, reported
  /// here and returned once the report, and whatever it records, is done.
  Future<AtConnectionState> attempt({Duration budget = defaultBudget}) async {
    final state = await _attempt(budget);
    await report(state);
    return state;
  }

  /// Attempts until the connection is online, or refused, or [budget] is
  /// spent, pausing [retryInterval] between attempts, and returns where it
  /// ended. A refusal, and an atDirectory with no record of the atSign, are
  /// answers that waiting does not change, so they end the wait at once.
  Future<AtConnectionState> awaitOnline({
    Duration budget = defaultBudget,
    Duration retryInterval = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(budget);
    var state = _current;
    while (!_settled(state)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      state = await attempt(budget: remaining);
      if (_settled(state)) break;
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) break;
      await Future<void>.delayed(retryInterval < left ? retryInterval : left);
    }
    return state;
  }

  static bool _settled(AtConnectionState state) =>
      state.isOnline ||
      state.isRefused ||
      state.cause == AtConnectionCause.noAtServer;

  /// Records [state] as what the connection is now.
  ///
  /// For the client's own connections to call; an application reads
  /// [current] and [changes]. The future completes when the online callback,
  /// if this transition ran it, has finished; a caller that does not need
  /// that may ignore it.
  Future<void> report(AtConnectionState state) {
    final wasOnline = _current.isOnline;
    final changed = !state.sameAs(_current);
    _current = state;
    if (!changed) return Future.value();
    _logger.info('connection is now $state');
    if (!_changes.isClosed) _changes.add(state);
    final onOnline = _onOnline;
    if (state.isOnline && !wasOnline && onOnline != null) {
      return Future.sync(onOnline).catchError((Object e, StackTrace st) {
        _logger.warning('the online callback failed: $e\n$st');
      });
    }
    return Future.value();
  }

  Future<void> close() => _changes.close();
}

/// The atServer's error codes that name a refusal of the credentials.
const Map<String, AtConnectionCause> _refusalCodes = {
  'AT0027': AtConnectionCause.revoked,
  'AT0401': AtConnectionCause.unauthenticated,
  'AT0029': AtConnectionCause.invalidEnrollment,
  'AT0025': AtConnectionCause.enrollmentNotApproved,
  'AT0026': AtConnectionCause.enrollmentNotApproved,
};

/// The codes at_lookup assigns when it wraps a failure to reach the atServer.
const Set<String> _unreachableCodes = {
  'AT0004', // SocketException
  'AT0021', // SecondaryConnectException
  'AT0023', // AtTimeoutException
};

/// The code at_lookup assigns when the atDirectory says there is no atServer.
const String _noAtServerCode = 'AT0007';

/// The code at_lookup assigns to a wrapped exception it has no code for, and
/// to an empty response.
const String _unknownCode = 'AT0014';

/// Text a wrapped connectivity failure carries once its type is gone.
final List<Pattern> _unreachableText = [
  'SocketException',
  'HandshakeException',
  'Connection refused',
  'Connection timed out',
  'Connection reset',
  'Network is unreachable',
  'No route to host',
  'Failed host lookup',
  'unable to connect to atServer',
  'Request timed out',
  'timed out',
  RegExp(r'Connecting to \S+ :'),
];

/// What [error] says about the connection, or null when it says nothing:
/// a key that was not found, a value that failed to parse, a privilege the
/// enrollment lacks all mean the atServer answered, and the classification
/// for those is [AtConnectionState.online], while an error about the caller's
/// own arguments says nothing at all.
///
/// at_lookup's `executeVerb` wraps every failure as an `AtLookUpException`
/// carrying a code from `error_codes` for the exception's type, or `AT0014`
/// for a type it has none for, so the refusal codes are read out of the
/// message as well as the code: an `UnAuthenticatedException` raised by the
/// authenticator is wrapped as `AT0401` and keeps the atServer's own
/// `error:AT0027` in its text.
AtConnectionState? classifyConnectionFailure(Object error) {
  if (error is AtLookUpException) {
    return _classifyCode(error.errorCode, error.errorMessage, error);
  }
  if (error is UnAuthenticatedException) {
    return AtConnectionState.refused(
        _refusalCauseIn(error.message) ?? AtConnectionCause.unauthenticated,
        error: error);
  }
  if (error is AtInvalidEnrollmentException) {
    return AtConnectionState.refused(AtConnectionCause.invalidEnrollment,
        error: error);
  }
  if (error is SecondaryNotFoundException) {
    return AtConnectionState.offline(AtConnectionCause.noAtServer,
        error: error);
  }
  if (error is UnAuthorizedException) {
    return AtConnectionState.online();
  }
  if (error is AtConnectException ||
      error is SecondaryConnectException ||
      error is AtTimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is TimeoutException) {
    return AtConnectionState.offline(AtConnectionCause.unreachable,
        error: error);
  }
  if (error is AtException) {
    final refusal = _refusalCauseIn(error.message);
    if (refusal != null)
      return AtConnectionState.refused(refusal, error: error);
    if (_readsUnreachable(error.message)) {
      return AtConnectionState.offline(AtConnectionCause.unreachable,
          error: error);
    }
  }
  return null;
}

AtConnectionState? _classifyCode(String code, String message, Object error) {
  final refusal = _refusalCodes[code];
  if (refusal != null) {
    // The wrapped message carries the atServer's own code, which is finer
    // than the AT0401 the wrapper gave the exception type.
    return AtConnectionState.refused(_refusalCauseIn(message) ?? refusal,
        error: error);
  }
  if (code == _noAtServerCode) {
    return AtConnectionState.offline(AtConnectionCause.noAtServer,
        error: error);
  }
  if (_unreachableCodes.contains(code)) {
    return AtConnectionState.offline(AtConnectionCause.unreachable,
        error: error);
  }
  if (code == _unknownCode) {
    final fromMessage = _refusalCauseIn(message);
    if (fromMessage != null) {
      return AtConnectionState.refused(fromMessage, error: error);
    }
    if (_readsUnreachable(message)) {
      return AtConnectionState.offline(AtConnectionCause.unreachable,
          error: error);
    }
    return null;
  }
  // Any other code is the atServer answering.
  return AtConnectionState.online();
}

AtConnectionCause? _refusalCauseIn(String message) {
  for (final entry in _refusalCodes.entries) {
    if (message.contains('error:${entry.key}') ||
        message.contains('${entry.key}:')) {
      return entry.value;
    }
  }
  return null;
}

bool _readsUnreachable(String message) =>
    _unreachableText.any((pattern) => message.contains(pattern));

/// `open` was refused, and this device holds nothing for the principal, so
/// there is no client to hand back: the first open of a principal on a device
/// must be online.
///
/// [state] carries the cause: revoked, unauthenticated, an expired or
/// unapproved enrollment, or an atSign the atDirectory has no atServer for.
class AtOpenRefusedException extends AtException {
  final String atSign;
  final AtConnectionState state;

  AtOpenRefusedException(this.atSign, this.state)
      : super('$atSign could not be opened: the atServer refused it '
            '(${state.cause?.name}) and this device has never held it online, '
            'so there is no local state to serve'
            '${state.error == null ? '' : ': ${state.error}'}');
}
