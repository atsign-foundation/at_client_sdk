/// Exact-shape pins over what the CLI's keyfile and checkpoint writers put at
/// rest through `FileAtKeysIo`, the same store `authenticate` reads back
/// through.
///
/// A change to any of it changes files users already hold, so it edits this
/// list first, and the two arms stay a pair — an absence alone would pass just
/// as well for a writer that had lost the ability to emit the typed document.
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
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
      // The exact emission, in the store's order. The atSign itself is a JSON
      // key carrying the plaintext selfEncryptionKey a second time, and it
      // sits beside the store's own 'atsign' field, which is a different
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
      expect(json['aesPkamPublicKey'], isNot(pkamPair.atPublicKey.publicKey),
          reason: 'the four aes* fields are AES-encrypted under the '
              'selfEncryptionKey, never plaintext');
      expect(json['aesEncryptPrivateKey'],
          isNot(encryptionPair.atPrivateKey.privateKey));
      // No typed-keys document at all: a `version: 1` document carrying no
      // enrollments says nothing a legacy file does not, and emitting one
      // would stamp every file a new build merely opened. The marker appears
      // with the material it marks.
      expect(json.containsKey('version'), isFalse);
      expect(json.containsKey('atsign'), isFalse);
      expect(json.containsKey('enrollments'), isFalse);
      expect(json.containsKey('atsignKeys'), isFalse);
    });

    test(
        'typed material brings the version/atsign/enrollments document with it',
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
        ..addKey(CryptographicMaterial(
          keyId: 'auth:mldsa65:1',
          enrollmentId: '456',
          role: CryptographicMaterialRole.privateAuthentication,
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
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
      // One entry per enrollment, each carrying its own keys rather than one
      // flat document-wide `keys` array.
      final enrollments = json['enrollments'] as List;
      expect(enrollments, hasLength(1));
      expect((enrollments.single as Map)['enrollmentId'], '456');
      expect((enrollments.single as Map)['keys'], isNotEmpty);
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
      final readBack =
          await FileAtKeysIo(filePath: (_) => file.path).read(atsign);
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
      // NOTE: a verbatim second declaration of at_auth's auth_constants
      // values — either package's copy moving breaks the other.
      expect(AuthKeyType.aesEncryptedPkamPublicKey, 'aesPkamPublicKey');
      expect(AuthKeyType.aesEncryptedPkamPrivateKey, 'aesPkamPrivateKey');
      expect(
          AuthKeyType.aesEncryptedEncryptionPublicKey, 'aesEncryptPublicKey');
      expect(
          AuthKeyType.aesEncryptedEncryptionPrivateKey, 'aesEncryptPrivateKey');
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
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json.keys.toSet(),
          {'enrollmentId', 'enrollStatus', 'atAuthKeys', 'validTill'});
      expect(json.containsKey('atSign'), isFalse,
          reason: 'the checkpoint deliberately does not reveal which atSign '
              'it belongs to');
      expect(json['enrollmentId'], '456');
      // NOTE: the keys are persisted PLAINTEXT — chmod 600 is the only
      // protection, unlike every .atKeys writer.
      expect(json['atAuthKeys']['selfEncryptionKey'], 'U0VMRkVOQw==');
    });
  });
}
