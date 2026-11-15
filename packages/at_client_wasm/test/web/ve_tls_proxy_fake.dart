import 'dart:convert';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

/// Names the folder holding the virtual environment's `fullchain.pem` and
/// `privkey.pem`, the certificate for `vip.ve.atsign.zone`.
const certsDirVariable = 'AT_VE_CERTS_DIR';

/// Names the folder holding a `fullchain.pem` and `privkey.pem` for the IPv6
/// loopback address, `IP:::1` in its subjectAltName, that the browser
/// running the tests trusts.
const ipv6CertsDirVariable = 'AT_IPV6_CERTS_DIR';

/// The atDirectory answer the fake gives for `@alice`.
const aliceAddress = 'alice.example:6464';

/// A proxy's `/ws` and an atDirectory's `/@alice`, over TLS on a loopback
/// port. With no message it binds 127.0.0.1 and serves the certificate in
/// [certsDirVariable]; with the message `'ipv6'` it binds `::1` and serves
/// the one in [ipv6CertsDirVariable].
///
/// Sends its port, answers every frame on `/ws` with `data:ok`, answers
/// `GET /@alice` with [aliceAddress] to any origin, and answers any message
/// on [channel] with what it received so far: each frame, and
/// `GET <path>` for each atDirectory request. When its variable is not set
/// it binds nothing and sends, instead of a port, the reason to skip, naming
/// the variable.
void hybridMain(StreamChannel channel, Object? message) async {
  final ipv6 = message == 'ipv6';
  final variable = ipv6 ? ipv6CertsDirVariable : certsDirVariable;
  final certs = Platform.environment[variable];
  if (certs == null || certs.isEmpty) {
    channel.sink.add(ipv6
        ? '$variable is not set: point it at a folder holding a fullchain.pem '
            'and privkey.pem for IP ::1 that the browser trusts'
        : '$variable is not set: point it at an at_server '
            "checkout's tools/build_virtual_environment/ve_base/contents/"
            'atsign/secondary/base/certs');
    await channel.sink.close();
    return;
  }
  final context = SecurityContext()
    ..useCertificateChain('$certs/fullchain.pem')
    ..usePrivateKey('$certs/privkey.pem');
  final server = await HttpServer.bindSecure(
      ipv6 ? InternetAddress.loopbackIPv6 : InternetAddress.loopbackIPv4,
      0,
      context);
  final received = <String>[];
  channel.stream.listen((_) => channel.sink.add(List.of(received)),
      onDone: () => server.close(force: true));
  channel.sink.add(server.port);

  await for (final request in server) {
    if (request.uri.path == '/@alice') {
      received.add('GET ${request.uri.path}');
      request.response
        ..headers.set('access-control-allow-origin', '*')
        ..write(aliceAddress);
      await request.response.close();
      continue;
    }
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
