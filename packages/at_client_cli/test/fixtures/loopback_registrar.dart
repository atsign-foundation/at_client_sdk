import 'dart:io';

import 'package:at_client_cli/src/register/registrar_api_constants.dart';

/// The line a loopback registrar logs to stderr for each request it serves:
/// its method and path, and whether it carried the registrar API key this
/// process's environment sets in `AT_REGISTRAR_API_KEY`, the built-in one, or
/// another. It never quotes a key.
String servedLine(HttpRequest request) {
  final sent = request.headers.value(HttpHeaders.authorizationHeader);
  final set = Platform.environment['AT_REGISTRAR_API_KEY'];
  final key = sent == null
      ? 'no key'
      : sent == set
          ? 'the key set'
          : sent == RegistrarApiConstants.authorization
              ? 'the built-in key'
              : 'another key';
  return 'registrar served ${request.method} ${request.uri.path} with $key';
}

/// Sends every request for my.atsign.com to the loopback registrar on [port],
/// in the clear, and refuses any other host.
class ToLoopbackRegistrar extends HttpOverrides {
  final int port;

  ToLoopbackRegistrar(this.port);

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, proxyHost, proxyPort) {
          if (uri.host != 'my.atsign.com') {
            throw StateError('dialled ${uri.host}, not the registrar');
          }
          return Socket.startConnect(InternetAddress.loopbackIPv4, port);
        };
}
