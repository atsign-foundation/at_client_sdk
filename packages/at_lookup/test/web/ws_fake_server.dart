import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

void hybridMain(StreamChannel channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  channel.sink.add(server.port);

  await for (HttpRequest request in server) {
    if (request.uri.path == '/ws') {
      final webSocket = await WebSocketTransformer.upgrade(request);
      webSocket.listen((message) {
        if (message is List<int>) {
          final text = utf8.decode(message);
          if (text == '@exit') {
            webSocket.close();
            return;
          }
          webSocket.add('data:$text');
        } else if (message is String) {
          if (message == '@exit') {
            webSocket.close();
            return;
          }
          webSocket.add('data:$message');
        }
      });
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }
}
