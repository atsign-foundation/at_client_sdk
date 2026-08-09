/// Exact-shape pins over the CLI's at-rest keyfile and checkpoint writers.
///
/// The CLI's `_generateAtKeysFile` is a SECOND declaration of the legacy
/// keyfile format — same field names as at_auth's writer, different key
/// order, plus a `<@atSign>` trailer entry at_auth does not emit. The
/// writer-consolidation work routes this through `FileAtKeysIo`; until the
/// formats are reconciled deliberately, these pins hold what existing
/// keyfiles actually look like. No test asserted a single field name of
/// either writer before this file.
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
      // The exact emission, in map-literal order. The '@alice_pins' entry is
      // the atSign itself as a JSON key, carrying the plaintext
      // selfEncryptionKey a second time — at_auth's writer has no such
      // trailer, and the consolidation must decide its fate deliberately.
      expect(json.keys.toList(), [
        'aesPkamPublicKey',
        'aesEncryptPublicKey',
        'aesEncryptPrivateKey',
        'selfEncryptionKey',
        atsign,
        'apkamSymmetricKey',
        'enrollmentId',
        'aesPkamPrivateKey',
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
