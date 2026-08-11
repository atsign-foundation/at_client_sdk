/// Exact-shape pins over the CLI's at-rest keyfile and checkpoint writers.
///
/// The CLI no longer declares the keyfile format: `_generateAtKeysFile`
/// writes through `FileAtKeysIo`, the same store `authenticate` reads back
/// through. These pins hold what that produces — the legacy fields under
/// their historical names, the `<@atSign>` entry the CLI still contributes,
/// and the typed-keys document's `version`/`atsign`/`keys` when there is
/// typed material to describe. A change to any of it changes files users
/// already hold, so it edits this list first.
///
/// The two arms below are a pair on purpose. A legacy onboard emits a
/// byte-for-byte legacy file with no typed scaffolding, so the absence of
/// `version`/`atsign`/`keys` is the contract, not an omission — and an
/// absence alone would pass just as well if the writer had lost the ability
/// to emit them at all. The typed arm is what rules that out.
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/onboard/helpers/enrollment_checkpoint.dart';
import 'package:at_onboarding_cli/src/util/auth_key_type.dart';
import 'package:test/test.dart';

void main() {
  group('the CLI legacy keyfile (at rest, frozen until consolidated)', () {
    test('createAtKeysFile emits exactly these fields, in this order',
        () async {
      const atsign = '@alice_pins';
      final preference = AtOnboardingPreference()
        ..hiveStoragePath = 'test/storage/hive/client'
        ..commitLogPath = 'test/storage/hive/client/commit'
        ..atKeysFilePath = '${Directory.current.path}/test/$atsign';
      final service = AtOnboardingServiceImpl(atsign, preference);

      final encryptionPair = service.generateRsaKeypair();
      final pkamPair = service.generateRsaKeypair();
      final selfEncryptionKey = service.generateAESKey();
      final apkamSymmetricKey = service.generateAESKey();
      final response = AtEnrollmentResponse('123', EnrollmentStatus.approved)
        ..atAuthKeys = (AtKeys()
          ..enrollmentId = '123'
          ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey)
          ..defaultEncryptionPublicKey =
              AtBytes.fromString(encryptionPair.atPublicKey.publicKey)
          ..defaultEncryptionPrivateKey =
              AtBytes.fromString(encryptionPair.atPrivateKey.privateKey)
          ..apkamPublicKey = AtBytes.fromString(pkamPair.atPublicKey.publicKey)
          ..apkamPrivateKey =
              AtBytes.fromString(pkamPair.atPrivateKey.privateKey)
          ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey));

      final file = await service.createAtKeysFile(response);
      addTearDown(() => File(file.path).deleteSync());

      final json = jsonDecode(File(file.path).readAsStringSync())
          as Map<String, dynamic>;
      // The exact emission, in the store's order. '@alice_pins' is the atSign
      // itself as a JSON key, carrying the plaintext selfEncryptionKey a
      // second time: it is in every keyfile ever written, so the CLI files it
      // into AtKeys.metadata rather than let the consolidation drop it. Note
      // it sits beside the store's own 'atsign' field, which is a different
      // thing — the name, not a key.
      expect(json.keys.toList(), [
        'aesPkamPublicKey',
        'aesPkamPrivateKey',
        'aesEncryptPublicKey',
        'aesEncryptPrivateKey',
        'selfEncryptionKey',
        'apkamSymmetricKey',
        'enrollmentId',
        atsign,
      ]);
      // Plaintext where plaintext, encrypted where encrypted.
      expect(json['selfEncryptionKey'], selfEncryptionKey);
      expect(json[atsign], selfEncryptionKey);
      expect(json['apkamSymmetricKey'], apkamSymmetricKey);
      expect(json['enrollmentId'], '123');
      expect(json['aesPkamPublicKey'],
          isNot(pkamPair.atPublicKey.publicKey),
          reason: 'the four aes* fields are AES-encrypted under the '
              'selfEncryptionKey, never plaintext');
      expect(json['aesEncryptPrivateKey'],
          isNot(encryptionPair.atPrivateKey.privateKey));
      // No typed-keys document at all. A `version: 1` document with an empty
      // `keys` array says nothing a legacy file does not, so emitting one
      // would stamp every file a new build merely opened — a diff on files
      // nobody meant to change. The marker appears with the material it
      // marks, which the next test pins.
      expect(json.containsKey('version'), isFalse);
      expect(json.containsKey('atsign'), isFalse);
      expect(json.containsKey('keys'), isFalse);
    });

    test('typed material brings the version/atsign/keys document with it',
        () async {
      const atsign = '@alice_typed_pins';
      final preference = AtOnboardingPreference()
        ..hiveStoragePath = 'test/storage/hive/client'
        ..commitLogPath = 'test/storage/hive/client/commit'
        ..atKeysFilePath = '${Directory.current.path}/test/$atsign';
      final service = AtOnboardingServiceImpl(atsign, preference);

      final encryptionPair = service.generateRsaKeypair();
      final pkamPair = service.generateRsaKeypair();
      final selfEncryptionKey = service.generateAESKey();
      final keys = AtKeys()
        ..enrollmentId = '456'
        ..atsign = atsign.toAtsign()
        ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey)
        ..defaultEncryptionPublicKey =
            AtBytes.fromString(encryptionPair.atPublicKey.publicKey)
        ..defaultEncryptionPrivateKey =
            AtBytes.fromString(encryptionPair.atPrivateKey.privateKey)
        ..apkamPublicKey = AtBytes.fromString(pkamPair.atPublicKey.publicKey)
        ..apkamPrivateKey = AtBytes.fromString(pkamPair.atPrivateKey.privateKey)
        ..apkamSymmetricKey = AtBytes.fromString(service.generateAESKey())
        ..addKey(AtKeysMaterial(
          keyId: 'apkam:456:1',
          enrollmentId: '456',
          keyPartType: CryptographicKeyType.privateAuthentication,
          keyAlgorithmType: KeyAlgorithmType.mlDsa65,
          // Shape, not substance — this pin is about the document the store
          // emits, so any well-formed base64 stands in for key material.
          bytes: AtBytes.fromString(base64Encode(utf8.encode('stand-in'))),
          createdAt: DateTime.now().toUtc(),
        ));
      final response = AtEnrollmentResponse('456', EnrollmentStatus.approved)
        ..atAuthKeys = keys;

      final file = await service.createAtKeysFile(response);
      addTearDown(() => File(file.path).deleteSync());

      final json = jsonDecode(File(file.path).readAsStringSync())
          as Map<String, dynamic>;
      expect(json['version'], 1);
      expect(json['atsign'], atsign);
      expect(json['keys'], isNotEmpty);
    });

    test('the store reads back exactly what the CLI wrote', () async {
      const atsign = '@alice_roundtrip';
      final preference = AtOnboardingPreference()
        ..hiveStoragePath = 'test/storage/hive/client'
        ..commitLogPath = 'test/storage/hive/client/commit'
        ..atKeysFilePath = '${Directory.current.path}/test/$atsign';
      final service = AtOnboardingServiceImpl(atsign, preference);

      final encryptionPair = service.generateRsaKeypair();
      final pkamPair = service.generateRsaKeypair();
      final selfEncryptionKey = service.generateAESKey();
      final response = AtEnrollmentResponse('789', EnrollmentStatus.approved)
        ..atAuthKeys = (AtKeys()
          ..enrollmentId = '789'
          ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey)
          ..defaultEncryptionPublicKey =
              AtBytes.fromString(encryptionPair.atPublicKey.publicKey)
          ..defaultEncryptionPrivateKey =
              AtBytes.fromString(encryptionPair.atPrivateKey.privateKey)
          ..apkamPublicKey = AtBytes.fromString(pkamPair.atPublicKey.publicKey)
          ..apkamPrivateKey =
              AtBytes.fromString(pkamPair.atPrivateKey.privateKey)
          ..apkamSymmetricKey = AtBytes.fromString(service.generateAESKey()));

      final file = await service.createAtKeysFile(response);
      addTearDown(() => File(file.path).deleteSync());

      // authenticate() reads through this same store, so a file this CLI
      // writes and cannot read is the failure mode that matters.
      final readBack = await FileAtKeysIo(filePath: (_) => file.path)
          .read(atsign);
      expect(readBack.apkamPrivateKey!.toString(),
          pkamPair.atPrivateKey.privateKey);
      expect(readBack.defaultEncryptionPrivateKey!.toString(),
          encryptionPair.atPrivateKey.privateKey);
      expect(readBack.defaultSelfEncryptionKey!.toString(), selfEncryptionKey);
      expect(readBack.enrollmentId, '789');
      expect(readBack.metadata[atsign], selfEncryptionKey,
          reason: 'the atSign-keyed entry survives the round trip as metadata');
    });

    test('the AuthKeyType field names, as raw strings', () {
      // A verbatim second declaration of at_auth's auth_constants values —
      // the classic both-sites hazard when either package's copy moves.
      expect(AuthKeyType.aesEncryptedPkamPublicKey, 'aesPkamPublicKey');
      expect(AuthKeyType.aesEncryptedPkamPrivateKey, 'aesPkamPrivateKey');
      expect(
          AuthKeyType.aesEncryptedEncryptionPublicKey, 'aesEncryptPublicKey');
      expect(AuthKeyType.aesEncryptedEncryptionPrivateKey,
          'aesEncryptPrivateKey');
      expect(AuthKeyType.selfEncryptionKey, 'selfEncryptionKey');
      expect(AuthKeyType.apkamSymmetricKey, 'apkamSymmetricKey');
    });
  });

  group('the enrollment checkpoint (at rest, frozen)', () {
    test('save emits its exact field set, with the atSign scrubbed', () async {
      final checkpoint = EnrollmentCheckpoint('@alice_pins');
      final atKeys = AtKeys()
        ..enrollmentId = '456'
        ..defaultSelfEncryptionKey = AtBytes.fromString('U0VMRkVOQw==');
      final response = AtEnrollmentResponse('456', EnrollmentStatus.pending)
        ..atAuthKeys = atKeys;

      await checkpoint.save(response, 'wavi', 'pixel', {'wavi': 'rw'});
      final file = checkpoint.getFile('wavi', 'pixel', {'wavi': 'rw'});
      addTearDown(() => file.deleteSync());

      expect(file.path, endsWith('.enrollment.checkpoint'));
      final json =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json.keys.toSet(),
          {'enrollmentId', 'enrollStatus', 'atAuthKeys', 'validTill'});
      expect(json.containsKey('atSign'), isFalse,
          reason: 'the checkpoint deliberately does not reveal which atSign '
              'it belongs to');
      expect(json['enrollmentId'], '456');
      // The keys are persisted PLAINTEXT — chmod 600 is the only protection,
      // unlike every .atKeys writer. Stated here so the consolidation cannot
      // change the posture silently in either direction.
      expect(json['atAuthKeys']['selfEncryptionKey'], 'U0VMRkVOQw==');
    });
  });
}
