import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/mocks.dart';

/// The per-enrollment signing algorithm must reach every connection the
/// client owns. A self-retrofit's ML-DSA enrollment re-authenticates on
/// every reconnect — verb, monitor and sync alike — so a connection stamped
/// with the preference's rsa2048 default fails against the
/// record-authoritative atServer no matter how correct its AtChops are.
void main() {
  final preference = AtClientPreference()..namespace = 'unit';

  group('RemoteSecondary', () {
    test('threads a resolved signingAlgoType onto the AtLookUp', () {
      final lookUp = MockAtLookUp();
      RemoteSecondary('@alice', preference,
          atLookUp: lookUp,
          enrollmentId: 'pq-1',
          signingAlgoType: SigningAlgoType.mldsa65);

      verify(() => lookUp.signingAlgoType = SigningAlgoType.mldsa65).called(1);
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048);
    });

    test('defaults to the preference when no resolution is supplied', () {
      final lookUp = MockAtLookUp();
      RemoteSecondary('@alice', preference, atLookUp: lookUp);

      verify(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048).called(1);
    });
  });

  group('AtClientImpl.buildRemoteSecondary', () {
    /// A client whose enrollment holds typed ML-DSA authentication material,
    /// so the algorithm under test is one the client resolved rather than one
    /// the test handed it.
    Future<AtClientImpl> pqClient(String atSign, String enrollmentId) async {
      AtClientImpl.atClientInstanceMap
          .remove(AtClientImpl.instanceKey(atSign, enrollmentId));
      return await AtClientImpl.create(
        atSign,
        'unit',
        AtClientPreference()
          ..hiveStoragePath = 'test/hive'
          ..commitLogPath = 'test/hive/path',
        remoteSecondary: MockRemoteSecondary(),
        atKeysIo: await mlDsaKeyfile(atSign, enrollmentId),
        enrollmentId: enrollmentId,
      ) as AtClientImpl;
    }

    test('stamps the resolved algorithm and enrollment id on the connection',
        () async {
      const atSign = '@threading_1';
      const enrollmentId = 'pq-threading-1';
      final client = await pqClient(atSign, enrollmentId);
      // Read back rather than assumed: if the resolution had not happened this
      // test would pin the preference default and prove nothing.
      expect(client.signingAlgoType, SigningAlgoType.mldsa65,
          reason: 'the rig must supply a resolved ML-DSA client, or the '
              'assertions below compare rsa2048 with rsa2048');

      final lookUp = MockAtLookUp();
      client.buildRemoteSecondary(atLookUp: lookUp);

      verify(() => lookUp.signingAlgoType = SigningAlgoType.mldsa65).called(1);
      verify(() => lookUp.enrollmentId = enrollmentId).called(1);
      verifyNever(() => lookUp.signingAlgoType = SigningAlgoType.rsa2048);
      verifyNever(() => lookUp.enrollmentId = null);
    });

    test('is the only way this class opens a connection', () {
      // `stream()` opens a connection of its own — separate from the client's,
      // because it hands the socket raw bytes and closes it — and used to
      // build it by hand, carrying neither the enrollment id nor the resolved
      // algorithm. It cannot be driven from a unit test (it is deprecated,
      // needs a file on disk and a real socket), so what is pinned instead is
      // that no site in the class builds one by hand any more: a fourth site
      // added the old way fails here rather than at an ML-DSA atSign's first
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
    Monitor buildMonitor({SigningAlgoType? signingAlgoType}) => Monitor(
        atSign: '@alice',
        atClientPreference: preference,
        atChops: null,
        enrollmentId: 'pq-1',
        secondaryAddressFinder: MockSecondaryAddressFinder(),
        handleNotification: (_) async {},
        getLastNotificationTime: () async => null,
        signingAlgoType: signingAlgoType);

    test('carries a resolved signingAlgoType for its own re-authentication',
        () {
      expect(buildMonitor(signingAlgoType: SigningAlgoType.mldsa65)
          .signingAlgoType, SigningAlgoType.mldsa65);
    });

    test('defaults to the preference', () {
      expect(buildMonitor().signingAlgoType, SigningAlgoType.rsa2048);
    });
  });
}
