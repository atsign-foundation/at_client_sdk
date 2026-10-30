import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:at_client_cli/src/register/register.dart' as register;

/// Runs at_register for `probe@example.com` against a registrar on the
/// loopback interface, which logs each request it serves to stderr.
///
/// The registrar hands out the atSign `registered` and, with the argument
/// `hands-over-cram`, accepts any verification code and hands over its CRAM
/// secret; with `refuses-codes`, it refuses every code.
Future<void> main(List<String> args) async {
  final port = ReceivePort();
  await Isolate.spawn(_serve, [port.sendPort, args.single]);
  HttpOverrides.global = _ToLoopback(await port.first as int);
  await register.main(['-e', 'probe@example.com']);
}

Future<void> _serve(List<Object> args) async {
  final reply = args[0] as SendPort;
  final mode = args[1] as String;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  reply.send(server.port);
  await for (final request in server) {
    await utf8.decoder.bind(request).join();
    stderr.writeln('registrar served ${request.method} ${request.uri.path}');
    final Object answer = switch (request.uri.path) {
      '/api/app/v3/get-free-atsign' => {
          'data': {'atsign': 'registered'}
        },
      '/api/app/v3/register-person' => {'message': 'Sent Successfully'},
      '/api/app/v3/validate-person' when mode == 'refuses-codes' => {
          'message':
              'The code you have entered is invalid or expired. Please try again?'
        },
      '/api/app/v3/validate-person' => {
          'message': 'Verified',
          'cramkey': '@registered:cram-secret'
        },
      _ => throw StateError('no such registrar path: ${request.uri.path}'),
    };
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(answer));
    await request.response.close();
  }
}

/// Sends every registrar request to the loopback registrar, in the clear.
class _ToLoopback extends HttpOverrides {
  final int port;

  _ToLoopback(this.port);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, proxyHost, proxyPort) {
          if (uri.host != 'my.atsign.com') {
            throw StateError('at_register dialled ${uri.host}');
          }
          return Socket.startConnect(InternetAddress.loopbackIPv4, port);
        };
}
