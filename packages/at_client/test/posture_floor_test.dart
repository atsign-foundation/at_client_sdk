import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        CryptographicMaterial,
        CryptographicMaterialAlgorithm,
        CryptographicMaterialRole,
        EnrollmentKeyExchangeMode,
        InMemoryAtKeysIo;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/pq_client_bootstrap.dart'
    show PqStartupGates;
import 'package:at_client/src/preference/at_client_particulars.dart'
    show AtClientParticulars;
import 'package:at_client/src/preference/posture_floor.dart';
import 'package:test/test.dart';

import 'test_utils/declared_fields.dart';

/// The posture floor's pieces: what raises a posture and a preference to a
/// floor stage, and what sets the floor.
///
/// Catalogue: features/at_client/posture_floor.feature
void main() {
  const atSign = '@alice';

  group('PqPosture.raisedTo', () {
    test(
        'raises legacy to pqReady on every setting the floor raises, and '
        'nothing else', () {
      final raised = PqPosture.legacy.raisedTo(PqPosture.pqReady);
      expect(raised.authenticationKeyAlgorithm, SigningAlgoType.mldsa65);
      expect(raised.dataSigningKeyAlgorithms, {SigningAlgoType.rsa2048});
      expect(raised.configuresPqProviders, isTrue);
      expect(raised.writesPqByDefault, isFalse,
          reason: 'pqReady writes legacy, so the floor raises nothing here');
      expect(raised.seedNamespaceKeys, isFalse,
          reason: 'the floor never raises seeding');
      expect(raised.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
      expect(raised.disallowLegacyEncryption, isFalse);
      expect(raised.mintLegacyMaterial, isTrue);
    });

    test(
        'raises pqReady to pqActive on the data signing set and writes, and '
        'leaves disallowLegacyEncryption as configured', () {
      final raised = PqPosture.pqReady.raisedTo(PqPosture.pqActive);
      expect(raised.dataSigningKeyAlgorithms, {SigningAlgoType.mldsa65});
      expect(raised.writesPqByDefault, isTrue);
      expect(raised.disallowLegacyEncryption, isFalse,
          reason: 'not a setting the floor raises: a pqReady client at a '
              'pqActive floor still writes legacy where the app allows it');
    });

    test('keeps a custom posture\'s other settings', () {
      final custom = PqPosture.legacy.copyWith(mintLegacyMaterial: false);
      final raised = custom.raisedTo(PqPosture.pqReady);
      expect(raised.authenticationKeyAlgorithm, SigningAlgoType.mldsa65);
      expect(raised.configuresPqProviders, isTrue);
      expect(raised.mintLegacyMaterial, isFalse);
    });

    test('returns a posture at or above the floor unchanged', () {
      for (final (posture, floor) in [
        (PqPosture.pqReady, PqPosture.pqReady),
        (PqPosture.pqActive, PqPosture.pqReady),
        (PqPosture.pqActive, PqPosture.pqActive),
      ]) {
        expect(posture.raisedTo(floor), same(posture));
      }
    });
  });

  /// Each field AtClientPreference declares, read through its getter.
  final fields = <String, Object? Function(AtClientPreference)>{
    'disallowLegacyEncryption': (p) => p.disallowLegacyEncryption,
    'posture': (p) => p.posture,
    'pqStartupGates': (p) => p.pqStartupGates,
    'dataSigningKeyAlgorithms': (p) => p.dataSigningKeyAlgorithms,
    'authenticationKeyAlgorithm': (p) => p.authenticationKeyAlgorithm,
    'sealsToKeyAlgorithms': (p) => p.sealsToKeyAlgorithms,
    // ignore: deprecated_member_use
    'hiveStoragePath': (p) => p.hiveStoragePath,
    'cramSecret': (p) => p.cramSecret,
    'namespace': (p) => p.namespace,
    'rootDomain': (p) => p.rootDomain,
    'rootPort': (p) => p.rootPort,
    'networkTimeout': (p) => p.networkTimeout,
    'maxDataSize': (p) => p.maxDataSize,
    'syncRegex': (p) => p.syncRegex,
    'syncBatchSize': (p) => p.syncBatchSize,
    'syncPageLimit': (p) => p.syncPageLimit,
    'fileEncryptionChunkSize': (p) => p.fileEncryptionChunkSize,
    'monitorHeartbeatInterval': (p) => p.monitorHeartbeatInterval,
    'monitorHeartbeatResponseTimeout': (p) => p.monitorHeartbeatResponseTimeout,
    'monitorSilenceTimeout': (p) => p.monitorSilenceTimeout,
    'monitorAutoStart': (p) => p.monitorAutoStart,
    'expiryCheckTimeInterval': (p) => p.expiryCheckTimeInterval,
    'fetchOfflineNotifications': (p) => p.fetchOfflineNotifications,
    'atClientParticulars': (p) => p.atClientParticulars,
    'remoteLocalPref': (p) => p.remoteLocalPref,
    '_crypto': (p) => p.crypto,
    'allowLegacyCryptoFallback': (p) => p.allowLegacyCryptoFallback,
    'seedNamespaceKeys': (p) => p.seedNamespaceKeys,
    'keyEstablishmentAlgorithms': (p) => p.keyEstablishmentAlgorithms,
  };

  /// The fields the floor raises.
  const raisedFields = {
    'posture',
    'authenticationKeyAlgorithm',
    'dataSigningKeyAlgorithms',
  };

  group('AtClientPreference.raisedTo', () {
    test('never raises seedNamespaceKeys, and raises the key exchange', () {
      final configured = AtClientPreference(posture: PqPosture.legacy);
      final raised = configured.raisedTo(PqPosture.pqReady);

      expect(raised.seedNamespaceKeys, isFalse,
          reason: 'a floor does not turn seeding on');
      expect(raised.posture.seedNamespaceKeys, isFalse);
      expect(raised.posture.keyExchangeMode, EnrollmentKeyExchangeMode.pq);
    });

    test('returns the preference itself when nothing is raised', () {
      final preference = AtClientPreference(posture: PqPosture.pqActive);
      expect(preference.raisedTo(PqPosture.pqReady), same(preference));
    });

    test('raises an app\'s own weaker axes with the posture', () {
      final raised = AtClientPreference(
              posture: PqPosture.pqReady,
              dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})
          .raisedTo(PqPosture.pqActive);
      expect(raised.dataSigningKeyAlgorithms, {SigningAlgoType.mldsa65});
      expect(raised.posture.writesPqByDefault, isTrue);
    });

    test('keeps an app\'s seeding and key establishment off its posture\'s',
        () {
      final seedingOff = AtClientPreference(posture: PqPosture.pqReady)
        ..seedNamespaceKeys = false;
      expect(seedingOff.raisedTo(PqPosture.pqActive).seedNamespaceKeys, isFalse,
          reason: 'pqActive seeds, but this app turned seeding off');

      final mlKem = AtClientPreference(
          posture: PqPosture.pqReady,
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024]);
      expect(mlKem.raisedTo(PqPosture.pqActive).keyEstablishmentAlgorithms,
          [SecretSharingAlgos.mlKem1024]);
    });

    test('carries every field the floor does not raise', () {
      // NOTE: every field is set off the value the raised posture would
      // default it to, so a field that is not carried shows as changed.
      final original = AtClientPreference(
          pqStartupGates: const PqStartupGates.inert(),
          sealsToKeyAlgorithms: const [SecretSharingAlgos.xWing],
          keyEstablishmentAlgorithms: const [SecretSharingAlgos.mlKem1024])
        ..seedNamespaceKeys = true
        // ignore: deprecated_member_use_from_same_package
        ..hiveStoragePath = 'h'
        ..cramSecret = 'c'
        ..namespace = 'n.s'
        ..rootDomain = 'r.example'
        ..rootPort = 6464
        ..networkTimeout = const Duration(seconds: 7)
        ..maxDataSize = 99
        ..syncRegex = 'sr'
        ..syncBatchSize = 9
        ..syncPageLimit = 11
        ..fileEncryptionChunkSize = 2048
        ..monitorHeartbeatInterval = const Duration(seconds: 21)
        ..monitorHeartbeatResponseTimeout = const Duration(seconds: 4)
        ..monitorSilenceTimeout = const Duration(seconds: 33)
        ..monitorAutoStart = false
        ..expiryCheckTimeInterval = const Duration(minutes: 3)
        ..fetchOfflineNotifications = false
        ..atClientParticulars = (AtClientParticulars()..appName = 'app')
        ..remoteLocalPref = RemoteLocalPref.remoteOnly
        ..crypto = const CryptoConfig.legacy()
        ..allowLegacyCryptoFallback = true;
      final raised = original.raisedTo(PqPosture.pqReady);
      expect(raised, isNot(same(original)));

      final source = File('lib/src/preference/at_client_preference.dart')
          .readAsStringSync();
      final declared = fieldsDeclaredIn(RegExp(
              r'^class AtClientPreference \{\n(.*?)^\}',
              multiLine: true,
              dotAll: true)
          .firstMatch(source)!
          .group(1)!);
      expect(declared, contains('rootDomain'),
          reason: 'the control: the census finds the preference\'s own fields');
      expect(declared, fields.keys.toSet(),
          reason: 'every declared field is read below, so one added later '
              'is either carried or raised on purpose');
      for (final MapEntry(key: name, value: read) in fields.entries) {
        if (raisedFields.contains(name)) continue;
        expect(read(raised), read(original),
            reason: '$name is carried over unchanged');
      }
    });
  });

  group('the floor key material sets', () {
    AtKeys holding(List<CryptographicMaterial> materials) =>
        AtKeys(atsign: atSign.toAtsign(), keysList: materials);

    CryptographicMaterial material(
            String keyId, String role, CryptographicMaterialAlgorithm algorithm,
            {String? enrollmentId}) =>
        CryptographicMaterial(
          keyId: keyId,
          enrollmentId: enrollmentId,
          role: CryptographicMaterialRole.of(role),
          algorithm: algorithm,
          bytes: AtBytes(Uint8List.fromList(List.filled(32, 7))),
          createdAt: DateTime.utc(2026),
        );

    test('is pqActive for an active ML-DSA-65 client data signing key', () {
      final keys = holding([
        material('sign:mldsa65:1', 'privateSigning',
            CryptographicMaterialAlgorithm.mlDsa65,
            enrollmentId: 'e-1'),
        material('sign:mldsa65:1', 'publicVerification',
            CryptographicMaterialAlgorithm.mlDsa65,
            enrollmentId: 'e-1'),
      ]);
      expect(floorOfKeyMaterial(keys, 'e-1'), same(PqPosture.pqActive));
      expect(floorOfKeyMaterial(keys, 'e-2'), isNull,
          reason: 'another enrollment\'s key sets no floor for this one');
    });

    test('is pqReady for a namespace-key private', () async {
      final io = InMemoryAtKeysIo();
      await io.write(atSign, AtKeys(atsign: atSign.toAtsign()));
      final pair = await XWingKeyPair.generate();
      await NskeyPrivateFiling(keysIo: io, atSign: atSign).store(
          namespace: 'k1.sensor',
          nskeyKid: nskeyKidOf(pair.publicKeyBytes),
          seed: NskeySeed(pair.privateKeyBytes));

      expect(floorOfKeyMaterial(await io.read(atSign), 'e-1'),
          same(PqPosture.pqReady));
    });

    test('is null for an active RSA-2048 client data signing key', () {
      final keys = holding([
        material('sign:rsa2048:1', 'privateSigning',
            CryptographicMaterialAlgorithm.rsa2048,
            enrollmentId: 'e-1'),
        material('sign:rsa2048:1', 'publicVerification',
            CryptographicMaterialAlgorithm.rsa2048,
            enrollmentId: 'e-1'),
      ]);
      expect(floorOfKeyMaterial(keys, 'e-1'), isNull,
          reason: 'only an ML-DSA-65 client data signing key sets pqActive, '
              'and pqReady mints an RSA-2048 one');
    });

    test('is null for a keyfile holding neither', () {
      expect(floorOfKeyMaterial(holding([]), 'e-1'), isNull);
    });
  });
}
