import 'dart:io';

const _contentTypes = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'wasm': 'application/wasm',
  'json': 'application/json',
  'map': 'application/json',
};

/// A dev static server bound to both loopback families.
class StaticServer {
  StaticServer._(this._servers);

  final List<HttpServer> _servers;

  int get port => _servers.first.port;

  Future<void> close() =>
      Future.wait(_servers.map((s) => s.close(force: true)));
}

/// Serves [root] on loopback `port` (0 picks a free one) for a dev page.
///
/// `.wasm` goes out as `application/wasm`, which `compileStreaming` requires,
/// and every response is `no-store`, so a rebuilt `at_client.*` is never
/// shadowed by the browser cache. Binds IPv4 and IPv6 loopback separately
/// (never the wildcard, which would expose the build to the LAN) because
/// `localhost` resolves to either.
Future<StaticServer> serveStatic(Directory root, {int port = 8080}) async {
  final rootUri = root.absolute.uri;
  final v4 = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  final servers = [v4];
  try {
    servers.add(await HttpServer.bind(InternetAddress.loopbackIPv6, v4.port));
  } on SocketException {
    // IPv6 loopback unavailable; IPv4 alone still serves `localhost`.
  }
  for (final server in servers) {
    server.listen((request) => _serve(rootUri, request));
  }
  return StaticServer._(servers);
}

Future<void> _serve(Uri rootUri, HttpRequest request) async {
  final response = request.response;
  response.headers.set('Cache-Control', 'no-store');

  final segments = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
  // `pathSegments` has already percent-decoded, so `..%2f` arrives as one
  // segment holding a slash. Refusing these outright beats normalizing them.
  if (segments.any((s) => s == '..' || s.contains('/') || s.contains('\\'))) {
    response.statusCode = HttpStatus.forbidden;
    return response.close();
  }

  final target = rootUri.resolveUri(
      Uri(pathSegments: segments.isEmpty ? ['index.html'] : segments));
  final file = File.fromUri(target);
  if (!await file.exists()) {
    response.statusCode = HttpStatus.notFound;
    return response.close();
  }

  final extension = target.path.split('.').last;
  response.headers.contentType =
      ContentType.parse(_contentTypes[extension] ?? 'application/octet-stream');
  await response.addStream(file.openRead());
  await response.close();
}
