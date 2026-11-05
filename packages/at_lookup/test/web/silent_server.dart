import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// Accepts connections and never answers, holding each one open. Sends its
/// port.
void hybridMain(StreamChannel channel) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final held = <Socket>[];
  server.listen(held.add);
  channel.sink.add(server.port);
  await channel.stream.drain<void>();
  for (final socket in held) {
    socket.destroy();
  }
  await server.close();
}
