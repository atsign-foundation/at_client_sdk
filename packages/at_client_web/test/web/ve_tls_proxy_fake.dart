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

/// The session id and the proof the fake's `from:` challenge carries: any
/// lowercase RFC-4122 value, since the client checks the shape and not the
/// value.
const challengeUuid = '00000000-0000-4000-8000-000000000000';

/// The `from:` challenge the fake issues to [atSign]: `_<uuid><atSign>:<uuid>`
/// with [challengeUuid] in both places, as an atServer mints one.
String fromChallenge(String atSign) => '_$challengeUuid$atSign:$challengeUuid';

/// The atSign a `from:` frame names, whether or not it carries client config:
/// `from:@alice\n` and `from:@alice:clientConfig:{...}\n` both give `@alice`.
String atSignOf(String frame) =>
    frame.substring('from:'.length).split(RegExp('[:\\n]')).first;

/// A proxy's `/ws` and an atDirectory's `/@alice`, over TLS on a loopback
/// port. With no message it binds 127.0.0.1 and serves the certificate in
/// [certsDirVariable]; with the message `'drop-first-upgrade'` it does the
/// same but closes the first WebSocket upgrade before answering, then serves
/// the next; with the message `'ipv6'` it binds `::1` and serves the one in
/// [ipv6CertsDirVariable].
///
/// Sends its port, answers a frame on `/ws` starting with `from:` with the
/// challenge [fromChallenge] issues to the atSign the frame names, one
/// starting with `pkam:` with `data:success` whatever signature it carries,
/// and every other one with `data:ok`; it answers
/// `GET /@alice` with [aliceAddress] to any origin, and answers any message
/// on [channel] with what it received so far: each frame, and
/// `GET <path>` for each atDirectory request. A dropped upgrade is recorded
/// as `DROP <path>` so a test can tell it happened. When [certsDirVariable]
/// is not set it throws, naming it, so the test fails rather than passing
/// unrun; when [ipv6CertsDirVariable] is not set it binds nothing and sends,
/// instead of a port, the reason to skip, naming the variable.
void hybridMain(StreamChannel channel, Object? message) async {
  final ipv6 = message == 'ipv6';
  final dropFirstUpgrade = message == 'drop-first-upgrade';
  final variable = ipv6 ? ipv6CertsDirVariable : certsDirVariable;
  final certs = Platform.environment[variable];
  if (certs == null || certs.isEmpty) {
    if (!ipv6) {
      throw StateError('$variable is not set: point it at an at_server '
          "checkout's tools/build_virtual_environment/ve_base/contents/atsign/"
          'secondary/base/certs');
    }
    channel.sink.add('$variable is not set: point it at a folder holding a '
        'fullchain.pem and privkey.pem for IP ::1 that the browser trusts');
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
  var upgrades = 0;
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
    if (dropFirstUpgrade && upgrades++ == 0) {
      // Close the connection without an HTTP answer, so the browser's socket
      // errors before it opens, as a refused upgrade does.
      received.add('DROP ${request.uri.path}');
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.destroy();
      continue;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((message) {
      final frame =
          message is String ? message : utf8.decode(message as List<int>);
      received.add(frame);
      socket.add(switch (frame) {
        _ when frame.startsWith('from:') =>
          'data:${fromChallenge(atSignOf(frame))}\n@',
        _ when frame.startsWith('pkam:') => 'data:success\n@',
        _ when frame.startsWith('stats:') =>
          'data:[{"id":"3","name":"lastCommitID","value":"-1"}]\n@',
        _ => 'data:ok\n@',
      });
    });
  }
}
