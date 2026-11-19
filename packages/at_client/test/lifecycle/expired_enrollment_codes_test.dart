import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

import '../test_utils/fake_at_server.dart';
import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/reopened_client.dart';
import '../test_utils/test_keypairs.dart';

/// Catalogue: features/enrollment/expired_enrollment_codes.feature
void main() {
  const atSign = '@alice🛠';
  const enrollmentId = '9821c174-cd2a-4a96-b3a9-ea4eb8e13db9';
  final keys = keysHoldingApkam(
      atSign, enrollmentId, pkamKeyPairFor(atSign, enrollmentId));

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  group(
      'A running client whose enrollment expired reports it as '
      'invalidEnrollment', () {
    for (final code in ['AT0028', 'AT0029']) {
      test(code, () async {
        final server =
            FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
        final storage = await storeOnceOnline(server, atSign, keys);
        final reply =
            'error:$code:enrollment_id: $enrollmentId is expired or invalid';
        server.refuseClientAuth = (_) => reply;

        final client = await openOn(server, atSign, keys, storage);

        final state = client.connection.current;
        expect(state.isRefused, isTrue, reason: '$state');
        expect(state.cause, AtConnectionCause.invalidEnrollment);
        expect(
            state.error,
            isA<UnAuthenticatedException>()
                .having((e) => e.message, 'message', endsWith(reply)));
      });
    }
  });

  test('An AT0028 reply to a verb leaves the connection online', () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
    var throttled = false;
    server.answerVerb = (command) => throttled && command.startsWith('llookup:')
        ? 'error:AT0028:Too many requests, try after some time'
        : null;
    final (:remote, :connection) =
        remoteReportingOn(server, atSign, keys, enrollmentId: enrollmentId);
    addTearDown(remote.closeConnection);
    expect(await remote.executeVerb(llookupOf(atSign)), 'data:ok');
    expect(connection.current.isOnline, isTrue,
        reason: 'the control: a verb that is answered reports online');

    throttled = true;
    await expectLater(remote.executeVerb(llookupOf(atSign)),
        throwsA(isA<AtThrottleLimitExceeded>()),
        reason: 'at_commons reads AT0028 in reply to a verb as a throttle');

    expect(connection.current.isOnline, isTrue,
        reason: '${connection.current}');
  });
}
