import 'dart:io';

/// Verifies that an atServer is reachable and accepts TLS connections, by
/// opening a connection and immediately destroying it.
///
/// VM/native only — it is exported from `at_auth_io.dart`, not from the
/// wasm-safe `at_auth.dart`. Inject it when creating an [AtAuth]:
///
/// ```dart
/// AtAuth.create(probeSocket: defaultProbeSocket);
/// ```
///
/// Without it, `validateAtServer` skips the reachability probe.
Future<void> defaultProbeSocket(String host, int port) async {
  final socket =
      await SecureSocket.connect(host, port, timeout: Duration(seconds: 5));
  socket.destroy();
}
