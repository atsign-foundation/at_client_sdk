import 'dart:convert';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

class Monitor {
  // Regex on with what the monitor is started
  var regex;

  // Time epoch milliseconds of the last notification received on this monitor
  int lastNotificationTime;

  // Status on the monitor
  MonitorStatus status = MonitorStatus.NotStarted;

  var _retry = false;

  Function _onError;

  Function _onResponse;

  AtClientPreference _preference;

  var _monitorConnection;

  RemoteSecondary _remoteSecondary;

  // Constructor
  Monitor(Function onResponse, Function onError, String atSign,
      AtClientPreference preference,
      {bool retry = false}) {
    _onResponse = onResponse;
    _onError = onError;
    _preference = preference;
    _retry = retry;
    _remoteSecondary = RemoteSecondary(atSign, preference);
  }

// Starts the monitor by establishing a TCP/IP connection with the secondary server
  Future<void> start() async {
    try {
      await _checkConnectivity();
      //1. Get a new outbound connection dedicated to monitor verb.
      _monitorConnection = await _remoteSecondary.atLookUp.createConnection();
      var response;
      _monitorConnection.getSocket().listen((event) {
        response = utf8.decode(event);
        _handleResponse(response, _onResponse);
      });
      await _remoteSecondary.authenticate(_preference.privateKey);

      await _remoteSecondary.executeCommand(_buildMonitorCommand());

      status = MonitorStatus.Started;
      return;
    } on Exception catch (e) {
      _handleError(e);
    }
  }

  String _buildMonitorCommand() {
    var monitorVerbBuilder = MonitorVerbBuilder();
    if (regex != null) {
      monitorVerbBuilder.regex = regex;
    }
    if (lastNotificationTime != null) {
      monitorVerbBuilder.lastNotificationTime = lastNotificationTime;
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
