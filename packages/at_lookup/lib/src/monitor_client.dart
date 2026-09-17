import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

/// Utility class to execute monitor verb.
/// Deprecated with no replacement, because nothing uses it: a tree-wide
/// search finds its own declaration and nothing else.
///
/// It also predates the connect timeouts - `_createNewConnection` builds its
/// socket directly rather than through `SecureSocketUtil`, so it never got
/// them. A caller wanting a notification stream should use
/// [AtLookUp.withSecureSocket] and [AtLookupMuxable.notifications], which
/// share one connection, one listener and one reconnect policy with the rest
/// of at_lookup.
@Deprecated('Use AtLookUp.withSecureSocket and AtLookupMuxable.notifications. '
    'Removed in the next major release.')
class MonitorClient {
  final _monitorVerbResponseQueue = Queue();
  late String response;
  late String _privateKey;
  var logger = AtSignLogger('MonitorVerbManager');

  MonitorClient(String privateKey) {
    _privateKey = privateKey;
  }

  ///Monitor Verb
  Future<OutboundConnection> executeMonitorVerb(String command, String atSign,
      String rootDomain, int rootPort, Function notificationCallBack,
      {bool auth = true, Function? restartCallBack}) async {
    //1. Get a new outbound connection dedicated to monitor verb.
    var monitorConnection =
        await _createNewConnection(atSign, rootDomain, rootPort);
    //2. Listener on _monitorConnection.
    monitorConnection.getSocket().listen((event) {
      response = utf8.decode(event);
      // If response contains data to be notified, invoke callback function.
      if (response.toString().startsWith('notification')) {
        notificationCallBack(response);
      } else {
        _monitorVerbResponseQueue.add(response);
      }
    }, onError: (error) {
      _errorHandler(error, monitorConnection);
    }, onDone: () {
      _finishedHandler(monitorConnection);
      restartCallBack!(command, notificationCallBack, _privateKey);
    });
    await _authenticateConnection(atSign, monitorConnection);
    //3. Write monitor verb to connection
    await monitorConnection.write(command);
    return monitorConnection;
  }

  /// Create a new connection for monitor verb.
  Future<OutboundConnection> _createNewConnection(
      String toAtSign, String rootDomain, int rootPort) async {
    //1. find secondary url for atsign from lookup library
    var secondaryUrl =
        // ignore: deprecated_member_use_from_same_package
        await AtLookupImpl.findSecondary(toAtSign, rootDomain, rootPort);
    var secondaryInfo = _getSecondaryInfo(secondaryUrl);
    var host = secondaryInfo[0];
    var port = secondaryInfo[1];

    //2. create a connection to secondary server
    var secureSocket = await SecureSocket.connect(host, int.parse(port));
    OutboundConnection monitorConnection = OutboundConnectionImpl(secureSocket);
    return monitorConnection;
  }

  /// To authenticate connection via PKAM verb.
  Future<OutboundConnection> _authenticateConnection(
      String atSign, OutboundConnection monitorConnection) async {
    await monitorConnection.write('from:$atSign\n');
    var fromResponse = await _getQueueResponse();
    logger.info('from result:$fromResponse');
    fromResponse = fromResponse.trim().replaceFirst(RegExp(r'^data:'), '');
    logger.info('fromResponse $fromResponse');
    // RSA SHA-256 sign via at_chops (wraps the same crypton
    // RSAPrivateKey.createSHA256Signature; only the private key is used).
    var sha256signature = PkamSigningAlgo(
            AtPkamKeyPair.create('', _privateKey), HashingAlgoType.sha256)
        .sign(Uint8List.fromList(utf8.encode(fromResponse)));
    var signature = base64Encode(sha256signature);
    logger.info('Sending command pkam:$signature');
    await monitorConnection.write('pkam:$signature\n');
    var pkamResponse = await _getQueueResponse();
    if (!pkamResponse.contains('success')) {
      throw UnAuthenticatedException('Auth failed');
    }
    logger.info('auth success');
    return monitorConnection;
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

  List<String> _getSecondaryInfo(String? url) {
    var result = <String>[];
    if (url != null && url.contains(':')) {
      var arr = url.split(':');
      result.add(arr[0]);
      result.add(arr[1]);
    }
    return result;
  }

  /// Logs the error and closes the [OutboundConnection]
  Future<void> _errorHandler(
      dynamic error, OutboundConnection connection) async {
    await _closeConnection(connection);
  }

  /// Closes the [OutboundConnection]
  void _finishedHandler(OutboundConnection connection) async {
    await _closeConnection(connection);
  }

  Future<void> _closeConnection(OutboundConnection connection) async {
    if (!connection.isInValid()) {
      await connection.close();
    }
  }
}
