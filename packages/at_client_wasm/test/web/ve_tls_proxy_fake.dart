import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// Names the folder holding the virtual environment's `fullchain.pem` and
/// `privkey.pem`, the certificate for `vip.ve.atsign.zone`.
const certsDirVariable = 'AT_VE_CERTS_DIR';

/// A proxy's `/ws` over TLS on a loopback port, serving the virtual
/// environment's certificate. Sends its port, answers every frame with
/// `data:ok`, and answers any message on [channel] with the frames received
/// so far. When [certsDirVariable] is not set it binds nothing and sends,
/// instead of a port, the reason to skip, naming the variable.
void hybridMain(StreamChannel channel) async {
  final certs = Platform.environment[certsDirVariable];
  if (certs == null || certs.isEmpty) {
    channel.sink.add('$certsDirVariable is not set: point it at an at_server '
        "checkout's tools/build_virtual_environment/ve_base/contents/"
        'atsign/secondary/base/certs');
    await channel.sink.close();
    return;
  }
  final context = SecurityContext()
    ..useCertificateChain('$certs/fullchain.pem')
    ..usePrivateKey('$certs/privkey.pem');
  final server =
      await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
  final received = <String>[];
  channel.stream.listen((_) => channel.sink.add(List.of(received)),
      onDone: () => server.close(force: true));
  channel.sink.add(server.port);

  await for (final request in server) {
    if (request.uri.path != '/ws') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((message) {
      received
          .add(message is String ? message : utf8.decode(message as List<int>));
      socket.add('data:ok\n@');
    });
  }
}
