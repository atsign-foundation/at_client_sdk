import 'dart:io';

/// The native atServer readiness probe: opens a TLS connection to
/// ([host], [port]) and immediately destroys it, so a caller can tell whether
/// an atServer is listening yet without completing a handshake.
///
/// `AtAuthImpl` picks this up as its default `probeSocket` on any `dart:io`
/// host, via the conditional import in `src/io/defaults_io.dart` — you do not
/// normally name it. It is exported from `package:at_auth/at_auth.dart` (and
/// deliberately *not* from `at_auth_web.dart`, which cannot name `SecureSocket`)
/// so it can be passed explicitly when a caller is overriding the default:
///
/// ```dart
/// final atAuth = AtAuth.create(probeSocket: secureSocketProbe);
/// ```
Future<void> secureSocketProbe(String host, int port) async {
  final socket =
      await SecureSocket.connect(host, port, timeout: Duration(seconds: 5));
  socket.destroy();
}
