import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp, AtLookUpException;
import 'package:test/test.dart';

import '../test_utils/fake_at_server.dart';
import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/reopened_client.dart';
import '../test_utils/test_keypairs.dart';

/// Catalogue: features/at_client/pkam_no_challenge.feature
void main() {
  const atSign = '@alice🛠';
  final keys = keysHoldingApkam(atSign, null, pkamKeyPairFor(atSign, null));

  /// The client's refusal of an answer that holds no challenge it will sign.
  final refusedToSign = isA<UnAuthenticatedException>().having((e) => e.message,
      'message', startsWith('Refusing to sign a malformed from: challenge'));

  /// at_lookup's refusal of an authenticator that found nothing to sign.
  final nothingToSign = isA<UnAuthenticatedException>().having(
      (e) => e.message,
      'message',
      'Failed connecting to $atSign. The authenticator reported failure');

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
      'A from: answer with no challenge to sign leaves the connection '
      'offline', () {
    // NOTE: the reply listener drops an empty line, so an answer of nothing
    // leaves the read waiting until the attempt's budget is spent.
    final answers = {
      'nothing': ('', isA<TimeoutException>()),
      'data: and nothing else': ('data:', refusedToSign),
      'a bare @alice🛠@ prompt': ('@alice🛠@', refusedToSign),
      'a malformed challenge': (
        'data:_9e8169dc-5618-44ec-ab43-1a5b2144c581@alice🛠:not-a-uuid',
        refusedToSign
      ),
      'a challenge issued for @bob🛠': (
        'data:_9e8169dc-5618-44ec-ab43-1a5b2144c581@bob🛠'
            ':c3d345fc-5691-4f90-bc34-17cba31f060f',
        refusedToSign
      ),
    };
    answers.forEach((row, answer) {
      final (reply, error) = answer;
      test(row, () async {
        final server =
            FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
        final storage = await storeOnceOnline(server, atSign, keys);
        final signedBefore = pkamsSent(server);
        server.answerClientFrom = () => reply;

        final client = await openOn(server, atSign, keys, storage,
            connectBudget: const Duration(milliseconds: 500));

        expect(pkamsSent(server), signedBefore, reason: 'nothing was signed');
        final state = client.connection.current;
        expect(state.isOffline, isTrue, reason: '$state');
        expect(state.cause, AtConnectionCause.unreachable);
        expect(state.error, error);
      });
    });
  });

  test('A first open whose from: gets no challenge hands back its client',
      () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true)
      ..answerClientFrom = () => 'data:';

    final client = await openOn(
        server, atSign, keys, InMemoryAtClientStorage(atSign: atSign));

    final state = client.connection.current;
    expect(state.isOffline, isTrue, reason: '$state');
    expect(state.cause, AtConnectionCause.unreachable);
    expect(await (client as AtClientImpl).hasBeenOnline(), isFalse,
        reason: 'the control: this device has never held the atSign online');
  });

  test(
      'Checking which enrollment keys authenticate as throws a missing '
      'challenge as it is', () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true)
      ..answerClientFrom = () => 'data:';

    await expectLater(
        Atsign(atSign).authenticatesAs(
            keys: keys,
            rootDomain: const AtRootDomain('127.0.0.1', 64),
            lookUps: server.lookUps,
            secondaryAddressFinder: server.addressFinder),
        throwsA(allOf(
          refusedToSign,
          isNot(isA<AtCredentialRefusedException>()),
        )));
  });

  test('A verb whose from: gets no challenge reports the connection offline',
      () async {
    final server = FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
    final (:remote, :connection) = remoteReportingOn(server, atSign, keys);
    addTearDown(remote.closeConnection);
    expect(await remote.executeVerb(llookupOf(atSign)), 'data:ok');
    expect(connection.current.isOnline, isTrue,
        reason: 'the control: a verb that is answered reports online');

    server.answerClientFrom = () => 'data:';
    await server.drop();
    await expectLater(
        remote.executeVerb(llookupOf(atSign)),
        throwsA(isA<AtException>().having((e) => e.message, 'message',
            contains('Refusing to sign a malformed from: challenge'))));

    expect(server.connectCount, 2,
        reason: 'the second verb asked a new connection for a challenge');
    expect(connection.current.isOffline, isTrue,
        reason: '${connection.current}');
    expect(connection.current.cause, AtConnectionCause.unreachable);
  });

  group('Given an authenticator that finds nothing to sign', () {
    AtLookUp lookUpOn(FakeAtServer server) {
      final lookUp = server.lookUps(
          atSign: atSign,
          rootDomain: const AtRootDomain('127.0.0.1', 64),
          authenticator: (_) async => false);
      addTearDown(lookUp.close);
      return lookUp;
    }

    test(
        'when a connection authenticates with it, then the failure is '
        'classified offline, unreachable', () async {
      final server =
          FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
      Object? failure;
      try {
        await lookUpOn(server).pkamAuthenticate();
      } catch (e) {
        failure = e;
      }

      expect(failure, nothingToSign);
      final state = classifyConnectionFailure(failure!);
      expect(state?.isOffline, isTrue, reason: '$state');
      expect(state?.cause, AtConnectionCause.unreachable);
    });

    test(
        'when a verb authenticates its connection with it, then the failure '
        'is classified offline, unreachable', () async {
      final server =
          FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
      Object? failure;
      try {
        await lookUpOn(server).executeVerb(llookupOf(atSign));
      } catch (e) {
        failure = e;
      }

      expect(failure, isA<AtLookUpException>());
      final state = classifyConnectionFailure(failure!);
      expect(state?.isOffline, isTrue, reason: '$state');
      expect(state?.cause, AtConnectionCause.unreachable);
    });
  });

  group('Given a refusal whose text quotes a refusal to sign a challenge', () {
    test('when it is classified, then it is read by its code', () {
      final failure = UnAuthenticatedException(
          'Failed connecting to $atSign. error:AT0027:Refusing to sign a '
          'malformed from: challenge for $atSign');

      final state = classifyConnectionFailure(failure);

      expect(state?.isRefused, isTrue, reason: '$state');
      expect(state?.cause, AtConnectionCause.revoked);
    });
  });

  group('Given an atServer that answers from: with an error: reply', () {
    test(
        'when it names AT0011 in the JSON form, then the connection is '
        'offline carrying it, and nothing is signed', () async {
      const reply = 'error:{"errorCode":"AT0011",'
          '"errorDescription":"Internal server exception"}';
      final server =
          FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
      final storage = await storeOnceOnline(server, atSign, keys);
      final signedBefore = pkamsSent(server);
      server.answerClientFrom = () => reply;

      final client = await openOn(server, atSign, keys, storage);

      expect(pkamsSent(server), signedBefore, reason: 'nothing was signed');
      final state = client.connection.current;
      expect(state.isOffline, isTrue, reason: '$state');
      expect(state.cause, AtConnectionCause.unreachable);
      expect(
          state.error,
          isA<UnAuthenticatedException>().having((e) => e.message, 'message',
              'Failed connecting to $atSign. $reply'));
    });

    test('when it names AT0027, then the connection is refused as revoked',
        () async {
      final server =
          FakeAtServer(atSign: atSign, runsClientAuthenticator: true);
      final storage = await storeOnceOnline(server, atSign, keys);
      server.answerClientFrom = () => 'error:AT0027:Apkam Access Revoked';

      final client = await openOn(server, atSign, keys, storage);

      final state = client.connection.current;
      expect(state.isRefused, isTrue, reason: '$state');
      expect(state.cause, AtConnectionCause.revoked);
    });
  });
}
