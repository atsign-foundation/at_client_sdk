import 'package:http/http.dart' as http;

/// How long a probe waits for the atServer to answer before giving up.
///
/// The caller's retry loop applies its own, usually shorter, deadline on top;
/// this one bounds a probe that would otherwise hang on a black-holed route.
const Duration probeTimeout = Duration(seconds: 5);

/// Whether the atServer at [host]:[port] is up and reachable.
///
/// An atServer answers an HTTPS GET, so **any** HTTP response proves it is
/// there: the TLS handshake completed and the process replied. The status code
/// is deliberately not inspected — this asks "is it up", not "did it like the
/// request" — and only a transport failure (DNS, connect, TLS, timeout) throws,
/// which is what a caller's retry loop treats as not-up-yet.
///
/// This is the default because it is WASM-safe: it reaches the network through
/// `package:http` rather than `dart:io`. A `dart:io` caller that would rather
/// test the TLS handshake alone can inject `secureSocketProbe` from
/// `package:at_auth/at_auth_io.dart` instead.
Future<void> httpsProbe(String host, int port) async {
  final client = http.Client();
  try {
    await client.get(Uri.https('$host:$port', '/')).timeout(probeTimeout);
  } finally {
    client.close();
  }
}
