// ignore_for_file: unused_field, deprecated_member_use_from_same_package

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/base_connection.dart'
    show requireOneLine;
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:at_lookup/src/util/abandonment.dart' show Abandonment;
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_utils.dart' show AtUtils;
import 'package:mutex/mutex.dart';

/// The `from:` challenge an atServer issues a client, once the `data:` prefix
/// is stripped: `_<uuid><atSign>:<uuid>`.
///
final RegExp _fromChallengeUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// Returns [challenge] when it is a well-formed `from:` challenge issued to
/// [atSign]; throws [UnAuthenticatedException] otherwise.
///
/// [challenge] is the response with any `data:` prefix already stripped.
///
/// Public, not `@visibleForTesting`: authentication is moving out of at_lookup
/// and into at_auth, where the key material is, and the side that signs the
/// challenge is the side that has to refuse a bad one. Duplicating this check
/// there would be the worse answer - two copies of a security control drift,
/// and the one that drifts is the one nobody is looking at.
String validatedFromChallenge(String challenge, String atSign) {
  void refuse(String why) {
    // The challenge itself is not secret — it is a session id and a nonce the
    // server just sent in clear — and naming what arrived is what makes a
    // genuine protocol mismatch diagnosable rather than a silent auth failure.
    throw UnAuthenticatedException(
        'Refusing to sign a malformed from: challenge for $atSign ($why). '
        'Expected `_<uuid><atSign>:<uuid>`, got "$challenge"');
  }

  final int lastColon = challenge.lastIndexOf(':');
  if (lastColon <= 0) {
    refuse('no proof separator');
  }
  if (!_fromChallengeUuid.hasMatch(challenge.substring(lastColon + 1))) {
    refuse('the proof is not a uuid');
  }

  // The atSign this client asked for has to be the one the challenge names, so
  // a challenge minted for somebody else cannot be replayed through it.
  final String head = challenge.substring(0, lastColon);
  final String expected = AtUtils.fixAtSign(atSign);
  if (!head.endsWith(expected)) {
    refuse('it does not name $expected');
  }

  final String sessionId = head.substring(0, head.length - expected.length);
  if (!sessionId.startsWith('_') ||
      !_fromChallengeUuid.hasMatch(sessionId.substring(1))) {
    refuse('the session id is not `_<uuid>`');
  }

  return challenge;
}

class AtLookupImpl implements AtLookUp, AtCommandExecutor, AtLookupMuxable {
  final logger = AtSignLogger('AtLookup');

  /// Listener for reading verb responses from the remote server
  late OutboundMessageListener messageListener;

  OutboundConnection? _connection;

  @override
  OutboundConnection? get connection => _connection;

  @override
  final SecondaryAddressFinder secondaryAddressFinder;

  late String _currentAtSign;

  late String _rootDomain;

  late int _rootPort;

  /// Authenticates each connection this lookup opens; with none set, a
  /// command that needs authentication fails. A login serves only the
  /// authenticator that made it. See [AtAuthenticator].
  @override
  AtAuthenticator? authenticator;

  /// Runs on each connection once it is up and before anything else is sent
  /// on it. See `AtLookUp.withSecureSocket`.
  final Future<void> Function(AtCommandExecutor connection)? onConnect;

  /// Permitted number of milliseconds before connection to atServer
  /// is deemed 'idle' and will be closed. The default is usually set to
  /// 10 minutes i.e. 600,000 milliseconds
  int? outboundConnectionTimeout;

  late final AtTransportFactory transportFactory;

  late final AtLookupMessageListenerFactory socketListenerFactory;

  late AtLookupOutboundConnectionFactory outboundConnectionFactory;

  /// Represents the client configurations.
  late Map<String, dynamic> _clientConfig;

  /// Prefer [AtLookUp.withTransport] or `AtLookUp.withSecureSocket`, which
  /// take an [AtRootDomain] and return the [AtLookupMuxable] interface.
  @Deprecated('Use AtLookUp.withTransport or AtLookUp.withSecureSocket, '
      'which return an AtLookupMuxable')
  AtLookupImpl(String atSign, String rootDomain, int rootPort,
      {required this.secondaryAddressFinder,
      required this.transportFactory,
      Map<String, dynamic>? clientConfig,
      AtLookupMessageListenerFactory? socketListenerFactory,
      AtLookupOutboundConnectionFactory? outboundConnectionFactory,
      this.onConnect}) {
    _currentAtSign = atSign;
    _rootDomain = rootDomain;
    _rootPort = rootPort;
    // Stores the client configurations.
    // If client configurations are not available, defaults to empty map
    _clientConfig = clientConfig ?? {};
    this.socketListenerFactory =
        socketListenerFactory ?? AtLookupMessageListenerFactory();
    this.outboundConnectionFactory =
        outboundConnectionFactory ?? AtLookupOutboundConnectionFactory();
  }

  /// Serialises [createConnection]: two callers racing through it would
  /// each open a socket, the second replacing the first as `_connection`
  /// while the first is still the one being authenticated, so the
  /// authenticated flag lands on a socket the atServer never saw a PKAM on.
  final Mutex _createConnectionMutex = Mutex();

  /// Opens a connection if there is no usable one.
  ///
  /// Throws [StoppedException] once [stop] has been called, including when
  /// the stop lands while the connection is being opened.
  Future<void> createConnection() => _unlessStopped(_createConnection);

  Future<void> _createConnection() async {
    await _createConnectionMutex.acquire();
    try {
      _throwIfStopped();
      if (!isConnectionAvailable()) {
        if (_connection != null) {
          // Clean up the connection before creating a new one
          logger.finer('Closing old connection');
          await _closeConnection();
        }
        logger.finer('Creating new connection');
        //1. find secondary url for atsign from lookup library
        SecondaryAddress secondaryAddress =
            await secondaryAddressFinder.findSecondary(_currentAtSign);
        _throwIfAbandoned();
        var host = secondaryAddress.host;
        var port = secondaryAddress.port;
        //2. create a connection to secondary server
        await createOutBoundConnection(host, port.toString(), _currentAtSign);
        if (_stopped || (Abandonment.current?.isAbandoned ?? false)) {
          // NOTE: close() or stop() has already run and cannot see this
          // socket, so it is destroyed here or not at all. Unset first: it has
          // no listener, and a close arriving meanwhile would reach for one.
          final orphan = _connection!;
          _connection = null;
          await orphan.close();
          throw _abandonedException();
        }
        //3. listen to server response
        messageListener = socketListenerFactory.createListener(_connection!);
        // Re-established on every connection, because createConnection builds
        // a fresh listener each time. Installed only when somebody has asked
        // for the stream: with no controller there is nowhere to put a
        // notification, and routing one into a void drops it silently.
        if (_notificationController != null) {
          messageListener.onNotification = _routeNotification;
          messageListener.onDisconnect = _onNotificationConnectionLost;
        }
        messageListener.listen();
        logger.finer('New connection created OK');
        // NOTE: under the mutex, so no command uses the connection before
        // its preamble has run.
        await _runOnConnect();
      }
    } finally {
      _createConnectionMutex.release();
    }
  }

  /// Runs [onConnect] on the connection just opened, closing it if
  /// [onConnect] fails so that the next call opens one and runs it again.
  Future<void> _runOnConnect() async {
    final preamble = onConnect;
    if (preamble == null) return;
    try {
      await preamble(_ConnectionPreamble(this));
    } catch (_) {
      await _closeConnection();
      rethrow;
    }
  }

  /// Executes the command returned by [VerbBuilder] build command on a remote secondary server.
  /// Catches any exception and throws [AtLookUpException]
  @override
  Future<String> executeVerb(VerbBuilder builder) async {
    _throwIfStopped();
    String verbResult = '';
    try {
      if (builder is UpdateVerbBuilder) {
        verbResult = await _update(builder);
      } else if (builder is DeleteVerbBuilder) {
        verbResult = await _delete(builder);
      } else if (builder is LookupVerbBuilder) {
        verbResult = await _lookup(builder);
      } else if (builder is LLookupVerbBuilder) {
        verbResult = await _llookup(builder);
      } else if (builder is PLookupVerbBuilder) {
        verbResult = await _plookup(builder);
      } else if (builder is ScanVerbBuilder) {
        verbResult = await _scan(builder);
      } else if (builder is StatsVerbBuilder) {
        verbResult = await _stats(builder);
      } else if (builder is ConfigVerbBuilder) {
        verbResult = await _config(builder);
      } else if (builder is NotifyVerbBuilder) {
        verbResult = await _notify(builder);
      } else if (builder is NotifyStatusVerbBuilder) {
        verbResult = await _notifyStatus(builder);
      } else if (builder is NotifyListVerbBuilder) {
        verbResult = await _notifyList(builder);
      } else if (builder is NotifyAllVerbBuilder) {
        verbResult = await _notifyAll(builder);
      } else if (builder is SyncVerbBuilder) {
        verbResult = await _sync(builder);
      } else if (builder is NotifyRemoveVerbBuilder) {
        verbResult = await _notifyRemove(builder);
      } else if (builder is NotifyFetchVerbBuilder) {
        verbResult = await _notifyFetch(builder);
      } else if (builder is EnrollVerbBuilder) {
        verbResult = await _enroll(builder);
      }
    } on StoppedException {
      rethrow;
    } on ConnectionInvalidException catch (e) {
      // Already logged by the listener that failed the read; a connection
      // closed underneath a request is not an error in the verb.
      throw AtLookUpException(
          AtLookUpExceptionUtil.getErrorCode(e), e.toString());
    } on Exception catch (e) {
      logger.severe('Error in remote verb execution ${e.toString()}');
      var errorCode = AtLookUpExceptionUtil.getErrorCode(e);
      throw AtLookUpException(errorCode, e.toString());
    }
    return _verbResponseHandler(verbResult);
  }

  String _verbResponseHandler(String verbResult) {
    // If connection time-out, do not return empty verbResult;
    // throw AtLookupException.
    if (verbResult.isEmpty) {
      throw AtLookUpException('AT0014', 'Request timed out');
    }
    // Response starting with "data:", represents successfully processing of verb
    // return the response.
    if (verbResult.startsWith('data:')) {
      return verbResult;
    }
    if (verbResult.startsWith('error:')) {
      _errorResponseHandler(verbResult);
    }
    return verbResult;
  }

  void _errorResponseHandler(String verbResult) {
    verbResult = verbResult.replaceFirst(RegExp('^error:'), '');
    // Setting the errorCode and errorDescription to default values.
    var errorCode = 'AT0014';
    var errorDescription = 'Unknown server error';
    try {
      var errorMap = jsonDecode(verbResult);
      errorCode = errorMap['errorCode'];
      errorDescription = errorMap['errorDescription'];
    } on FormatException {
      // Catching the FormatException to preserve backward compatibility - responses without jsonEncoding.
      // TODO: Can we remove the below catch block in next release once all the servers are migrated to new version.
      if (verbResult.contains('-')) {
        errorCode = verbResult.substring(0, verbResult.indexOf('-'));
        errorDescription = verbResult.substring(verbResult.indexOf('-') + 1);
      } else {
        errorDescription += ": $verbResult";
      }
    }

    throw AtLookUpException(errorCode, errorDescription);
  }

  Future<String> _update(UpdateVerbBuilder builder) async {
    String atCommand;
    if (builder.operation == AtConstants.updateMeta) {
      atCommand = builder.buildCommandForMeta();
    } else {
      atCommand = builder.buildCommand();
    }
    logger.finer('update to remote: $atCommand');
    return await _process(atCommand, auth: true);
  }

  Future<String> _notify(NotifyVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    logger.finer('notify to remote: $atCommand');
    return await _process(atCommand, auth: true);
  }

  Future<String> _scan(ScanVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: builder.auth);
  }

  Future<String> _stats(StatsVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _config(ConfigVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _notifyStatus(NotifyStatusVerbBuilder builder) async {
    var command = builder.buildCommand();
    return await _process(command, auth: true);
  }

  Future<String> _notifyList(NotifyListVerbBuilder builder) async {
    var command = builder.buildCommand();
    return await _process(command, auth: true);
  }

  Future<String> _notifyAll(NotifyAllVerbBuilder builder) async {
    var command = builder.buildCommand();
    return await _process(command, auth: true);
  }

  Future<String> _notifyRemove(NotifyRemoveVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _notifyFetch(NotifyFetchVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _sync(SyncVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _enroll(EnrollVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    if (builder.operation == EnrollOperationEnum.request) {
      return _process(atCommand, auth: false);
    }
    return await _process(atCommand, auth: true);
  }

  @override
  Future<String?> executeCommand(String atCommand, {bool auth = false}) async {
    String verbResponse = await _process(atCommand, auth: auth);
    return _verbResponseHandler(verbResponse);
  }

  /// Records on [connection] the identity it has just authenticated as, so
  /// a later caller can tell which enrollment a live socket holds rather than
  /// which one the next authentication would use.
  void _recordAuthentication(OutboundConnection connection,
      {String? enrollmentId}) {
    final metaData = connection.getMetaData()!;
    metaData.isAuthenticated = true;
    metaData.authenticatedAsEnrollmentId = enrollmentId;
    metaData.authenticatedAt = DateTime.now().toUtc();
  }

  final Mutex _pkamAuthenticationMutex = Mutex();

  /// The authenticator whose login each connection carries. A login serves
  /// only the authenticator that made it.
  final Expando<AtAuthenticator> _loggedInBy = Expando();

  @override
  Future<String> sendSync(String command,
          {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) =>
      _unlessStopped(() async {
        await _sendCommand(command);
        return messageListener.read(
            maxWaitMilliSeconds: maxWaitMilliSeconds,
            transientWaitTimeMillis: transientWaitTimeMillis);
      });

  /// Runs [authenticate] against this connection, under the PKAM mutex, and
  /// returns true once it has authenticated.
  ///
  /// A connection logged in by another authenticator is closed, and
  /// [authenticate] logs in on a new one. A connection lost before the
  /// authentication finishes is replaced and [authenticate] runs again from
  /// its first command, once; a second loss throws
  /// [ConnectionInvalidException].
  ///
  /// The enrollment recorded on the connection is the one named by the
  /// `pkam:` the atServer accepted, none for a CRAM or a legacy PKAM.
  Future<bool> _authenticateWith(AtAuthenticator authenticate) async {
    await createConnection();
    try {
      await _pkamAuthenticationMutex.acquire();
      try {
        return await _authenticateOnce(authenticate);
      } on ConnectionInvalidException {
        await createConnection();
        return await _authenticateOnce(authenticate);
      }
    } finally {
      _pkamAuthenticationMutex.release();
    }
  }

  Future<bool> _authenticateOnce(AtAuthenticator authenticate) async {
    // NOTE: the authenticator's commands all go on this connection, so its
    // success is recorded on it, never on whichever one [_connection] holds
    // by then.
    var connection = _connection!;
    if (connection.getMetaData()!.isAuthenticated) {
      if (identical(_loggedInBy[connection], authenticate)) return true;
      await _closeConnection();
      await createConnection();
      connection = _connection!;
    }
    final sent = _SentCommands(this, connection, messageListener);
    if (!await authenticate(sent)) {
      throw UnAuthenticatedException('Failed connecting to $_currentAtSign.'
          ' The authenticator reported failure');
    }
    _recordAuthentication(connection, enrollmentId: sent.pkamEnrollmentId);
    _loggedInBy[connection] = authenticate;
    return true;
  }

  @override
  Future<bool> pkamAuthenticate() => _unlessStopped(_pkamAuthenticate);

  Future<bool> _pkamAuthenticate() async {
    final authenticate = authenticator;
    if (authenticate == null) {
      throw UnAuthenticatedException('pkamAuthenticate requires an '
          'AtAuthenticator - pass one to AtLookUp.withSecureSocket.');
    }
    return _authenticateWith(authenticate);
  }

  Future<String> _plookup(PLookupVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _lookup(LookupVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: builder.auth);
  }

  Future<String> _llookup(LLookupVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(atCommand, auth: true);
  }

  Future<String> _delete(DeleteVerbBuilder builder) async {
    var atCommand = builder.buildCommand();
    return await _process(
      atCommand,
      auth: true,
    );
  }

  /// Ensures that a new request isn't sent until either response has been received from previous
  /// request, or response wasn't received due to timeout or other exception
  Mutex requestResponseMutex = Mutex();

  Future<String> _process(String command, {bool auth = false}) =>
      _unlessStopped(() => _processCommand(command, auth: auth));

  Future<String> _processCommand(String command, {bool auth = false}) async {
    // NOTE: outside the try, whose finally releases a mutex this has not
    // acquired yet.
    requireOneLine(command);
    try {
      await requestResponseMutex.acquire();

      if (auth && _isAuthRequired()) {
        final authenticate = authenticator;
        if (authenticate == null) {
          throw UnAuthenticatedException('Unable to perform atLookup auth: '
              'no AtAuthenticator is set.');
        }
        await _authenticateWith(authenticate);
      }
      try {
        await _sendCommand(command);
        var result = await messageListener.read();
        return result;
      } on ConnectionInvalidException {
        // Already logged by the listener that failed the read.
        rethrow;
      } on Exception catch (e) {
        if (!_stopped) {
          logger.severe('Exception in sending to server, ${e.toString()}');
        }
        rethrow;
      }
    } finally {
      requestResponseMutex.release();
    }
  }

  bool _isAuthRequired() {
    return !isConnectionAvailable() ||
        !(_connection!.getMetaData()!.isAuthenticated) ||
        !identical(_loggedInBy[_connection!], authenticator);
  }

  Future<bool> createOutBoundConnection(
      String host, String port, String toAtSign) async {
    try {
      _connection = outboundConnectionFactory
          .createOutboundConnection(await transportFactory.connect(host, port));
      if (outboundConnectionTimeout != null) {
        _connection!.setIdleTime(outboundConnectionTimeout);
      }
    } on SecondaryConnectException catch (e) {
      // The factory reports what it could not reach; only the caller knows
      // whose atServer that was.
      throw SecondaryConnectException('$toAtSign: ${e.message}');
    }
    return true;
  }

  @override
  bool isConnectionAvailable() {
    return _connection != null && !_connection!.isInValid();
  }

  bool isInValid() {
    return _connection!.isInValid();
  }

  bool _stopped = false;
  Future<void>? _stopping;

  /// Abandoned by [close] and by [stop], ending the work in flight and every
  /// socket still being opened for this lookup, the atDirectory's included.
  /// [close] replaces it, so calls made after it run.
  Abandonment _abandonment = Abandonment();

  @override
  Future<void> close() async {
    final inFlight = _abandonment;
    _abandonment = Abandonment();
    inFlight.abandon();
    await stopNotifications();
  }

  @override
  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    _stopped = true;
    _abandonment.abandon();
    await stopNotifications();
  }

  @override
  Future<void> dropConnection() => _closeConnection();

  StoppedException _stoppedException() =>
      StoppedException('the lookup for $_currentAtSign has been stopped');

  /// What abandoned work fails with: a [StoppedException] once [stop] has
  /// run, else the [ConnectionInvalidException] of a [close].
  Exception _abandonedException() => _stopped
      ? _stoppedException()
      : ConnectionInvalidException(
          'The connection to $_currentAtSign was closed by this client');

  void _throwIfStopped() {
    if (_stopped) throw _stoppedException();
  }

  /// Throws once [stop] has run, or once a [close] has abandoned the work
  /// this runs inside.
  void _throwIfAbandoned() {
    _throwIfStopped();
    if (Abandonment.current?.isAbandoned ?? false) {
      throw _abandonedException();
    }
  }

  /// Runs [work] unless [stop] has been called, and fails it as soon as
  /// [close] or [stop] is called, without waiting for it.
  ///
  /// A failure that arrives after that - a read it aborted, a write to the
  /// socket it destroyed - is reported as the abandonment it is.
  Future<T> _unlessStopped<T>(Future<T> Function() work) async {
    _throwIfAbandoned();
    final abandonment = _abandonment;
    final ended = Completer<T>();
    final unregister =
        abandonment.onAbandon(() => ended.completeError(_abandonedException()));
    final running = abandonment.run(work);
    try {
      return await Future.any([running, ended.future]);
    } on Exception catch (e) {
      if (abandonment.isAbandoned &&
          e is! StoppedException &&
          e is! ConnectionInvalidException) {
        throw _abandonedException();
      }
      rethrow;
    } finally {
      unregister();
      running.ignore();
    }
  }

  /// Closes the connection and fails whatever was waiting on it.
  ///
  /// Every close goes through here rather than calling `_connection.close()`
  /// directly, because a close leaves a request in flight with nowhere for its
  /// response to arrive from. [OutboundMessageListener.read] cannot see that on
  /// its own, so it waits out its transient budget - and it is holding
  /// [requestResponseMutex] while it does, which stalls the NEXT request on
  /// this instance for the same 30 seconds.
  ///
  /// The listener aborts on `onDone` as well, and in Dart a local
  /// `Socket.destroy()` does deliver one - measured - so the two routes
  /// usually agree. This one is still needed, and not merely as belt and
  /// braces: **a PAUSED subscription delivers no done event**, also measured,
  /// and this class pauses the socket to push back-pressure at the atServer
  /// during notification delivery. Closing while paused reaches the abort
  /// through here and through nothing else.
  Future<void> _closeConnection() async {
    final connection = _connection;
    if (connection == null) {
      return;
    }
    // `messageListener` is `late` and assigned in [createConnection] - which is
    // also where `_connection` is assigned, so a non-null connection means
    // there is a listener to tell.
    messageListener.abortPendingRequests(closedLocally: true);
    await connection.close();
  }

  // ---------------------------------------------------------------------
  // AtLookupMuxable - the second framing, on a connection of its own.
  // See the warning on [AtLookupMuxable]: sharing one socket with verb
  // traffic is NOT safe today, because no atServer implements the flag that
  // was supposed to make it safe.
  // ---------------------------------------------------------------------

  /// Created on first read of [notifications], not in the constructor.
  ///
  /// Its existence is what tells [createConnection] to install the framing
  /// seam, so a lookup nobody asked notifications of behaves exactly as it
  /// always did - including leaving a stray notification in the buffer, which
  /// is pinned by test as the behaviour the seam exists to fix.
  StreamController<String>? _notificationController;

  bool _isNotifying = false;

  // --- reconnect, reauth and heartbeat -----------------------------------
  //
  // Owned here because this object holds the socket. at_client's Monitor
  // carries an identical [1,2,3,5,8,13,21,34] delay list; both cannot own
  // reconnection, and on a connection that also carries verb traffic a
  // Monitor-owned reconnect would be healing a socket it does not own for a
  // subsystem that is not it.

  /// Delays between reconnect attempts. The last is repeated indefinitely.
  ///
  /// Settable for the same reason as [heartbeatInterval]: a test of what
  /// happens over several outages would otherwise spend a second on the first
  /// reconnect of each one, and minutes on one that keeps failing.
  static List<Duration> notificationReconnectDelays = const [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
    Duration(seconds: 21),
    Duration(seconds: 34),
  ];

  /// How often a quiet notification connection is probed, and how long the
  /// probe waits. Settable so a test does not have to wait 30 seconds.
  @override
  Duration heartbeatInterval = const Duration(seconds: 30);

  @override
  Duration heartbeatResponseTimeout = const Duration(seconds: 10);

  String? _notifyRegex;

  /// The caller's watermark source, asked on every (re)connect.
  ///
  /// A function rather than a value because the caller's position moves as it
  /// consumes notifications, and a reconnect should resume from where it has
  /// got to - not from where it was when notifications started.
  Future<int?> Function()? _getLastNotificationTime;
  bool _notifySelfNotifications = true;

  int _reconnectIx = 0;
  bool _reconnecting = false;

  /// Bumped by every start of a reconnect loop and by every
  /// [stopNotifications], so a loop can tell whether the notification session
  /// it belongs to is still the current one. A stop followed by a start puts
  /// `_isNotifying` back to true, which is why that flag alone cannot answer
  /// it.
  int _notifyGeneration = 0;
  Timer? _heartbeatTimer;

  /// When the last notification arrived, in UTC, or null when none has.
  DateTime? _lastReceipt;

  /// Whether a reconnect is in flight. Visible so a test can assert the loop
  /// is running rather than inferring it from a delay.
  @override
  bool get isReconnectingNotifications => _reconnecting;

  StreamController<bool>? _connectionUpController;

  @override
  Stream<bool> get notificationConnectionUp {
    if (_stopped) return const Stream.empty();
    _connectionUpController ??= StreamController<bool>.broadcast();
    return _connectionUpController!.stream;
  }

  void _emitConnectionUp(bool up) {
    final controller = _connectionUpController;
    if (controller == null || controller.isClosed) return;
    controller.add(up);
  }

  void _onNotificationConnectionLost() {
    if (!_isNotifying || _reconnecting) return;
    // `warning`: the subscriber cannot see this any other way, and a silent
    // reconnect looks identical to an atServer that has simply gone quiet.
    logger.warning(
        'Notification connection to $_currentAtSign lost - reconnecting');
    _emitConnectionUp(false);
    _stopHeartbeat();
    unawaited(_reconnectNotifications());
  }

  Future<void> _reconnectNotifications() async {
    // The generation this loop belongs to. `_isNotifying` alone is not enough
    // to decide whether waking is safe: a stop followed by a start inside the
    // backoff window sets it back to true, and a loop orphaned by that stop
    // would then act on a connection somebody else established - writing a
    // second `monitor:` on it, resetting its heartbeat and announcing an `up`
    // that never went down.
    final generation = ++_notifyGeneration;
    _reconnecting = true;
    try {
      while (_isNotifying && generation == _notifyGeneration) {
        final delay = notificationReconnectDelays[
            min(_reconnectIx, notificationReconnectDelays.length - 1)];
        _reconnectIx++;
        logger.info('Reconnecting notifications in ${delay.inSeconds}s '
            '(attempt $_reconnectIx)');
        await Future.delayed(delay);
        // Re-checked after the delay, not only before it: stopNotifications
        // can land while this is sleeping, and reconnecting after that would
        // resurrect a connection the caller asked to be rid of - or, if a
        // start followed that stop, interfere with the connection the restart
        // just made.
        if (!_isNotifying || generation != _notifyGeneration) return;
        try {
          if (!await _openNotificationStream(generation)) return;
          if (generation != _notifyGeneration) return;
          logger.info('Notification connection re-established');
          _reconnectIx = 0;
          _startHeartbeat();
          _emitConnectionUp(true);
          return;
        } catch (e) {
          if (generation != _notifyGeneration) return;
          logger.warning('Reconnect attempt $_reconnectIx failed: $e');
        }
      }
    } finally {
      // Only if this loop is still the current one. A superseded loop clearing
      // the flag would disarm nothing and re-arm the live loop's guard.
      if (generation == _notifyGeneration) _reconnecting = false;
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer(heartbeatInterval, _heartbeat);
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Probe a quiet connection with `noop:0`.
  ///
  /// This makes the notification connection carry verb traffic: a notification
  /// arriving between this command and its reply is a message of its own and is
  /// routed as one, and the reply still arrives.
  Future<void> _heartbeat() async {
    if (!_isNotifying) return;
    final generation = _notifyGeneration;
    // A paused subscriber is not reading the socket, so nothing can fill the
    // read queue and the probe below could never be answered - it would time
    // out and destroy a healthy connection. Pausing is a documented feature of
    // [notifications], not misuse, so skip this round and try again at the
    // next interval. A connection that really has gone is still detected: the
    // done event is buffered by the paused subscription and delivered when
    // delivery resumes.
    if (messageListener.isDeliveryPaused) {
      _heartbeatTimer = Timer(heartbeatInterval, _heartbeat);
      return;
    }
    try {
      await requestResponseMutex.acquire();
      try {
        await _sendCommand('noop:0\n');
        await messageListener.read(
            maxWaitMilliSeconds: heartbeatResponseTimeout.inMilliseconds,
            transientWaitTimeMillis: heartbeatResponseTimeout.inMilliseconds);
      } finally {
        requestResponseMutex.release();
      }
      // NOTE: a stop or a reconnect while the probe was out owns the
      // heartbeat now; re-arming here would leave a timer nothing cancels.
      if (generation != _notifyGeneration) return;
      // NOTE: operators read this line; it keeps the wording at_client's
      // Monitor used.
      logger.info('Heartbeat OK: lastReceipt $_lastReceipt');
      _heartbeatTimer = Timer(heartbeatInterval, _heartbeat);
    } catch (e) {
      if (generation != _notifyGeneration) return;
      // The same pause, landing after the probe went out rather than before
      // it: the failure is our own reader being starved, not the connection.
      // Tearing down here would destroy a healthy socket for doing exactly
      // what the back-pressure contract invites.
      if (messageListener.isDeliveryPaused) {
        logger.info('Notification heartbeat could not complete while delivery '
            'is paused - leaving the connection alone and retrying');
        _heartbeatTimer = Timer(heartbeatInterval, _heartbeat);
        return;
      }
      logger.info('Notification heartbeat failed ($e) - closing the '
          'connection so it reconnects');
      // Closing is what starts recovery: the socket going away drives the
      // listener's onDone, which is wired to [_onNotificationConnectionLost].
      await _closeConnection();
    }
  }

  @override
  bool get isNotifying => _isNotifying;

  @override
  Stream<String> get notifications {
    if (_stopped) return const Stream.empty();
    _notificationController ??= StreamController<String>(
      // Back-pressure that reaches the far end. A listener that stops reading
      // stops the socket, so bytes pile up in the kernel buffer and TCP closes
      // the window on the atServer - rather than being absorbed here without
      // bound until the byte buffer overflows.
      onPause: () => _setNotificationDelivery(paused: true),
      onResume: () => _setNotificationDelivery(paused: false),
    );
    // A connection may already exist - `notifications` can be read after the
    // first verb - so the seams are installed here too, not only on connect.
    // BOTH of them: a listener given a route but no disconnect callback loses
    // its connection silently, because `_notifyDisconnect` is the only path to
    // `_onNotificationConnectionLost` and so the only thing that emits `false`
    // and starts a reconnect. Installing the disconnect seam before anything
    // is notifying is harmless - it returns immediately unless `_isNotifying`.
    if (_connection != null) {
      messageListener.onNotification = _routeNotification;
      messageListener.onDisconnect = _onNotificationConnectionLost;
    }
    return _notificationController!.stream;
  }

  /// [messageListener] is `late` and is assigned only inside
  /// [createConnection], immediately after `_connection`. So a null
  /// `_connection` is exactly the case where touching it throws a
  /// `LateInitializationError` - and the controller can be paused before
  /// anything has connected.
  void _setNotificationDelivery({required bool paused}) {
    if (_connection == null) return;
    if (paused) {
      messageListener.pauseDelivery();
    } else {
      messageListener.resumeDelivery();
    }
  }

  void _routeNotification(String notification) {
    _lastReceipt = DateTime.now().toUtc();
    final controller = _notificationController;
    if (controller == null || controller.isClosed) {
      // `warning`, not `finer`. A silently dropped notification is
      // indistinguishable from one the atServer never sent, so the failure
      // gets attributed to the sender. Nothing retries this.
      logger.warning('Notification DROPPED for $_currentAtSign - the stream is '
          '${controller == null ? "not open" : "closed"}: $notification');
      return;
    }
    controller.add(notification);
  }

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) =>
      _unlessStopped(() => _startNotifications(
          regex: regex,
          getLastNotificationTime: getLastNotificationTime,
          selfNotificationsEnabled: selfNotificationsEnabled));

  Future<void> _startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {
    if (_isNotifying) {
      logger.info('startNotifications: already notifying, nothing sent');
      return;
    }
    // Reading this getter is what creates the controller and installs the
    // seam, so it must happen before `monitor:` goes out - otherwise the first
    // notifications arrive with nowhere to go.
    notifications;

    // Remembered, because reconnecting has to re-issue the same monitor:. A
    // reconnect that dropped the regex would start delivering everything.
    //
    // The watermark is remembered as the CALLER'S FUNCTION, not as a value:
    // it is asked again on every reconnect, so the command carries where the
    // caller has actually got to rather than where it had got to when
    // notifications first started. Freezing the value re-requests the whole
    // retained backlog on every reconnect, which is what a caller holding a
    // durable watermark is keeping one to avoid.
    _notifyRegex = regex;
    _getLastNotificationTime = getLastNotificationTime;
    _notifySelfNotifications = selfNotificationsEnabled;

    final generation = _notifyGeneration;
    if (!await _openNotificationStream(generation)) return;
    // NOTE: a stopNotifications() that landed while `monitor:` went out owns
    // the state now.
    if (generation != _notifyGeneration) return;
    _isNotifying = true;
    _reconnectIx = 0;
    _startHeartbeat();
    _emitConnectionUp(true);
  }

  /// Connect, authenticate if required, and send `monitor:`.
  ///
  /// Shared by [startNotifications] and the reconnect loop, so a reconnected
  /// connection is established exactly as the first one was. Anything else and
  /// the two paths drift, with the difference only visible after an outage.
  ///
  /// Returns false, having closed the connection it opened, when a stop has
  /// retired [generation] meanwhile; throws [StoppedException] when that stop
  /// was [stop].
  Future<bool> _openNotificationStream(int generation) async {
    await requestResponseMutex.acquire();
    try {
      await createConnection();
      if (generation != _notifyGeneration) {
        await _closeConnection();
        _throwIfStopped();
        return false;
      }
      if (_isAuthRequired()) {
        if (authenticator != null) {
          await _authenticateWith(authenticator!);
        } else {
          throw UnAuthenticatedException(
              'monitor requires authentication and no authenticator is set');
        }
      }
      final loggedIn = _connection;
      // Asked here rather than held from the start, so a reconnect resumes
      // from the caller's current watermark.
      //
      // Guarded, because this is CALLER code running inside the reconnect
      // loop. Letting it throw would abort the attempt after the connection
      // was already opened and authenticated - and that connection stays
      // valid, so every later attempt skips the connect, re-runs only this
      // call, and backs off forever without ever sending `monitor:`. The
      // client would be permanently deaf with no symptom but a missing `up`.
      // Starting without a watermark instead costs a replayed window, which
      // the caller can absorb.
      int? lastNotificationTime;
      try {
        lastNotificationTime = await _getLastNotificationTime?.call();
      } catch (e) {
        logger.warning('Could not read the last-notification watermark, so '
            'this connection starts without one and the atServer will replay '
            'from where it last heard: $e');
      }
      final command = (MonitorVerbBuilder()
            ..regex = _notifyRegex
            ..lastNotificationTime = lastNotificationTime
            ..selfNotificationsEnabled = _notifySelfNotifications)
          .buildCommand();
      // ⚠️ `multiplexed` is deliberately NOT set. It is accepted by the shared
      // verb syntax and read by no atServer, so setting it would advertise a
      // safety property that does not exist. See [AtLookupMuxable].
      // NOTE: only the connection this start logged in. Connecting and logging
      // in take no request mutex, so another caller of this lookup may have
      // opened and logged in a newer one while the watermark was read.
      if (generation != _notifyGeneration) {
        if (identical(_connection, loggedIn)) await _closeConnection();
        _throwIfStopped();
        return false;
      }
      logger.finer('SENDING: ${command.trim()}');
      await _connection!.write(command);
      return true;
    } finally {
      requestResponseMutex.release();
    }
  }

  @override
  Future<void> stopNotifications() async {
    // First, and deliberately: this flag is what the reconnect loop reads to
    // decide whether to keep trying. Closing the connection before clearing it
    // would trip the disconnect handler into reconnecting the very connection
    // this method is tearing down.
    _isNotifying = false;
    // Retires any reconnect loop still sleeping on a backoff, and clears the
    // flag it would otherwise leave set: `_reconnecting` disarms
    // [_onNotificationConnectionLost], so a stale one left true means a real
    // loss on a later connection is ignored.
    _notifyGeneration++;
    _reconnecting = false;
    _stopHeartbeat();
    _emitConnectionUp(false);
    await _closeConnection();
    final controller = _notificationController;
    _notificationController = null;
    // NOT awaited, and that is the point. `close()` on a single-subscription
    // controller returns its `done` future, which completes only once a
    // subscriber has received the done event - so a caller that started
    // notifications and never listened would hang here forever. Start-then-stop
    // with no subscriber is a legal caller, and awaiting this deadlocked four
    // tests for thirty seconds each before it was caught.
    unawaited(controller?.close() ?? Future<void>.value());
    final up = _connectionUpController;
    _connectionUpController = null;
    unawaited(up?.close() ?? Future<void>.value());
  }

  Future<void> _sendCommand(String command) async {
    await createConnection();
    logger.finer('SENDING: $command');
    await _connection!.write(command);
  }
}

/// Builds the listener that reads an open connection, over any transport.
class AtLookupMessageListenerFactory {
  const AtLookupMessageListenerFactory();

  OutboundMessageListener createListener(
      OutboundConnection outboundConnection) {
    return OutboundMessageListener(outboundConnection);
  }
}

class AtLookupOutboundConnectionFactory {
  const AtLookupOutboundConnectionFactory();

  OutboundConnection createOutboundConnection(AtTransport transport) {
    return OutboundConnectionImpl(transport);
  }
}

/// The connection as `onConnect` sees it: a command goes straight onto the
/// socket just opened, and its reply is read back, with nothing between.
class _ConnectionPreamble implements AtCommandExecutor {
  final AtLookupImpl _lookUp;

  _ConnectionPreamble(this._lookUp);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    _lookUp.logger.finer('SENDING (on connect): $command');
    await _lookUp._connection!.write(command);
    return _lookUp.messageListener.read(
        maxWaitMilliSeconds: maxWaitMilliSeconds,
        transientWaitTimeMillis: transientWaitTimeMillis);
  }
}

/// Hands an authenticator's commands to the one connection its authentication
/// began on, and keeps the enrollment named by the last `pkam:` among them
/// that the atServer accepted.
class _SentCommands implements AtCommandExecutor {
  static final _pkam = RegExp(VerbSyntax.pkam);

  final AtLookupImpl _lookUp;
  final OutboundConnection _connection;
  final OutboundMessageListener _listener;

  /// The enrollment the last accepted `pkam:` named; null when none was
  /// accepted or it named none.
  String? pkamEnrollmentId;

  _SentCommands(this._lookUp, this._connection, this._listener);

  @override
  Future<String> sendSync(String command,
          {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) =>
      _lookUp._unlessStopped(() async {
        // NOTE: every command of one handshake goes on one connection.
        if (!identical(_lookUp._connection, _connection) ||
            _connection.isInValid()) {
          throw ConnectionInvalidException('The connection this '
              'authentication began on closed before it finished, so the rest '
              'of it is sent on no other connection');
        }
        _lookUp.logger.finer('SENDING: $command');
        await _connection.write(command);
        final response = await _listener.read(
            maxWaitMilliSeconds: maxWaitMilliSeconds,
            transientWaitTimeMillis: transientWaitTimeMillis);
        final pkam = _pkam.firstMatch(command.trim());
        if (pkam != null && response == 'data:success') {
          pkamEnrollmentId = pkam.namedGroup('enrollmentId');
        }
        return response;
      });
}
