import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// An atDirectory's HTTPS face and an atServer's `/ws` on one plain HTTP
/// port: the directory answers every atSign with this server's own address.
/// Sends its port. Records the raw path of each request before answering it,
/// and answers `GET /__answered` with a JSON list of the paths recorded since
/// the last such request, which it never records.
void hybridMain(StreamChannel channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  channel.sink.add(server.port);
  final answered = <String>[];

  await for (HttpRequest request in server) {
    final path = request.uri.path;
    if (path == '/__answered') {
      request.response
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write(jsonEncode(answered));
      answered.clear();
      await request.response.close();
      continue;
    }
    answered.add(path);
    if (path == '/ws') {
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
