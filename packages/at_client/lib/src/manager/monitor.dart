import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:meta/meta.dart';

///
/// A [Monitor] object is used to receive notifications from the secondary server.
///
class Monitor {
  // Regex on with what the monitor is started
  String? _regex;

  /// Capacity is represented in bytes.
  /// Throws [BufferOverFlowException] if data size exceeds 10MB.
  final _buffer = ByteBuffer(capacity: 10240000);

  // Time epoch milliseconds of the last notification received on this monitor
  int? _lastNotificationTime;

  final _monitorVerbResponseQueue = Queue();

  // Status on the monitor
  MonitorStatus status = MonitorStatus.notStarted;

  final _logger = AtSignLogger('Monitor');

  bool _keepAlive = false;

  late String _atSign;

  late Function _onError;

  late Function _onResponse;

  late Function _retryCallBack;

  late AtClientPreference _preference;

  OutboundConnection? _monitorConnection;

  late RemoteSecondary _remoteSecondary;

  final DefaultResponseParser _defaultResponseParser = DefaultResponseParser();

  late MonitorConnectivityChecker _monitorConnectivityChecker;

  late MonitorOutboundConnectionFactory _monitorOutboundConnectionFactory;

  bool _closeOpInProgress = false;

  /// The time (milliseconds since epoch) that the last heartbeat message was sent
  int _lastHeartbeatSentTime = 0;

  get lastHeartbeatSentTime => _lastHeartbeatSentTime;

  /// The time (milliseconds since epoch) that the last heartbeat response was received
  int _lastHeartbeatResponseTime = 0;

  get lastHeartbeatResponseTime => _lastHeartbeatResponseTime;

  /// Monitor will send heartbeat 'no-op' messages periodically.
  /// First heartbeat will be sent [_heartbeatInterval] after monitor has entered
  /// [MonitorStatus.started] state, if it is still in the started state.
  /// Subsequent heartbeats will be sent every [_heartbeatInterval] if the monitor
  /// is still in started state.
  /// If a heartbeat message doesn't get a response within one third of [_heartbeatInterval],
  /// the monitor will set an errored state, destroy the socket, and call the
  /// retryCallback
  late Duration _heartbeatInterval;

  get heartbeatInterval => _heartbeatInterval;

  ///
  /// Creates a [Monitor] object.
  ///
  /// [onResponse] function is called when a new batch of notifications are received from the server.
  /// This cannot be null.
  /// Example [onResponse] callback
  /// ```
  /// void onResponse(String notificationResponse) {
  /// // add your notification processing logic
  ///}
  ///```
  /// [onError] function is called when is some thing goes wrong with the processing.
  /// For example this could be:
  ///    - Unavailability of the network
  ///    - Exception while running the code
  /// This cannot be null.
  /// Example [onError] callback
  /// ```
  /// void onError(Monitor monitor, Exception e) {
  ///  // add your error handling logic
  /// }
  /// ```
  /// After calling [onError] monitor would stop sending any more notifications. If the error is recoverable
  /// and if [retry] is true the [Monitor] would continue and waits to recover from the error condition and not call [onError].
  ///
  /// For example if the app loses internet connection then [Monitor] would wait till the internet comes back and not call
  /// [onError]
  ///
  /// When the [regex] is passed only those notifications matching the [regex] will be notified
  /// When the [lastNotificationTime] is passed only those notifications AFTER the time value are notified.
  /// This is expressed as EPOCH time milliseconds.
  /// When [retry] is true
  ////
  Monitor(
      Function onResponse,
      Function onError,
      String atSign,
      AtClientPreference preference,
      MonitorPreference monitorPreference,
      Function retryCallBack,
      {RemoteSecondary? remoteSecondary,
      MonitorConnectivityChecker? monitorConnectivityChecker,
      MonitorOutboundConnectionFactory? monitorOutboundConnectionFactory,
      Duration? monitorHeartbeatInterval}) {
    _onResponse = onResponse;
    _onError = onError;
    _preference = preference;
    _atSign = atSign;
    _regex = monitorPreference.regex;
    _keepAlive = monitorPreference.keepAlive;
    _lastNotificationTime = monitorPreference.lastNotificationTime;
    _remoteSecondary = remoteSecondary ?? RemoteSecondary(atSign, preference);
    _retryCallBack = retryCallBack;
    _monitorConnectivityChecker =
        monitorConnectivityChecker ?? MonitorConnectivityChecker();
    _monitorOutboundConnectionFactory =
        monitorOutboundConnectionFactory ?? MonitorOutboundConnectionFactory();
    _heartbeatInterval =
        monitorHeartbeatInterval ?? preference.monitorHeartbeatInterval;
  }

  /// Starts the monitor by establishing a new TCP/IP connection with the secondary server
  /// If [lastNotificationTime] expressed as EPOCH milliseconds is passed, only those notifications occurred after
  /// that time are notified.
  /// Calling start on already started monitor would not cause any exceptions and it will have no side affects.
  /// Calling start on monitor that is not started or erred will be started again.
  /// Calling [Monitor#getStatus] would return the status of the [Monitor]
  Future<void> start({int? lastNotificationTime}) async {
    if (status == MonitorStatus.started) {
      // Monitor already started
      _logger.finer('Monitor is already running');
      return;
    }
    // This enables start method to be called with lastNotificationTime on the same instance of Monitor
    if (lastNotificationTime != null) {
      _logger.info(
          'starting monitor for $_atSign with lastNotificationTime: $lastNotificationTime');
      _lastNotificationTime = lastNotificationTime;
    }
    try {
      await _checkConnectivity();

      //1. Get a new outbound connection dedicated to monitor verb.
      _monitorConnection = await _createNewConnection(
          _atSign, _preference.rootDomain, _preference.rootPort);
      _monitorConnection!.getSocket().listen(_messageHandler, onDone: () {
        _logger.info(
            'socket.listen onDone called. Will destroy socket, set status stopped, call retryCallback');
        _callCloseStopAndRetry();
      }, onError: (error) {
        _logger.warning('socket.listen onError called with: $error');
        _handleError(error);
      });
      await _authenticateConnection();
      await _monitorConnection!.write(_buildMonitorCommand());
      status = MonitorStatus.started;
      _logger.info(
          'monitor started for $_atSign with last notification time: $_lastNotificationTime');

      _scheduleHeartbeat();
      return;
    } on Exception catch (e) {
      _handleError(e);
    }
  }

  /// Creates a delayed Future for the heartbeat to be sent [_heartbeatInterval] from now.
  /// If the monitor status is not still 'started' when the Future executes, then the
  /// heartbeat will not be sent.
  /// If the heartbeat is sent when the Future executes, then
  /// (1) a delayed Future is created to check, in [heartbeatInterval / 3] from now,
  /// that a heartbeat response has been received, and
  /// (2) we call _scheduleHeartbeat() again to schedule the next one to be sent
  void _scheduleHeartbeat() {
    if (status != MonitorStatus.started) {
      _logger.info("status is $status : not scheduling next heartbeat");
      return;
    }
    Future.delayed(_heartbeatInterval, () async {
      if (status != MonitorStatus.started) {
        _logger.info("status is $status : heartbeat will not be sent");
      } else {
        // send heartbeat and save the heartbeat sent time
        _logger.finest("sending heartbeat");
        _lastHeartbeatSentTime = DateTime.now().millisecondsSinceEpoch;
        // schedule a future to check if a timely heartbeat response is received
        Future.delayed(
            Duration(
                milliseconds: (_heartbeatInterval.inMilliseconds / 3).floor()),
            () async {
          if (_lastHeartbeatResponseTime < _lastHeartbeatSentTime) {
            _logger.warning(
                'Heartbeat response not received within expected duration. '
                'Heartbeat was sent at $_lastHeartbeatSentTime, '
                'it is now ${DateTime.now().millisecondsSinceEpoch}, '
                'last heartbeat response was received at $_lastHeartbeatResponseTime. '
                'Will close connection, set status stopped, call retryCallback');
            _callCloseStopAndRetry();
          }
        });

        await _monitorConnection!.write("noop:0\n");

        // schedule the next heartbeat to be sent
        _scheduleHeartbeat();
      }
    });
  }

  _callCloseStopAndRetry() {
    if (_closeOpInProgress) {
      _logger.info('Another closeStopAndRetry operation is in progress');
      return;
    }
    try {
      _closeOpInProgress = true;
      status = MonitorStatus.stopped;
      _monitorConnection!.close();
      _retryCallBack();
    } finally {
      _closeOpInProgress = false;
    }
  }

  Future<void> _authenticateConnection() async {
    await _monitorConnection!.write('from:$_atSign\n');
    var fromResponse = await getQueueResponse();
    if (fromResponse.isEmpty) {
      throw UnAuthenticatedException('From response is empty');
    }
    _logger.finer(
        'Authenticating the monitor connection: from result:$fromResponse');
    var key = RSAPrivateKey.fromString(_preference.privateKey!);
    var sha256signature =
        key.createSHA256Signature(utf8.encode(fromResponse) as Uint8List);
    var signature = base64Encode(sha256signature);
    _logger.finer('Authenticating the monitor connection: pkam:$signature');
    await _monitorConnection!.write('pkam:$signature\n');

    var pkamResponse = await getQueueResponse();
    if (!pkamResponse.contains('success')) {
      throw UnAuthenticatedException(
          'Monitor connection authentication failed');
    }
    _logger.finer('Monitor connection authentication successful');
  }

  Future<OutboundConnection> _createNewConnection(
      String toAtSign, String rootDomain, int rootPort) async {
    //1. look up the secondary url for this atsign
    var secondaryUrl = await _remoteSecondary.findSecondaryUrl();
    if (secondaryUrl == null) {
      throw Exception('Secondary url not found');
    }

    //2. create a connection to secondary server
    var outboundConnection =
        await _monitorOutboundConnectionFactory.createConnection(secondaryUrl,
            decryptPackets: _preference.decryptPackets,
            pathToCerts: _preference.pathToCerts,
            tlsKeysSavePath: _preference.tlsKeysSavePath);
    return outboundConnection;
  }

  ///Returns the response of the monitor verb queue.
  @visibleForTesting
  Future<String> getQueueResponse({int maxWaitTimeInMills = 6000}) async {
    dynamic monitorResponse;
    //waits for 30 seconds
    for (var i = 0; i < maxWaitTimeInMills; i++) {
      if (_monitorVerbResponseQueue.isNotEmpty) {
        // result from another secondary is either data or a @<atSign>@ denoting complete
        // of the handshake
        monitorResponse = _defaultResponseParser
            .parse(_monitorVerbResponseQueue.removeFirst());
        break;
      }
      await Future.delayed(Duration(milliseconds: 5));
    }
    if (monitorResponse == null) {
      throw AtTimeoutException(
          'Waited for ${5 * maxWaitTimeInMills} milliseconds and no response received');
    }
    // If monitor response contains error, return error
    if (monitorResponse.isError) {
      return '${monitorResponse.errorCode}: ${monitorResponse.errorDescription}';
    }
    return monitorResponse.response;
  }

  String _buildMonitorCommand() {
    var monitorVerbBuilder = MonitorVerbBuilder();
    if (_regex != null && _regex!.isNotEmpty) {
      monitorVerbBuilder.regex = _regex;
    }
    if (_lastNotificationTime != null) {
      monitorVerbBuilder.lastNotificationTime = _lastNotificationTime;
    }
    return monitorVerbBuilder.buildCommand();
  }

  /// Stops the monitor. Call [Monitor#start] to start it again.
  void stop() {
    status = MonitorStatus.stopped;
    if (_monitorConnection != null) {
      _monitorConnection!.close();
    }
  }

// Stops the monitor from receiving notification
  MonitorStatus getStatus() {
    return status;
  }

  void _handleResponse(String response, Function callback) {
    _logger.finer('received response on monitor: $response');
    if (response.toString().startsWith('notification')) {
      callback(response);
    } else if (response.toString() == 'data:ok' ||
        response.toString() == '@ok') {
      _lastHeartbeatResponseTime = DateTime.now().millisecondsSinceEpoch;
    } else {
      _monitorVerbResponseQueue.add(response);
    }
  }

  void _handleError(e) {
    _monitorConnection?.close();
    status = MonitorStatus.errored;
    // Pass monitor and error
    // TBD : If retry = true should the onError needs to be called?
    if (_keepAlive) {
      // We will use a strategy here
      _logger.info('Retrying start monitor due to error');
      _retryCallBack();
    } else {
      _logger.warning(
          '_keepAlive is false : monitor is errored, and NOT calling retryCallback');
      _onError(e);
    }
  }

  Future<void> _checkConnectivity() async {
    await _monitorConnectivityChecker.checkConnectivity(_remoteSecondary);
  }

  /// Handles messages on the inbound client's connection and calls the verb executor
  /// Closes the inbound connection in case of any error.
  /// Throw a [BufferOverFlowException] if buffer is unable to hold incoming data
  Future<void> _messageHandler(data) async {
    _logger.finest("_messageHandler received data");

    String result;
    if (!_buffer.isOverFlow(data)) {
      // skip @ prompt. byte code for @ is 64
      if (data.length == 1 && data.first == 64) {
        return;
      }
      //ignore prompt(@ or @<atSign>@) after '\n'. byte code for \n is 10
      if (data.last == 64 && data.contains(10)) {
        data = data.sublist(0, data.lastIndexOf(10) + 1);
        _buffer.append(data);
      } else if (data.length > 1 && data.first == 64 && data.last == 64) {
        // pol responses do not end with '\n'. Add \n for buffer completion
        _buffer.append(data);
        _buffer.addByte(10);
      } else {
        _buffer.append(data);
      }
    } else {
      _buffer.clear();
      throw BufferOverFlowException('Buffer overflow on outbound connection');
    }
    if (_buffer.isEnd()) {
      result = utf8.decode(_buffer.getData());
      result = result.trim();
      _buffer.clear();
      _handleResponse(result, _onResponse);
    }
  }

  /// NOT a part of API.
  /// Used to populate data into the monitorVerbResponseQueue for unit testing
  @visibleForTesting
  void addMonitorResponseToQueue(String data) {
    _monitorVerbResponseQueue.add(data);
  }
}

enum MonitorStatus { notStarted, started, stopped, errored }

class MonitorConnectivityChecker {
  Future<void> checkConnectivity(RemoteSecondary remoteSecondary) async {
    if (!(await NetworkUtil().isNetworkAvailable())) {
      throw AtConnectException(
          'Monitor connectivity checker: Internet connection unavailable');
    }
    return;
  }
}

class MonitorOutboundConnectionFactory {
  Future<OutboundConnection> createConnection(String secondaryUrl,
      {decryptPackets, pathToCerts, tlsKeysSavePath}) async {
    var secondaryInfo = _getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];

    SecureSocketConfig secureSocketConfig = SecureSocketConfig();
    secureSocketConfig.decryptPackets = decryptPackets;
    secureSocketConfig.pathToCerts = pathToCerts;
    secureSocketConfig.tlsKeysSavePath = tlsKeysSavePath;

    SecureSocket secureSocket = await SecureSocketUtil.createSecureSocket(
        host, port, secureSocketConfig);
    return OutboundConnectionImpl(secureSocket);
  }

  List<String> _getSecondaryInfo(String url) {
    var result = <String>[];
    if (url.contains(':')) {
      var arr = url.split(':');
      result.add(arr[0]);
      result.add(arr[1]);
    }
    return result;
  }
}
