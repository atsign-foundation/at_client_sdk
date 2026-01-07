import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/response.dart' show AtResponse;
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';

///
/// A [Monitor] object is used to receive notifications from the secondary server.
///
/// When [start] is called, the expectation is that the Monitor will run
/// constantly, reconnecting as required by network weather, until [stop] is
/// called.
///
/// There are two statuses:
/// [currentState] : the current status (connected / unconnected)
/// [targetState] : the target status (connected / unconnected)
class Monitor {
  /// Capacity is represented in bytes.
  /// Throws [BufferOverFlowException] if data size exceeds 10MB.
  final _buffer = ByteBuffer(capacity: 10240000);

  // Monitor connection status
  MonitorState _currentState = MonitorState.notConnected;
  MonitorState _targetState = MonitorState.notConnected;

  MonitorState get currentState => _currentState;

  MonitorState get targetState => _targetState;

  StreamController<MonitorState> currentStateStreamController =
      StreamController.broadcast();

  Stream<MonitorState> get currentStateStream =>
      currentStateStreamController.stream;
  late final AtSignLogger logger;

  final String atSign;

  Future<void> Function(String jsonEncoded) handleNotification;

  Future<int?> Function() getLastNotificationTime;

  SecondaryAddressFinder secondaryAddressFinder;

  late AtClientPreference atClientPreference;

  OutboundConnection? _monitorConnection;
  Completer? _connectionDoneCompleter;

  final DefaultResponseParser _defaultResponseParser = DefaultResponseParser();

  late final MonitorOutboundConnectionFactory monitorOutboundConnectionFactory;

  final AtChops? atChops;

  final String? enrollmentId;

  final int newLineCodeUnit = 10;
  final int atCharCodeUnit = 64;

  Timer? heartbeatTimer;

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
  }) {
    logger = AtSignLogger('Monitor ($atSign)');
    logger.finer('enrollmentId: $enrollmentId');
    this.monitorOutboundConnectionFactory =
        monitorOutboundConnectionFactory ?? MonitorOutboundConnectionFactory();
  }

  /// - Sets [targetState] to `connected`. Throws a [StateError] if
  /// [targetState] is already `connected`, or [currentState] is already `connected`
  ///
  /// - Start a keep alive loop as follows:
  /// - while [targetState] is `connected`
  ///   - connect
  ///   - startHeartbeat
  ///   - wait for done
  ///   - stopHeartbeat
  ///   - if [targetState] is still `connected`, wait for a little time, with
  ///     exponential backoff 1, 2, 3, 5, 8, 13, 21, 34 seconds and then 34
  ///     seconds each time, resetting to 1 once a connection is successful.
  Future<void> start() async {
    if (targetState == MonitorState.connected) {
      logger.shout('start() called, but targetStatus is already "connected"');
      return;
    }

    _targetState = MonitorState.connected;

    unawaited(Future.delayed(Duration(milliseconds: 1), () {
      stayConnected();
    }));
  }

  @visibleForTesting
  Future<void> closeConnection() async {
    // stop heartbeat
    stopHeartbeat();

    if (_monitorConnection != null) {
      await _monitorConnection!.close();

      _monitorConnection = null;
    }

    if (_connectionDoneCompleter != null &&
        !_connectionDoneCompleter!.isCompleted) {
      _connectionDoneCompleter!.complete();
    }

    _currentState = MonitorState.notConnected;
    currentStateStreamController.add(_currentState);
  }

  /// Stops the monitor. Call [Monitor#start] to start it again.
  /// - If [currentState] is already `unconnected`, return
  /// - If there's a heartbeatTimer running, cancel it
  /// - close the [_monitorConnection]
  /// - set [currentState] to `unconnected`
  /// - set [targetState] to `unconnected`
  void stop() {
    _targetState = MonitorState.notConnected;

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
      _sendHeartbeat,
    );
  }

  void stopHeartbeat() {
    if (heartbeatTimer != null) {
      logger.info('Stopping heartbeat');
      heartbeatTimer!.cancel();
      heartbeatTimer = null;
    }
  }

  /// - while [targetState] is `connected`
  ///   - connect, authenticate, issue monitor command
  ///   - startHeartbeat
  ///   - wait for done
  ///   - stopHeartbeat
  ///   - if [targetState] is still `connected`, wait for a little time, with
  ///     exponential backoff 1, 2, 3, 5, 8, 13, 21, 34 seconds and then 34
  ///     seconds each time, resetting to 1 once a connection is successful.
  @visibleForTesting
  Future<void> stayConnected() async {
    while (targetState == MonitorState.connected) {
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

        runZonedGuarded(() {
          _monitorConnection!.getSocket().listen(
            _messageHandler,
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
        logger.info('Attempting connect with lastNotificationTime:'
            ' $lastNotificationTime');

        // authenticate
        await _authenticateConnection();

        // issue monitor command
        var cmd = (MonitorVerbBuilder()
              ..selfNotificationsEnabled = (true)
              ..regex = (null)
              ..lastNotificationTime = lastNotificationTime)
            .buildCommand();
        logger.info('SENDING: $cmd');
        await _monitorConnection!.write(cmd);

        logger.info(
            'monitor started, last notification time: $lastNotificationTime');

        _currentState = MonitorState.connected;
        currentStateStreamController.add(_currentState);
      } on SocketException catch (e) {
        logger.shout('Failed to connect: ${e.message}');
        await closeConnection();
        _connectionDoneCompleter = null;
      } catch (e) {
        logger.shout('Failed to connect: $e');
        await closeConnection();
        _connectionDoneCompleter = null;
      }

      if (currentState == MonitorState.connected) {
        delayIx = 0;

        // start heartbeat
        startHeartbeat();

        // wait for connection done
        logger.info('stayConnected(): Waiting for Socket done');
        await _connectionDoneCompleter!.future;
        _connectionDoneCompleter = null;
        logger.shout('stayConnected() : Socket done');

        await closeConnection(); // also stops heartbeat
      }

      // if [targetStatus] is still `connected`, wait before continuing
      if (targetState == MonitorState.connected) {
        logger.shout('Will attempt reconnect in ${connectDelays[delayIx]}');
        await Future.delayed(connectDelays[delayIx]);
        if (delayIx < (connectDelays.length - 1)) {
          delayIx++;
        }
      } else {
        logger.info('targetState is $targetState - will not auto reconnect');
      }
    }

    logger.shout('stayConnected() complete');
  }

  /// - Send a heartbeat on the connection, wait for response
  /// - If response received
  ///   - set the Timer for the next heartbeat
  /// - else
  ///   - close the connection
  void _sendHeartbeat() async {
    if (currentState != MonitorState.connected) {
      logger.shout("status is $currentState : heartbeat will not be sent");
    } else {
      logger.info("sending heartbeat");
      try {
        final AtResponse r = await sendCommand("noop:0\n",
            timeout: atClientPreference.monitorHeartbeatResponseTimeout);
        logger.info('Received heartbeat response: ${r.response}');
        heartbeatTimer = Timer(
          atClientPreference.monitorHeartbeatInterval,
          _sendHeartbeat,
        );
      } on TimeoutException {
        logger.shout('No heartbeat response after'
            ' ${atClientPreference.monitorHeartbeatResponseTimeout}'
            ' - closing unresponsive connection to atServer');
        await closeConnection();
      } catch (e) {
        logger.shout('Heartbeat exception $e - closing connection to atServer');
        await closeConnection();
      }
    }
  }

  Future<void> _authenticateConnection() async {
    if (atChops == null) {
      throw AtClientException.message(
          'cannot authenticate monitor connection without at_chops set');
    }
    AtResponse fromResponse = await sendCommand('from:$atSign\n');

    if (fromResponse.isError) {
      throw UnAuthenticatedException('Bad "from" response: $fromResponse');
    }

    final atSigningInput = AtSigningInput(fromResponse.response)
      ..signingAlgoType = atClientPreference.signingAlgoType
      ..hashingAlgoType = atClientPreference.hashingAlgoType
      ..signingMode = AtSigningMode.pkam;

    var signingResult = atChops!.sign(atSigningInput);

    var pkamBuilder = PkamVerbBuilder()
      ..signingAlgo = atClientPreference.signingAlgoType.name
      ..hashingAlgo = atClientPreference.hashingAlgoType.name
      ..enrollmentlId = enrollmentId
      ..signature = signingResult.result;

    AtResponse pkamResponse = await sendCommand(pkamBuilder.buildCommand());
    if (pkamResponse.isError || pkamResponse.response != 'success') {
      throw UnAuthenticatedException('Bad "pkam" response: $fromResponse');
    }

    logger.info('Monitor connection authentication successful');
  }

  @visibleForTesting
  Completer<AtResponse>? requestCompleter;

  @visibleForTesting
  Future<AtResponse> sendCommand(
    String command, {
    Duration timeout = defaultCommandTimeout,
  }) async {
    if (requestCompleter != null) {
      throw StateError('Cannot send command,'
          ' still waiting for response from previous command');
    }
    if (_monitorConnection == null) {
      throw StateError('No connection, cannot send command');
    }
    if (!command.endsWith('\n')) {
      throw ArgumentError('Commands must be terminated with \\n');
    }
    logger.info('Sending: ${command.trim()}');

    requestCompleter = Completer();

    await _monitorConnection!.write(command);

    try {
      return await requestCompleter!.future.timeout(timeout);
    } finally {
      requestCompleter = null;
    }
  }

  void _handleResponse(String response, Function callback) {
    try {
      logger.finer('received response on monitor: $response');
      if (response.toString().startsWith('notification:')) {
        callback(response);
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
  Future<void> _messageHandler(dynamic data) async {
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
          _handleResponse(result, handleNotification);
        } catch (e) {
          logger.shout('$e from $doing while handling $result');
        } finally {
          _buffer.clear();
        }
      } else {
        _buffer.addByte(data[element]);
      }
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

enum MonitorState { connected, notConnected }

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
