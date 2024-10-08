import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_client/at_client.dart';

// Queue to simulate the message buffer
var _queue = Queue<String>();
var maxRetryCount = 10;
var retryCount = 1;

void main() {
  AtSignLogger.root_level = 'finer';
  var atSign = '@bob';
  WebSocket websocket;
  late SecureSocketConfig secureSocketConfig;

  test('checking for test environment readiness', () async {
    secureSocketConfig = SecureSocketConfig()..decryptPackets = false;
    websocket = await SecureSocketUtil.createSecureWebSocket(
        'vip.ve.atsign.zone', '6365', secureSocketConfig);
    print('Connection established');

    websocket.listen((onData) {
      print("on data");
    });

    // Start listening for WebSocket messages
    // socketListener(websocket);

    // Wait for the '@' prompt before sending the scan command
    await waitForPrompt('@');

    // Send the 'scan' command once the '@' prompt is received
    websocket.add('scan\n');
    print('Sent scan command');

    await Future.delayed(Duration(minutes: 5));

    // // Wait for and print the response from the 'scan' command
    // String response = await read();
    // print('Scan result: $response');
  }, timeout: Timeout(Duration(minutes: 5)));
}

/// Socket Listener
void socketListener(WebSocket ws) {
  print("inside socket listener");
  ws.listen((data) {
    print("inside listen method");
    _messageHandler(data);
  }, onError: (error) {
    print('WebSocket error: $error');
  });
  // , onDone: () {
  //   print('WebSocket closed');
  // });
}

/// Message Handler
void _messageHandler(dynamic data) {
  var message = utf8.decode(data);
  print('Received: $message');

  // Add message to the queue for processing
  _queue.add(message);
}

/// Waits for the '@' prompt
Future<void> waitForPrompt(String prompt) async {
  while (true) {
    String response = await read();
    if (response.contains(prompt)) {
      print('Prompt received: $prompt');
      break;
    }
    await Future.delayed(
        Duration(milliseconds: 100)); // Slight delay before checking again
  }
}

/// Reads data from the queue with a timeout
Future<String> read({int maxWaitMilliSeconds = 5000}) async {
  String result = '';
  var loopCount = (maxWaitMilliSeconds / 50).round();

  for (var i = 0; i < loopCount; i++) {
    await Future.delayed(Duration(milliseconds: 100));

    if (_queue.isNotEmpty) {
      result = _queue.removeFirst();
      return result; // Return the first result from the queue
    }
  }

  return result; // Return whatever was collected in the timeout
}
