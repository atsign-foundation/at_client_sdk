import 'dart:io';

/// The native atServer readiness probe: opens a TLS connection to
/// ([host], [port]) and immediately destroys it, so a caller can tell whether
/// an atServer is listening yet without completing a handshake.
///
/// This is the probe `AtAuthImpl` used unconditionally before at_auth 4.0.0.
/// It is only reachable from `package:at_auth/at_auth_io.dart` — the WASM-safe
/// main barrel cannot name `SecureSocket`, so it leaves the probe uninjected.
/// Pass it to get 3.x behaviour back:
///
/// ```dart
/// final atAuth = AtAuth.create(probeSocket: secureSocketProbe);
/// ```
Future<void> secureSocketProbe(String host, int port) async {
  final socket =
      await SecureSocket.connect(host, port, timeout: Duration(seconds: 5));
  socket.destroy();
}
