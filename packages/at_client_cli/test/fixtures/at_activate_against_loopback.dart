import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:at_client_cli/at_client_cli.dart';

import 'loopback_registrar.dart';

/// Runs at_activate with the arguments given against a registrar on the
/// loopback interface, which refuses every request and logs each one it
/// serves to stderr. Exits with at_activate's code.
Future<void> main(List<String> args) async {
  final port = ReceivePort();
  await Isolate.spawn(_serve, port.sendPort);
  HttpOverrides.global = ToLoopbackRegistrar(await port.first as int);
  exit(await AtActivate.main(args));
}

Future<void> _serve(SendPort reply) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  reply.send(server.port);
  await for (final request in server) {
    await utf8.decoder.bind(request).join();
    stderr.writeln(servedLine(request));
    request.response
      ..statusCode = HttpStatus.badRequest
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'message': 'refused by the loopback registrar'}));
    await request.response.close();
  }
}
