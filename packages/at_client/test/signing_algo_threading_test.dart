import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show CryptographicMaterialAlgorithm;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/fake_at_server.dart' show FakeAtServerSocket;
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
          lookUps: secureSocketLookUps(),
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
      // NOTE: pinned in the source, since a site that built a
      // RemoteSecondary by hand would skip the wiring buildRemoteSecondary
      // gives every connection, and only an ML-DSA atSign would notice.
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
    /// The monitor's connection is built by `NotificationServiceImpl` through
    /// the client's `lookUps`, and authenticates on the wire of the atServer
    /// below when the service starts listening.
    test(
        'the monitor connection authenticates as the client\'s enrollment, '
        'signing with the keys it holds', () async {
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
      final client = MockAtClient();
      client.getPreferences()
        ..namespace = 'wavi'
        ..monitorAutoStart = false
        ..fetchOfflineNotifications = false
        ..monitorHeartbeatInterval = const Duration(hours: 1);
      when(() => client.getCurrentAtSign()).thenReturn(atSign);
      when(() => client.atSign).thenReturn(atSign.toAtsign());
      when(() => client.enrollmentId).thenReturn(enrollmentId);
      when(() => client.atKeysIo)
          .thenReturn(InMemoryAtKeysIo.holding(atSign, keys));
      final server = _MonitorAtServer(atSign: atSign, challenge: challenge);
      final service = await NotificationServiceImpl.create(client,
              lookUps: server.lookUps,
              secondaryAddressFinder: server.addressFinder)
          as NotificationServiceImpl;
      addTearDown(service.stop);

      service.startListening();
      await server.authenticated.future;

      expect(server.froms, [startsWith('from:$atSign')],
          reason: 'the control: the monitor connection reached this atServer '
              'and began its handshake, so what its pkam: says is about the '
              'monitor');
      expect(server.pkams, [contains(':enrollmentId:$enrollmentId:')],
          reason: 'the monitor connection authenticates as the client\'s own '
              'enrollment');
      expect(server.pkams, [startsWith('pkam:signingAlgo:mldsa65:')],
          reason: 'with the algorithm the client\'s keys name');
      final pkam = server.pkams.single;
      expect(
          MlDsa65PureDartAlgo.verifyBytesSync(
              Uint8List.fromList(utf8.encode(challenge)),
              signature: base64Decode(
                  pkam.substring(pkam.lastIndexOf(':') + 1).trim()),
              publicKey: base64Decode(pqPair.atPublicKey.publicKey)),
          isTrue,
          reason:
              'signed with the enrollment\'s private in the client\'s keys');
      expect(
          service.monitor.lookUp.connection
              ?.getMetaData()
              ?.authenticatedAsEnrollmentId,
          enrollmentId,
          reason: 'and the monitor\'s connection records that enrollment');
    });
  });
}

/// An atServer that answers `from:` with [challenge] and `pkam:` with
/// success, and keeps every `from:` and `pkam:` sent to it.
///
/// [lookUps] builds a real lookup over it, running the authenticator the
/// caller hands in; [authenticated] completes when that first finishes,
/// whether it succeeded or threw, or at once when the caller hands none.
class _MonitorAtServer implements AtTransportFactory {
  _MonitorAtServer({required this.atSign, required this.challenge});

  final String atSign;
  final String challenge;

  final List<String> froms = [];
  final List<String> pkams = [];
  final Completer<void> authenticated = Completer<void>();
  final SecondaryAddressFinder addressFinder = _FixedAddress();

  AtLookUpFactory get lookUps => ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
      }) {
        if (authenticator == null && !authenticated.isCompleted) {
          authenticated.complete();
        }
        return AtLookUp.withSecureSocket(
          atSign: atSign,
          rootDomain: rootDomain,
          authenticator: authenticator == null
              ? null
              : (executor) async {
                  try {
                    return await authenticator(executor);
                  } finally {
                    if (!authenticated.isCompleted) authenticated.complete();
                  }
                },
          secondaryAddressFinder: addressFinder,
          transport: AtLookupTransport(transportFactory: this),
        );
      };

  @override
  Future<AtTransport> connect(String host, String port,
          {Duration? timeout}) async =>
      FakeAtServerSocket(_answer);

  void _answer(FakeAtServerSocket socket, String command) {
    if (command.startsWith('monitor:')) return;
    if (command.startsWith('from:')) froms.add(command.trim());
    if (command.startsWith('pkam:')) pkams.add(command.trim());
    final reply = command.startsWith('from:')
        ? 'data:$challenge\n@'
        : command.startsWith('pkam:')
            ? 'data:success\n$atSign@'
            : 'data:ok\n$atSign@';
    unawaited(socket.serverSends(reply));
  }
}

class _FixedAddress extends SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
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
