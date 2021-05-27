import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/util/network_util.dart';
import 'package:at_lookup/src/connection/outbound_connection.dart';
import 'package:at_commons/at_commons.dart';

class Monitor {
  // Regex on with what the monitor is started
  var _regex;

  // Date and time of the last notification received on this minotor
  var _lastNotificationTime;

  // Status on the monitor
  MonitorStatus status = MonitorStatus.NotStarted;

  var _retry = false;

  Function _onDone;

  Function _onError;

  Function _notificationCallBack;

  AtClientPreference _preference;

  var _monitorConnection;

  RemoteSecondary _remoteSecondary;

  var _command;

  // Constructor
  Monitor(Function onDone, Function onError, Function notificationCallBack,
      String atSign, String command, AtClientPreference preference,
      {String regex, DateTime lastNotificationTime, bool retry = false}) {
    _onDone = onDone;
    _onError = onError;
    _preference = preference;
    _regex = regex;
    _lastNotificationTime = lastNotificationTime;
    _retry = retry;
    _command = command;
    _remoteSecondary = RemoteSecondary(atSign, preference);
  }

// Starts the monitor by establishing a TCP/IP connection with the secondary server
  Future<void> start() async {
    try {
      await _checkConnectivity();
      //1. Get a new outbound connection dedicated to monitor verb.
      _monitorConnection = await _remoteSecondary.atLookUp.createConnection();
      await _remoteSecondary.authenticate(_preference.privateKey);
      await _remoteSecondary.executeCommand(_command);
      var response;
      _monitorConnection.getSocket().listen((event) {
        response = utf8.decode(event);
        _handleResponse(response, _notificationCallBack);
      });

      status = MonitorStatus.Started;
      _onDone(this);
    } on Exception catch (e) {
      _handleError(e);
    }
  }

// Stops the monitor from receiving notification
  Future<void> stop() {
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

  DateTime getLastNotificationTime() {
    return _lastNotificationTime;
  }

  String getRegex() {
    return _regex;
  }

  Future<void> _checkConnectivity() async {
    if (!NetworkUtil.isNetworkAvailable()) {
      throw AtConnectException('Internet connection unavailable to sync');
    }
    if (!(await _remoteSecondary.isAvailable())) {
      throw AtConnectException('Secondary server is unavailable');
    }
  }
}

enum MonitorStatus { NotStarted, Started, Stopped, Errored }
