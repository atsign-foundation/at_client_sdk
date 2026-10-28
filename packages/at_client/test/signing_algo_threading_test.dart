import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show CryptographicMaterialAlgorithm;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// Every connection the client owns authenticates from its keys, which name
/// the algorithm, as its own enrollment. A self-retrofit's ML-DSA enrollment
/// re-authenticates on every reconnect — verb, monitor and sync alike — so a
/// connection signing with anything else fails against the
/// record-authoritative atServer.
void main() {
  group('RemoteSecondary', () {
    test('signs with the algorithm its keys name, whatever it is told',
        () async {
      const atSign = '@threading';
      const enrollmentId = 'pq-enrollment';
      const challenge = '_9e8169dc-5618-44ec-ab43-1a5b2144c581$atSign'
          ':c3d345fc-5691-4f90-bc34-17cba31f060f';
      final pqPair = await MlDsa65KeyPair.generate();
      final keys = AtKeys(atsign: atSign.toAtsign())
        ..fileApkamMaterial(
            enrollmentId: enrollmentId,
            algorithm: CryptographicMaterialAlgorithm.mlDsa65,
            publicKey: pqPair.atPublicKey.publicKey,
            privateKey: pqPair.atPrivateKey.privateKey);
      final lookUp = MockAtLookupImpl();
      RemoteSecondary(
          atSign,
          AtClientPreference()
            // ignore: deprecated_member_use_from_same_package
            ..signingAlgoType = SigningAlgoType.rsa2048,
          atLookUp: lookUp,
          atKeysIo: InMemoryAtKeysIo.holding(atSign, keys),
          enrollmentId: enrollmentId,
          // ignore: deprecated_member_use_from_same_package
          signingAlgoType: SigningAlgoType.rsa2048);
      final authenticate = verify(() => lookUp.authenticator = captureAny())
          .captured
          .last as AtAuthenticator;
      final executor = _RecordingExecutor(['data:$challenge', 'data:success']);

      expect(await authenticate(executor), isTrue);

      final pkam = executor.sent.last;
      expect(pkam, startsWith('pkam:signingAlgo:mldsa65:'),
          reason: 'the preference and the parameter both said rsa2048; the '
              'keys name ML-DSA, and only the keys can sign');
      expect(pkam, contains(':enrollmentId:$enrollmentId:'));
      expect(
          MlDsa65PureDartAlgo.verifyBytesSync(
              Uint8List.fromList(utf8.encode(challenge)),
              signature: base64Decode(
                  pkam.substring(pkam.lastIndexOf(':') + 1).trim()),
              publicKey: base64Decode(pqPair.atPublicKey.publicKey)),
          isTrue);
    });
  });

  group('AtClientImpl.buildRemoteSecondary', () {
    /// Asserted against the source: the forward is a plain pass-through with
    /// no branch or default to exercise live, and RemoteSecondary's own
    /// resolution of what it's handed is the 'RemoteSecondary' group above.
    test(
        'threads the client\'s enrollment id and keys into the connection it '
        'builds', () {
      final source =
          File('lib/src/client/at_client_impl.dart').readAsStringSync();
      final wiring = source
          .substring(source.indexOf('RemoteSecondary buildRemoteSecondary('));

      expect(wiring, contains('enrollmentId: enrollmentId'),
          reason: 'so the seam authenticates as this client\'s own '
              'enrollment, not the primary one');
      expect(wiring, contains('atKeysIo: _atKeysIo'),
          reason: 'so a connection opened for an ML-DSA enrollment signs '
              'with the ML-DSA keypair its keys hold');
    });

    test('is the only way this class opens a connection', () {
      // NOTE: `stream()` opens a connection of its own and cannot be driven
      // from a unit test — it needs a file on disk and a real socket — so what
      // is pinned instead is that no site in the class builds one by hand. A
      // hand-rolled site fails here rather than at an ML-DSA atSign's first
      // file transfer.
      final source =
          File('lib/src/client/at_client_impl.dart').readAsStringSync();
      final constructions =
          RegExp(r'(?<![A-Za-z_])RemoteSecondary\(').allMatches(source);

      expect(constructions, hasLength(1),
          reason: 'the one permitted construction is inside '
              'buildRemoteSecondary; every other site calls it');
      final only = source.substring(0, constructions.single.start);
      expect(only, contains('RemoteSecondary buildRemoteSecondary('),
          reason: 'the surviving construction must be the builder itself, not '
              'a hand-rolled site that happens to be the last one left');
    });
  });

  group('Monitor', () {
    /// Monitor holds an `AtLookupMuxable` rather than a signing algorithm, and
    /// the keys travel inside the authenticator `NotificationServiceImpl`
    /// builds for it.
    ///
    /// Asserted against the source because the keys are captured in a
    /// closure, with nothing on the built object to read them back from.
    test('the monitor connection authenticates from the client\'s keys', () {
      final source = File('lib/src/service/notification_service_impl.dart')
          .readAsStringSync();
      final wiring = source.substring(source.indexOf('lookUp: lookUps('));

      expect(wiring, contains('authenticator: clientAuthenticator(atSign,'),
          reason: 'the one builder every connection of the client uses');
      expect(wiring, contains('atKeysIo: atClient.atKeysIo'),
          reason: 'the keys name the algorithm the monitor signs with');
      expect(wiring,
          contains('privateKey: pkamPrivateKeyWithoutKeyfile(atClient)'),
          reason: 'and a client with no keyfile signs with the key its local '
              'store or preference holds');
      expect(wiring, contains('enrollmentId: atClient.enrollmentId'),
          reason: 'and as the right enrollment, or the atServer refuses it');
    });
  });
}

/// Answers each command with the next of [replies] and records what was sent.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];
  final List<String> replies;

  _RecordingExecutor(this.replies);

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return replies.removeAt(0);
  }
}
