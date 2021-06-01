import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';
import 'package:at_utils/at_logger.dart';

class Monitor {
  // Regex on with what the monitor is started
  var _regex;

  // Time epoch milliseconds of the last notification received on this monitor
  int _lastNotificationTime;

  final _monitorVerbResponseQueue = Queue();

  // Status on the monitor
  MonitorStatus status = MonitorStatus.NotStarted;

  final _logger = AtSignLogger('Monitor');

  var _retry = false;

  var _atSign;

  Function _onError;

  Function _onResponse;

  AtClientPreference _preference;

  var _monitorConnection;

  RemoteSecondary _remoteSecondary;

  // Constructor
  Monitor(Function onResponse, Function onError, String atSign,
      AtClientPreference preference,
      {String regex, int lastNotificationTime, bool retry = false}) {
    _onResponse = onResponse;
    _onError = onError;
    _preference = preference;
    _regex = regex;
    _atSign = atSign;
    _retry = retry;
    _remoteSecondary = RemoteSecondary(atSign, preference);
  }

// Starts the monitor by establishing a TCP/IP connection with the secondary server
  Future<void> start({int lastNotificationTime}) async {
    if (status == MonitorStatus.Started) {
      // Monitor already started
      _logger.finer('Monitor is already running');
      return;
    }
    // This enables start method to be called with lastNotificationTime on the same instance of Monitor
    if (lastNotificationTime != null) {
      _lastNotificationTime = lastNotificationTime;
    }
    try {
      await _checkConnectivity();
      //1. Get a new outbound connection dedicated to monitor verb.
      _monitorConnection = await _createNewConnection(
          _atSign, _preference.rootDomain, _preference.rootPort);
      var response;
      _monitorConnection.getSocket().listen((event) {
        response = utf8.decode(event);
        _handleResponse(response, _onResponse);
        print('inside socket listen: $response');
      }, onError: (error) {
        print('error in monitor');
        print(error);
      }, onDone: () {
        print('monitor done');
      });
      await _authenticateConnection();

      await _monitorConnection.write(_buildMonitorCommand());

      status = MonitorStatus.Started;

      return;
    } on Exception catch (e) {
      _handleError(e);
    }
  }

  Future<void> _authenticateConnection() async {
    _monitorConnection.write('from:$_atSign\n');
    var fromResponse = await _getQueueResponse();
    _logger.finer('from result:$fromResponse');
    fromResponse = fromResponse.trim().replaceAll('data:', '');
    _logger.finer('fromResponse $fromResponse');
    var key = RSAPrivateKey.fromString(_preference.privateKey);
    var sha256signature = key.createSHA256Signature(utf8.encode(fromResponse));
    var signature = base64Encode(sha256signature);
    _logger.finer('Sending command pkam:$signature');
    _monitorConnection.write('pkam:$signature\n');
    var pkamResponse = await _getQueueResponse();
    if (!pkamResponse.contains('success')) {
      throw UnAuthenticatedException('Auth failed');
    }
    _logger.finer('auth success');
    return _monitorConnection;
  }

  Future<OutboundConnection> _createNewConnection(
      String toAtSign, String rootDomain, int rootPort) async {
    //1. find secondary url for atsign from lookup library
    var secondaryUrl =
        await AtLookupImpl.findSecondary(toAtSign, rootDomain, rootPort);
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
    if (url != null && url.contains(':')) {
      var arr = url.split(':');
      result.add(arr[0]);
      result.add(arr[1]);
    }
    return result;
  }

  ///Returns the response of the monitor verb queue.
  Future<String> _getQueueResponse() async {
    var maxWaitMilliSeconds = 5000;
    String result;
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
    if (_regex != null) {
      monitorVerbBuilder.regex = _regex;
    }
    if (_lastNotificationTime != null) {
      monitorVerbBuilder.lastNotificationTime = _lastNotificationTime;
    }
    return monitorVerbBuilder.buildCommand();
  }

// Stops the monitor from receiving notification
  void stop() {
    status = MonitorStatus.Stopped;
    _monitorConnection.close();
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
    status = MonitorStatus.Errored;
    // Pass monitor and error
    // TBD : If retry = true should the onError needs to be called?
    if (_retry) {
      // We will use a strategy here
      Future.delayed(Duration(seconds: 3), start);
    } else {
      _onError(this, e);
    }
  }

  Future<void> _checkConnectivity() async {
    if (!NetworkUtil.isNetworkAvailable()) {
      throw AtConnectException('Internet connection unavailable to sync');
    }
    if (!(await _remoteSecondary.isAvailable())) {
      throw AtConnectException('Secondary server is unavailable');
    }
    return;
  }
}

enum MonitorStatus { NotStarted, Started, Stopped, Errored }
