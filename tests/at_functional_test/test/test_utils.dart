import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:crypton/crypton.dart';
import 'package:at_client/at_client.dart';

import 'at_demo_credentials.dart' as demo_credentials;

class TestUtils {
  static AtClientPreference getPreference(String atsign) {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'test/hive/client';
    preference.commitLogPath = 'test/hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
    preference.rootDomain = 'vip.ve.atsign.zone';
    preference.decryptPackets = false;
    preference.pathToCerts = 'test/testData/cert.pem';
    preference.tlsKeysSavePath = 'test/tlsKeysFile';
    return preference;
  }
}

/// A simple wrapper around a socket for @ protocol communication.
class SimpleOutboundSocketHandler {
  static const int maxRetryCount = 10;
  late Queue _queue;
  final _buffer = ByteBuffer(capacity: 10240000);

  // ignore: prefer_typing_uninitialized_variables
  String host;
  int port;
  String atSign;
  SecureSocket? socket;

  /// Try to open a socket
  SimpleOutboundSocketHandler(this.host, this.port, this.atSign) {
    _queue = Queue();
  }

  void close() {
    print("Closing SimpleOutboundSocketHandler for $atSign ($host:$port)");
    socket!.destroy();
  }

  Future<void> connect() async {
    int retryCount = 1;
    while (retryCount < maxRetryCount) {
      try {
        socket = await SecureSocket.connect(host, port);
        if (socket != null) {
          return;
        }
      } on Exception {
        print('retrying "$host:$port" for connection.. $retryCount');
        await Future.delayed(Duration(seconds: 1));
        retryCount++;
      }
    }
    throw Exception(
        "Failed to connect to $host:$port after $retryCount attempts");
  }

  void startListening() {
    socket!.listen(_messageHandler);
  }

  /// Socket write
  Future<void> writeCommand(String command, {bool log = true}) async {
    if (log) {
      print('command sent: $command');
    }
    if (!command.endsWith('\n')) {
      command = command + '\n';
    }
    socket!.write(command);
  }

  /// Runs a from verb and pkam verb on the atsign param.
  Future<void> sendFromAndPkam() async {
    // FROM VERB
    await writeCommand('from:$atSign');
    var response = await read(timeoutMillis: 4000);
    response = response.replaceAll('data:', '');
    var pkamDigest = generatePKAMDigest(atSign, response);

    // PKAM VERB
    print("Sending pkam: command");
    await writeCommand('pkam:$pkamDigest', log: false);
    response = await read(timeoutMillis: 1000);
    print('pkam verb response $response');
    assert(response.contains('data:success'));
  }

  Future<void> clear() async {
    // queue.clear();
  }

  /// Handles responses from the remote secondary, adds to [_queue] for processing in [read] method
  /// Throws a [BufferOverFlowException] if buffer is unable to hold incoming data
  Future<void> _messageHandler(data) async {
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
      _queue.add(result);
    }
  }

  /// A message which is returned from [read] if throwTimeoutException is set to false
  static String readTimedOutMessage = 'E2E_SIMPLE_SOCKET_HANDLER_TIMED_OUT';

  Future<String> read(
      {bool log = true,
      int timeoutMillis = 4000,
      bool throwTimeoutException = true}) async {
    String result;

    // Wait this many milliseconds between checks on the queue
    var loopDelay = 250;

    // Check every loopDelay milliseconds until we get a response or timeoutMillis have passed.
    var loopCount = (timeoutMillis / loopDelay).round();
    for (var i = 0; i < loopCount; i++) {
      await Future.delayed(Duration(milliseconds: loopDelay));
      var queueLength = _queue.length;
      if (queueLength > 0) {
        result = _queue.removeFirst();
        if (log) {
          print("Response: $result");
        }
        // Got a response, let's return it
        return result;
      }
    }
    // No response - either throw a timeout exception or return the canned readTimedOutMessage
    if (throwTimeoutException) {
      throw AtTimeoutException(
          "No response from $host:$port ($atSign) after ${timeoutMillis / 1000} seconds");
    } else {
      print("read(): No response after $timeoutMillis milliseconds");
      return readTimedOutMessage;
    }
  }
}

extension Utils on SimpleOutboundSocketHandler {
  Future<String?> getVersion() async {
    await writeCommand('info\n');
    var version = await read();
    version = version.replaceAll('data:', '');
    // Since secondary version has gha<number> appended, remove the gha number from version
    // Hence using split.
    final versionObj = jsonDecode(version)['version'];
    var versionStr = versionObj?.split('+')[0];
    return versionStr;
  }
}

Future<SimpleOutboundSocketHandler> getSocketHandler(host, port, atSign) async {
  var handler = SimpleOutboundSocketHandler(host, port, atSign);
  await handler.connect();
  handler.startListening();
  await handler.sendFromAndPkam();
  return handler;
}

Future<SimpleOutboundSocketHandler> getUnAuthSocketHandler(
    host, port, atSign) async {
  var handler = SimpleOutboundSocketHandler(host, port, atSign);
  await handler.connect();
  handler.startListening();
  return handler;
}

String generatePKAMDigest(String atsign, String challenge) {
  var privateKey = demo_credentials.pkamPrivateKeyMap[atsign];
  privateKey = privateKey!.trim();
  var key = RSAPrivateKey.fromString(privateKey);
  challenge = challenge.trim();
  var sign =
      key.createSHA256Signature(Uint8List.fromList(utf8.encode(challenge)));
  return base64Encode(sign);
}

/// Returns the digest of the user.
String getDigest(String atsign, String key) {
  var secret = demo_credentials.cramKeyMap[atsign];
  secret = secret!.trim();
  var challenge = key;
  challenge = challenge.trim();
  var combo = '$secret$challenge';
  var bytes = utf8.encode(combo);
  var digest = sha512.convert(bytes);

  return digest.toString();
}
