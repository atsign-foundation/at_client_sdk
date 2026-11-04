import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// An atDirectory's HTTPS face and an atServer's `/ws` on one plain HTTP
/// port: the directory answers every atSign with this server's own address.
/// Sends its port, then the raw path of each request.
void hybridMain(StreamChannel channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  channel.sink.add(server.port);

  await for (HttpRequest request in server) {
    channel.sink.add(request.uri.path);
    if (request.uri.path == '/ws') {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((message) {
        final command =
            (message is String ? message : utf8.decode(message as List<int>))
                .trim();
        socket.add('data:ok:$command\n@');
      });
      continue;
    }
    request.response
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..write('127.0.0.1:${server.port}');
    await request.response.close();
  }
}
