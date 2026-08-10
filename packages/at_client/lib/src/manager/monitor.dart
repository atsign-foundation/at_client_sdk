import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/response.dart' show AtResponse;
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';
import 'package:mutex/mutex.dart';

///
/// A [Monitor] object is used to receive notifications from the secondary server.
///
/// When [start] is called, the expectation is that the Monitor will run
/// constantly, reconnecting as required by network weather, until [stop] is
/// called.
///
/// There are two statuses:
/// [currentState] : the current status (listening / notConnected)
/// [targetState] : the target status (listening / notConnected)
class Monitor {
  /// Capacity is represented in bytes.
  /// Throws [BufferOverFlowException] if data size exceeds 10MB.
  final _buffer = ByteBuffer(capacity: 10240000);

  // Monitor connection status
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

  Future<void> Function(String jsonEncoded) handleNotification;

  Future<int?> Function() getLastNotificationTime;

  SecondaryAddressFinder secondaryAddressFinder;

  late AtClientPreference atClientPreference;

  OutboundConnection? _monitorConnection;
  StreamSubscription<Uint8List>? _monitorSocketSubscription;
  Completer? _connectionDoneCompleter;

  final DefaultResponseParser _defaultResponseParser = DefaultResponseParser();

  late final MonitorOutboundConnectionFactory monitorOutboundConnectionFactory;

  final AtChops? atChops;

  /// The PKAM signing algorithm for this monitor's connection. Defaults to
  /// the preference's value; a self-retrofit's ML-DSA enrollment passes its
  /// resolved algorithm, since the monitor re-authenticates on every
  /// (re)connect and a wrong algorithm fails each one against the
  /// record-authoritative atServer.
  late final SigningAlgoType signingAlgoType;

  final String? enrollmentId;

  final int newLineCodeUnit = 10;
  final int atCharCodeUnit = 64;

  Timer? heartbeatTimer;
  DateTime? lastReceipt;
  DateTime? connectedAt;

  static const defaultCommandTimeout = Duration(milliseconds: 2500);

  static const List<Duration> defaultConnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
    Duration(seconds: 21),
    Duration(seconds: 34),
  ];

  List<Duration> connectDelays;
  int delayIx = 0;

  Monitor({
    required this.atSign,
    required this.atClientPreference,
    required this.atChops,
    required this.enrollmentId,
    required this.secondaryAddressFinder,
    required this.handleNotification,
    required this.getLastNotificationTime,
    this.connectDelays = defaultConnectDelays,
    MonitorOutboundConnectionFactory? monitorOutboundConnectionFactory,
    SigningAlgoType? signingAlgoType,
  }) {
    // The preference is the documented legacy fallback: the caller passes the
    // key-material resolution when the enrollment has typed material.
    this.signingAlgoType =
        // ignore: deprecated_member_use_from_same_package
        signingAlgoType ?? atClientPreference.signingAlgoType;
    logger = AtSignLogger('Monitor ($atSign)');
    logger.finer('enrollmentId: $enrollmentId');
    this.monitorOutboundConnectionFactory =
        monitorOutboundConnectionFactory ?? MonitorOutboundConnectionFactory();
  }

  /// - Sets [targetState] to `listening`. Throws a [StateError] if
  /// [targetState] is already `listening`, or [currentState] is already `listening`
  ///
  /// - Start a keep alive loop as follows:
  /// - while [targetState] is `listening`
  ///   - connect
  ///   - startHeartbeat
  ///   - wait for done
  ///   - stopHeartbeat
  ///   - if [targetState] is still `listening`, wait for a little time, with
  ///     exponential backoff 1, 2, 3, 5, 8, 13, 21, 34 seconds and then 34
  ///     seconds each time, resetting to 1 once a connection is successful.
  void start() {
    if (targetState == NotificationListenerState.listening) {
      logger.shout('start() called, but targetState is already "listening"');
      return;
    }

    _targetState = NotificationListenerState.listening;

    Future.delayed(Duration(milliseconds: 0), () {
      stayConnected();
    });
  }

  /// - If there's a heartbeatTimer running, cancel it
  /// - close the [_monitorConnection]
  /// - set [currentState] to `notConnected`
  Future<void> closeConnection() async {
    logger.finer('closeConnection called');
    // stop heartbeat
    stopHeartbeat();

    if (_monitorConnection != null) {
      logger.finer('closeConnection: closing non-null _monitorConnection');
      await _monitorConnection!.close();

      _monitorConnection = null;
    } else {
      logger.finer(
          'closeConnection: _monitorConnection is null, no need to close');
    }

    if (_connectionDoneCompleter != null &&
        !_connectionDoneCompleter!.isCompleted) {
      logger.finer('closeConnection: Completing _connectionDoneCompleter');
      _connectionDoneCompleter!.complete();
    } else {
      logger.finer(
          'closeConnection: _connectionDoneCompleter is null or already complete,'
          ' no need to complete');
    }

    logger.finer('closeConnection: Setting currentState notConnected');
    _currentState = NotificationListenerState.notConnected;
    currentStateStreamController.add(_currentState);
    connectedAt = null;
  }

  /// Stops the monitor. Call [Monitor.start] to start it again.
  /// - set [targetState] to `notConnected`
  /// - calls [closeConnection]
  void stop() {
    logger.info('stop() called. Setting targetState to notConnected,'
        ' and calling closeConnection()');
    _targetState = NotificationListenerState.notConnected;

    closeConnection();
  }

  void startHeartbeat() {
    if (heartbeatTimer != null) {
      logger.warning('startHeartbeat called but heartbeatTimer exists');
      logger.warning('cancelling timer and restarting');
      stopHeartbeat();
    }
    logger.info('Starting heartbeat');

    heartbeatTimer = Timer(
      atClientPreference.monitorHeartbeatInterval,
      _heartbeat,
    );
  }

  void stopHeartbeat() {
    if (heartbeatTimer != null) {
      logger.info('Stopping heartbeat');
      heartbeatTimer!.cancel();
      heartbeatTimer = null;
    }
  }

  /// - while [targetState] is `listening`
  ///   - connect, authenticate, issue monitor command
  ///   - startHeartbeat
  ///   - wait for done
  ///   - stopHeartbeat
  ///   - if [targetState] is still `listening`, wait for a little time, with
  ///     exponential backoff 1, 2, 3, 5, 8, 13, 21, 34 seconds and then 34
  ///     seconds each time, resetting to 1 once a connection is successful.
  @visibleForTesting
  Future<void> stayConnected() async {
    while (targetState == NotificationListenerState.listening) {
      if (_monitorConnection != null) {
        throw StateError('_monitorConnection should be null');
      }
      if (_connectionDoneCompleter != null) {
        throw StateError('_connectionDoneCompleter should be null');
      }
      try {
        logger.info('Connecting');
        _connectionDoneCompleter = Completer();
        // connect
        _monitorConnection =
            await monitorOutboundConnectionFactory.createConnection(
                await secondaryAddressFinder.findSecondary(atSign),
                decryptPackets: atClientPreference.decryptPackets,
                pathToCerts: atClientPreference.pathToCerts,
                tlsKeysSavePath: atClientPreference.tlsKeysSavePath);

        logger.finer('Connection created');
        runZonedGuarded(() {
          logger.finer('Calling listen');
          _monitorSocketSubscription = _monitorConnection!.getSocket().listen(
            onSocketDataReceipt,
            onDone: () {
              if (_connectionDoneCompleter != null &&
                  !_connectionDoneCompleter!.isCompleted) {
                _connectionDoneCompleter!.complete();
              }
            },
            onError: (e) {
              if (_connectionDoneCompleter != null &&
                  !_connectionDoneCompleter!.isCompleted) {
                _connectionDoneCompleter!.complete();
              }
            },
          );
        }, (Object error, StackTrace st) {
          logger.shout('runZonedGuarded onError $error\nStack Trace:\n$st');
          if (_connectionDoneCompleter != null &&
              !_connectionDoneCompleter!.isCompleted) {
            logger.shout('runZonedGuarded onError - completing doneCompleter');
            _connectionDoneCompleter!.complete();
          }
        });

        int? lastNotificationTime = await getLastNotificationTime();

        // authenticate
        await _authenticateConnection();

        // issue monitor command
        var cmd = (MonitorVerbBuilder()
              ..selfNotificationsEnabled = (true)
              ..regex = (null)
              ..lastNotificationTime = lastNotificationTime)
            .buildCommand();
        logger.info('SENDING: ${cmd.trim()}');
        await _monitorConnection!.write(cmd);

        logger.info(
            'monitor started, last notification time: $lastNotificationTime');

        logger.finer('stayConnected: Setting currentState listening');
        _currentState = NotificationListenerState.listening;
        currentStateStreamController.add(_currentState);
        connectedAt = DateTime.now();
      } on SocketException catch (e) {
        logger.info('Failed to connect: ${e.message}');
        await closeConnection();
        _connectionDoneCompleter = null;
      } catch (e) {
        logger.info('Failed to connect: $e');
        await closeConnection();
        _connectionDoneCompleter = null;
      }

      if (currentState == NotificationListenerState.listening) {
        delayIx = 0;

        // start heartbeat
        startHeartbeat();

        // wait for connection done
        logger.info('stayConnected(): Waiting for Socket done');
        await _connectionDoneCompleter!.future;
        _connectionDoneCompleter = null;
        logger.info('stayConnected() : Socket done');

        await closeConnection(); // also stops heartbeat
      }

      // if [targetStatus] is still `listening`, wait before continuing
      if (targetState == NotificationListenerState.listening) {
        logger.info('Will attempt reconnect in ${connectDelays[delayIx]}');
        await Future.delayed(connectDelays[delayIx]);
        if (delayIx < (connectDelays.length - 1)) {
          delayIx++;
        }
      } else {
        logger.info('targetState is $targetState - will not auto reconnect');
      }
    }

    logger.info('stayConnected() complete - monitor stopped');
  }

  final Duration aMinute = const Duration(seconds: 60);

  /// Heartbeat checking
  ///
  /// - Send a heartbeat on the connection, wait for response
  /// - If response received
  ///   - if we've been connected for >= 60 seconds, verify we've received a
  ///   notification within that time. (Server currently always sends
  ///   statsNotifications - in future it will send small heartbeat
  ///   notifications once every 30 seconds)
  ///   - set the Timer for the next heartbeat
  /// - else
  ///   - close the connection
  void _heartbeat() async {
    if (currentState != NotificationListenerState.listening) {
      logger.info("status is $currentState : heartbeat will not be sent");
    } else {
      logger.finer("sending heartbeat");
      try {
        final AtResponse r = await sendCommand(
          "noop:0\n",
          timeout: atClientPreference.monitorHeartbeatResponseTimeout,
          logInfo: false,
        );
        logger.finer('Received heartbeat response: ${r.response}');

        DateTime now = DateTime.now().toUtc();
        // if we've been connected for over a minute
        if (connectedAt != null && now.difference(connectedAt!) > aMinute) {
          // and we've either received no notification, or last notification
          // was received over a minute ago
          if (lastReceipt == null || now.difference(lastReceipt!) > aMinute) {
            throw Exception('No notification received in past minute');
          } else {
            logger.info('Heartbeat OK: lastReceipt $lastReceipt');
          }
        }
        heartbeatTimer = Timer(
          atClientPreference.monitorHeartbeatInterval,
          _heartbeat,
        );
      } on TimeoutException {
        logger.info('No heartbeat response after'
            ' ${atClientPreference.monitorHeartbeatResponseTimeout}'
            ' - closing unresponsive connection to atServer');
        await closeConnection();
      } catch (e) {
        logger.info('Heartbeat exception $e - closing connection to atServer');
        await closeConnection();
      }
    }
  }

  Future<void> _authenticateConnection() async {
    logger.finer('Authenticating');
    if (atChops == null) {
      throw AtClientException.message(
          'cannot authenticate monitor connection without at_chops set');
    }
    AtResponse fromResponse =
        await sendCommand('from:$atSign\n', logInfo: true);

    if (fromResponse.isError) {
      throw UnAuthenticatedException('Bad "from" response: $fromResponse');
    }

    final atSigningInput = AtSigningInput(fromResponse.response)
      ..signingAlgoType = signingAlgoType
      ..hashingAlgoType = atClientPreference.hashingAlgoType
      ..signingMode = AtSigningMode.pkam;

    var signingResult = atChops!.sign(atSigningInput);

    var pkamBuilder = PkamVerbBuilder()
      ..signingAlgo = signingAlgoType.name
      ..hashingAlgo = atClientPreference.hashingAlgoType.name
      ..enrollmentlId = enrollmentId
      ..signature = signingResult.result;

    AtResponse pkamResponse = await sendCommand(
      pkamBuilder.buildCommand(),
      logInfo: true,
    );
    if (pkamResponse.isError || pkamResponse.response != 'success') {
      throw UnAuthenticatedException('Bad "pkam" response: $fromResponse');
    }

    logger.info('Monitor connection authentication successful');
  }

  @visibleForTesting
  Completer<AtResponse>? requestCompleter;

  Mutex sendCommandMutex = Mutex();

  @visibleForTesting
  Future<AtResponse> sendCommand(
    String command, {
    Duration timeout = defaultCommandTimeout,
    required bool logInfo,
  }) async {
    if (_monitorConnection == null) {
      throw StateError('No connection, cannot send command');
    }
    if (!command.endsWith('\n')) {
      throw ArgumentError('Commands must be terminated with \\n');
    }
    if (logInfo) {
      logger.info('Sending: ${command.trim()}');
    } else {
      logger.finer('Sending: ${command.trim()}');
    }

    try {
      await sendCommandMutex.acquire();
      requestCompleter = Completer();

      await _monitorConnection!.write(command);

      return await requestCompleter!.future.timeout(timeout);
    } finally {
      sendCommandMutex.release();
      requestCompleter = null;
    }
  }

  Future<void> handleAtServerResponse(String response) async {
    try {
      logger.finer('received response on monitor: $response');
      if (response.toString().startsWith('notification:')) {
        lastReceipt = DateTime.now().toUtc();
        await handleNotification(response);
      } else {
        if (requestCompleter != null && !requestCompleter!.isCompleted) {
          requestCompleter!.complete(_defaultResponseParser.parse(response));
        } else {
          logger.shout('Received response on monitor: $response'
              ' but have nowhere to send it');
        }
      }
    } catch (e, st) {
      logger.shout('Caught $e while handling received message $response');
      logger.shout('Stack Trace:\n$st');
    }
  }

  /// Handles messages on the inbound client's connection.
  /// Closes the inbound connection in case of any error.
  /// Throw a [BufferOverFlowException] if buffer is unable to hold incoming data
  @visibleForTesting
  Future<void> onSocketDataReceipt(dynamic data) async {
    _monitorSocketSubscription?.pause();
    try {
      // check buffer overflow
      _checkBufferOverFlow(data);

      // Loop from last index to until the end of data.
      // If a new line character is found, then it is end
      // of server response. process the data.
      // Else add the byte to buffer.
      for (int element = 0; element < data.length; element++) {
        // If it's a '\n' then complete data has been received. process it.
        if (data[element] == newLineCodeUnit) {
          String result = '';
          String doing = '';
          try {
            doing = '_messageHandler:utf8.decode data';
            result = utf8.decode(_buffer.getData().toList());

            doing = '_messageHandler:_stripPrompt';
            result = _stripPrompt(result);
            logger.finer('RECEIVED $result');

            doing = '_messageHandler:_handleResponse';
            await handleAtServerResponse(result);
          } catch (e) {
            logger.shout('$e from $doing while handling $result');
          } finally {
            _buffer.clear();
          }
        } else {
          _buffer.addByte(data[element]);
        }
      }
    } finally {
      _monitorSocketSubscription?.resume();
    }
  }

  void _checkBufferOverFlow(dynamic data) {
    if (_buffer.isOverFlow(data)) {
      int bufferLength = (_buffer.length() + data.length) as int;
      _buffer.clear();
      throw BufferOverFlowException(
          'data length exceeded the buffer limit. Data length : $bufferLength and Buffer capacity ${_buffer.capacity}');
    }
  }

  String _stripPrompt(String result) {
    var colonIndex = result.indexOf(':');
    if (colonIndex == -1) {
      return result;
    }
    var responsePrefix = result.substring(0, colonIndex);
    var response = result.substring(colonIndex);
    if (responsePrefix.contains('@')) {
      responsePrefix =
          responsePrefix.substring(responsePrefix.lastIndexOf('@') + 1);
    }
    return '$responsePrefix$response';
  }
}

class MonitorOutboundConnectionFactory {
  Future<OutboundConnection> createConnection(SecondaryAddress address,
      {decryptPackets, pathToCerts, tlsKeysSavePath}) async {
    SecureSocketConfig secureSocketConfig = SecureSocketConfig();
    secureSocketConfig.decryptPackets = decryptPackets;
    secureSocketConfig.pathToCerts = pathToCerts;
    secureSocketConfig.tlsKeysSavePath = tlsKeysSavePath;

    SecureSocket secureSocket = await SecureSocketUtil.createSecureSocket(
        address.host, address.port.toString(), secureSocketConfig);
    return OutboundConnectionImpl(secureSocket);
  }
}
