import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/preference/monitor_preference.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';
import 'package:at_utils/at_logger.dart';

///
/// A [Monitor] object is used to receive notifications from the secondary server.
///
class Monitor {
  // Regex on with what the monitor is started
  String? _regex;

  // Time epoch milliseconds of the last notification received on this monitor
  int? _lastNotificationTime;

  final _monitorVerbResponseQueue = Queue();

  // Status on the monitor
  MonitorStatus status = MonitorStatus.NotStarted;

  final _logger = AtSignLogger('Monitor');

  bool _keepAlive = false;

  late String _atSign;

  late Function _onError;

  late Function _onResponse;

  late Function _retryCallBack;

  late AtClientPreference _preference;

  OutboundConnection? _monitorConnection;

  RemoteSecondary? _remoteSecondary;

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
      Function retryCallBack) {
    _onResponse = onResponse;
    _onError = onError;
    _preference = preference;
    _atSign = atSign;
    _regex = monitorPreference.regex;
    _keepAlive = monitorPreference.keepAlive;
    _lastNotificationTime = monitorPreference.lastNotificationTime;
    _remoteSecondary ??= RemoteSecondary(atSign, preference);
    _retryCallBack = retryCallBack;
  }

  /// Starts the monitor by establishing a new TCP/IP connection with the secondary server
  /// If [lastNotificationTime] expressed as EPOCH milliseconds is passed, only those notifications occurred after
  /// that time are notified.
  /// Calling start on already started monitor would not cause any exceptions and it will have no side affects.
  /// Calling start on monitor that is not started or erred will be started again.
  /// Calling [Monitor#getStatus] would return the status of the [Monitor]
  Future<void> start({int? lastNotificationTime}) async {
    if (status == MonitorStatus.Started) {
      // Monitor already started
      _logger.finer('Monitor is already running');
      return;
    }
    // This enables start method to be called with lastNotificationTime on the same instance of Monitor
    if (lastNotificationTime != null) {
      _logger.finer(
          'starting monitor for $_atSign with lastnotificationTime: $lastNotificationTime');
      _lastNotificationTime = lastNotificationTime;
    }
    try {
      await _checkConnectivity();
      //1. Get a new outbound connection dedicated to monitor verb.
      _monitorConnection = await _createNewConnection(
          _atSign, _preference.rootDomain, _preference.rootPort);
      var response;
      _monitorConnection!.getSocket().listen((event) {
        response = utf8.decode(event);
        _handleResponse(response, _onResponse);
      }, onError: (error) {
        _logger.severe('error in monitor $error');
        _handleError(error);
      }, onDone: () {
        _logger.finer('monitor done');
        _monitorConnection!.close();
        status = MonitorStatus.Stopped;
        // Future.delayed(Duration(seconds: 5), () => retryCallBack);
        _retryCallBack();
      });
      await _authenticateConnection();
      await _monitorConnection!.write(_buildMonitorCommand());
      status = MonitorStatus.Started;
      _logger.finer(
          'monitor started for $_atSign with last notification time: $_lastNotificationTime');
      return;
    } on Exception catch (e) {
      _handleError(e);
    }
  }

  Future<void> _authenticateConnection() async {
    await _monitorConnection!.write('from:$_atSign\n');
    var fromResponse = await _getQueueResponse();
    if (fromResponse.isEmpty) {
      throw UnAuthenticatedException('From response is empty');
    }
    _logger.finer('from result:$fromResponse');
    fromResponse = fromResponse.trim().replaceAll('data:', '');
    _logger.finer('fromResponse $fromResponse');
    var key = RSAPrivateKey.fromString(_preference.privateKey!);
    var sha256signature =
        key.createSHA256Signature(utf8.encode(fromResponse) as Uint8List);
    var signature = base64Encode(sha256signature);
    _logger.finer('Sending command pkam:$signature');
    await _monitorConnection!.write('pkam:$signature\n');
    var pkamResponse = await _getQueueResponse();
    if (!pkamResponse.contains('success')) {
      throw UnAuthenticatedException('Auth failed');
    }
    _logger.finer('auth success');
  }

  Future<OutboundConnection> _createNewConnection(
      String toAtSign, String rootDomain, int rootPort) async {
    //1. find secondary url for atsign from lookup library
    var secondaryUrl =
        await AtLookupImpl.findSecondary(toAtSign, rootDomain, rootPort);
    if (secondaryUrl == null) {
      throw Exception('Secondary url not found');
    }
    var secondaryInfo = _getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];

    //2. create a connection to secondary server
    var secureSocket = await SecureSocket.connect(host, int.parse(port));
    OutboundConnection _monitorConnection =
        OutboundConnectionImpl(secureSocket);
    return _monitorConnection;
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

  ///Returns the response of the monitor verb queue.
  Future<String> _getQueueResponse() async {
    var maxWaitMilliSeconds = 5000;
    var result = '';
    //wait maxWaitMilliSeconds seconds for response from remote socket
    var loopCount = (maxWaitMilliSeconds / 50).round();
    for (var i = 0; i < loopCount; i++) {
      await Future.delayed(Duration(milliseconds: 90));
      var queueLength = _monitorVerbResponseQueue.length;
      if (queueLength > 0) {
        result = _monitorVerbResponseQueue.removeFirst();
        // result from another secondary is either data or a @<atSign>@ denoting complete
        // of the handshake
        if (result.startsWith('data:')) {
          var index = result.indexOf(':');
          result = result.substring(index + 1, result.length - 2);
          break;
        }
      }
    }
    return result;
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
    status = MonitorStatus.Stopped;
    if(_monitorConnection != null) {
      _monitorConnection!.close();
    }
  }

// Stops the monitor from receiving notification
  MonitorStatus getStatus() {
    return status;
  }

  void _handleResponse(String response, Function callback) {
    if (response.toString().startsWith('notification')) {
      callback(response);
    } else {
      _monitorVerbResponseQueue.add(response);
    }
  }

  void _handleError(e) {
    _monitorConnection?.close();
    status = MonitorStatus.Errored;
    // Pass monitor and error
    // TBD : If retry = true should the onError needs to be called?
    if (_keepAlive) {
      // We will use a strategy here
      _logger.finer('Retrying start monitor due to error');
      _retryCallBack();
    } else {
      _onError(e);
    }
  }

  Future<void> _checkConnectivity() async {
    if (!(await NetworkUtil.isNetworkAvailable())) {
      throw AtConnectException('Internet connection unavailable to sync');
    }
    if (!(await _remoteSecondary!.isAvailable())) {
      throw AtConnectException('Secondary server is unavailable');
    }
    return;
  }
}

enum MonitorStatus { NotStarted, Started, Stopped, Errored }
