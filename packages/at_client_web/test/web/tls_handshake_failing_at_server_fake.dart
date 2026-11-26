import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// A loopback port kept bound for the test, with every connection destroyed as
/// it arrives.
///
/// The browser transport only opens `wss://`, so a `WebSocket` to this port
/// fails its TLS handshake at once: an entry point that reaches the atServer
/// stage fails there deterministically, and no other process can take the port
/// while the test runs.
void hybridMain(StreamChannel channel) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    channel.sink.add('connection');
    socket.destroy();
  });
  channel.sink.add(server.port);
  channel.stream.listen((_) {}, onDone: () => server.close());
}
