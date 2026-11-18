import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:test/test.dart';

import '../test_utils/fake_at_server.dart';
import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/reopened_client.dart';
import '../test_utils/test_keypairs.dart';

/// Catalogue: features/at_client/pkam_server_error.feature
void main() {
  const atSign = '@alice🛠';
  final keys = keysHoldingApkam(atSign, null, pkamKeyPairFor(atSign, null));

  /// AT0011 as an atServer writes it in each form.
  const serverError = {
    'dash': 'error:AT0011-Internal server exception',
    'colon': 'error:AT0011:Internal server exception',
    'JSON': 'error:{"errorCode":"AT0011",'
        '"errorDescription":"Internal server exception"}',
  };

  Matcher carrying(String reply) => isA<UnAuthenticatedException>()
      .having((e) => e.message, 'message', endsWith(reply));

  int pkamsSent(FakeAtServer server) => server.sockets
      .expand((socket) => socket.written)
      .where((command) => command.startsWith('pkam:'))
      .length;

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  group(
      'A server error in reply to a connection\'s PKAM leaves it offline, '
      'not refused', () {
    serverError.forEach((form, reply) {
      test(form, () async {
        final server =
            FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
        final storage = await storeOnceOnline(server, atSign, keys);
        server.refuseClientAuth = (_) => reply;

        final client = await openOn(server, atSign, keys, storage);

        final state = client.connection.current;
        expect(state.isOffline, isTrue, reason: '$state');
        expect(state.error, carrying(reply));
      });
    });
  });

  test('A first open whose PKAM gets a server error hands back its client',
      () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true)
      ..refuseClientAuth = (_) => serverError['dash'];

    final client = await openOn(
        server, atSign, keys, InMemoryAtClientStorage(atSign: atSign));

    final state = client.connection.current;
    expect(state.isOffline, isTrue, reason: '$state');
    expect(state.error, carrying(serverError['dash']!));
    expect(await (client as AtClientImpl).hasBeenOnline(), isFalse,
        reason: 'the control: this device has never held the atSign online');
  });

  test(
      'Checking which enrollment keys authenticate as throws a server error '
      'as it is', () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true)
      ..refuseClientAuth = (_) => serverError['dash'];

    await expectLater(
        Atsign(atSign).authenticatesAs(
            keys: keys,
            rootDomain: const AtRootDomain('127.0.0.1', 64),
            lookUps: server.lookUps,
            secondaryAddressFinder: server.addressFinder),
        throwsA(allOf(
          carrying(serverError['dash']!),
          isNot(isA<AtCredentialRefusedException>()),
        )));
  });

  test(
      'A verb whose PKAM gets a server error leaves the connection state as '
      'it was', () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
    final (:remote, :connection) = remoteReportingOn(server, atSign, keys);
    addTearDown(remote.closeConnection);
    expect(await remote.executeVerb(llookupOf(atSign)), 'data:ok');
    expect(connection.current.isOnline, isTrue,
        reason: 'the control: a verb that is answered reports online');

    server.refuseClientAuth = (_) => serverError['dash'];
    await server.drop();
    await expectLater(
        remote.executeVerb(llookupOf(atSign)), throwsA(isA<AtException>()));

    expect(pkamsSent(server), 2,
        reason: 'the second verb authenticated a new connection');
    expect(connection.current.isOnline, isTrue,
        reason: '${connection.current}');
  });

  group('A refusal code in reply to a PKAM still refuses', () {
    final rows = {
      'AT0401': (
        'error:AT0401-Exception: pkam authentication failed',
        AtConnectionCause.unauthenticated
      ),
      'AT0025': (
        'error:AT0025:enrollment_id: e-1 is denied',
        AtConnectionCause.enrollmentDenied
      ),
      'AT0026': (
        'error:AT0026:enrollment_id: e-1 is pending',
        AtConnectionCause.enrollmentNotApproved
      ),
      'AT0027': (
        'error:AT0027:Apkam Access Revoked',
        AtConnectionCause.revoked
      ),
      'AT0028': (
        'error:AT0028:enrollment_id: e-1 is expired or invalid',
        AtConnectionCause.invalidEnrollment
      ),
      'AT0029': (
        'error:AT0029:enrollment_id: e-1 is expired or invalid',
        AtConnectionCause.invalidEnrollment
      ),
      'no code': (
        'error:Exception: pkam authentication failed',
        AtConnectionCause.unauthenticated
      ),
    };
    rows.forEach((code, row) {
      final (reply, cause) = row;
      test('$code, ${cause.name}', () async {
        final server =
            FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
        final storage = await storeOnceOnline(server, atSign, keys);
        server.refuseClientAuth = (_) => reply;

        final client = await openOn(server, atSign, keys, storage);

        final state = client.connection.current;
        expect(state.isRefused, isTrue, reason: '$state');
        expect(state.cause, cause);
        expect(state.error, carrying(reply));
      });
    });
  });
}
