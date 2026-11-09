import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// An atDirectory's HTTPS face, over plain HTTP, with the CORS header a
/// browser needs. Sends its port. Records the raw path of each request before
/// answering it, and answers `GET /__answered` with a JSON list of the paths
/// recorded since the last such request, which it never records.
void hybridMain(StreamChannel channel) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  channel.sink.add(server.port);
  final answered = <String>[];

  await for (HttpRequest request in server) {
    final path = request.uri.path;
    final response = request.response
      ..headers.set('Access-Control-Allow-Origin', '*');
    if (path == '/__answered') {
      response.write(jsonEncode(answered));
      answered.clear();
      await response.close();
      continue;
    }
    answered.add(path);
    if (path == '/@endless') {
      unawaited(_endless(response));
      continue;
    }
    switch (path) {
      case '/@alice':
        response.write('vip.example.org:1234');
      case '/@malformed':
        response.write('not-an-address');
      case '/@badport':
        response.write('vip.example.org:99999');
      case '/@elsewhere':
        response.write('vip.example.org@other.example.org:1234');
      case '/@huge':
        response.write('a' * 1000000);
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

/// A body with no end: chunks keep coming until the client goes away, or for
/// 20 seconds at most, so only a reader that stops at the bound sees an answer
/// before then.
Future<void> _endless(HttpResponse response) async {
  final stop = DateTime.now().add(const Duration(seconds: 20));
  try {
    while (DateTime.now().isBefore(stop)) {
      response.write('a' * 1024);
      await response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await response.close();
  } catch (_) {
    // The client aborted the request.
  }
}
