import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// An atDirectory's HTTPS face, over plain HTTP, with the CORS header a
/// browser needs. Sends its port, then the raw path of each request.
void hybridMain(StreamChannel channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  channel.sink.add(server.port);

  await for (HttpRequest request in server) {
    final path = request.uri.path;
    channel.sink.add(path);
    final response = request.response
      ..headers.set('Access-Control-Allow-Origin', '*');
    switch (path) {
      case '/@alice':
        response.write('vip.example.org:1234');
      case '/@malformed':
        response.write('not-an-address');
      case '/@badport':
        response.write('vip.example.org:99999');
      case '/@broken':
        response.statusCode = HttpStatus.internalServerError;
      case '/@slow':
        await Future<void>.delayed(const Duration(seconds: 2));
        response.write('vip.example.org:1234');
      default:
        response
          ..statusCode = HttpStatus.notFound
          ..write('404 not found');
    }
    await response.close();
  }
}
