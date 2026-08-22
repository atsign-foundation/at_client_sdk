import 'dart:io';

import 'package:at_auth/src/auth/server_probe.dart' show probeTimeout;

/// Whether the atServer at [host]:[port] completes a TLS handshake.
///
/// A lighter check than the default [httpsProbe]: it opens a secure socket and
/// drops it, proving the port is listening and its certificate chain is
/// acceptable, without asking the atServer to answer anything. It cannot tell a
/// listening TLS terminator apart from a healthy atServer behind one.
///
/// Requires `dart:io`, which is why it lives here rather than in the main
/// barrel. Inject it as `probeSocket` where that trade is the one you want.
Future<void> secureSocketProbe(String host, int port) async {
  final socket = await SecureSocket.connect(host, port, timeout: probeTimeout);
  socket.destroy();
}
