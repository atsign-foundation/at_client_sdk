/// What an approval seals for the enrollee, and what it takes to seal it.
///
/// Approval needs the atSign's encryption private key, to unwrap the APKAM
/// symmetric key an enrollee RSA-wrapped to it, and the self-encryption key,
/// which is one of the two secrets it seals for the enrollee under that
/// symmetric key. Neither is authentication, and neither should have to come
/// from a network object.
///
/// The seals are opened here with `StringAESEncryptor`, because that is what
/// the enrollee's handshake opens them with — a different AES implementation
/// from the one that seals, so agreement between the two is the contract and
/// not a restatement.
library;

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/enrollment_approver.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

void main() {
  const atSign = '@alice🛠';
  final encryptionPublicKey = demo.encryptionPublicKeyMap[atSign]!;
  final encryptionPrivateKey = demo.encryptionPrivateKeyMap[atSign]!;
  final selfEncryptionKey = demo.aesKeyMap[atSign]!;
  final apkamSymmetricKey = demo.apkamSymmetricKeyMap[atSign]!;

  /// A lookup holding no key material that records the one command sent.
  ({MockAtLookUp lookUp, List<String> commands}) emptyLookUp() {
    final lookUp = MockAtLookUp();
    final commands = <String>[];
    when(() => lookUp.atChops).thenReturn(null);
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((inv) async {
      commands.add(inv.positionalArguments[0] as String);
      return 'data:{"enrollmentId":"abc-123","status":"approved"}';
    });
    return (lookUp: lookUp, commands: commands);
  }

  /// A decision for an enrollee whose symmetric key the approver minted, so
  /// there is nothing to RSA-unwrap.
  EnrollmentRequestDecision mintedDecision() =>
      EnrollmentRequestDecision.approvedWithMintedKey(
        enrollmentId: 'abc-123',
        apkamSymmetricKey: apkamSymmetricKey,
        atSign: atSign,
      );

  /// A decision carrying the symmetric key RSA-wrapped to the atSign's
  /// encryption public key, as a legacy enrollee sends it.
  EnrollmentRequestDecision wrappedDecision() {
    final wrapped = (RsaEncryptionAlgo()
          ..atPublicKey = AtPublicKey.fromString(encryptionPublicKey))
        .encrypt(utf8.encode(apkamSymmetricKey));
    return EnrollmentRequestDecision.approved(
      enrollmentId: 'abc-123',
      apkamSymmetricKey: AtBytes.fromString(base64Encode(wrapped)),
      atSign: atSign,
    );
  }

  /// Opens both seals in the `enroll:approve` command the way the enrollee
  /// does, and returns what they held.
  ({String encryptionPrivateKey, String selfEncryptionKey}) unsealed(
      String command) {
    expect(command, startsWith('enroll:approve:'));
    final json = jsonDecode(
            command.substring('enroll:approve:'.length, command.length - 1))
        as Map<String, dynamic>;
    final opener = StringAESEncryptor(AESKey(apkamSymmetricKey));
    return (
      encryptionPrivateKey: opener.decrypt(
          json['encryptedDefaultEncryptionPrivateKey'] as String,
          iv: InitialisationVector.fromBase64(
              json[AtConstants.apkamEncryptionPrivateKeyIV] as String)),
      selfEncryptionKey: opener.decrypt(
          json[AtConstants.apkamEncryptedDefaultSelfEncryptionKey] as String,
          iv: InitialisationVector.fromBase64(
              json[AtConstants.apkamSelfEncryptionKeyIV] as String)),
    );
  }

  group('what the approval seals', () {
    test('opens, under the minted key, to the two secrets the enrollee needs',
        () async {
      final l = emptyLookUp();

      await EnrollmentApprover().approve(mintedDecision(), l.lookUp,
          approverKeys: (
            encryptionPrivateKey: encryptionPrivateKey,
            selfEncryptionKey: selfEncryptionKey
          ));

      final opened = unsealed(l.commands.single);
      expect(opened.encryptionPrivateKey, encryptionPrivateKey);
      expect(opened.selfEncryptionKey, selfEncryptionKey);
      // Never even asked: the material came with the call.
      verifyNever(() => l.lookUp.atChops);
    });

    test('opens, under a key the approver had to unwrap, to the same two',
        () async {
      // The RSA leg: a wrong or missing encryption private key cannot unwrap
      // the enrollee's key, so nothing sealed here would open under it.
      final l = emptyLookUp();

      await EnrollmentApprover().approve(wrappedDecision(), l.lookUp,
          approverKeys: (
            encryptionPrivateKey: encryptionPrivateKey,
            selfEncryptionKey: selfEncryptionKey
          ));

      final opened = unsealed(l.commands.single);
      expect(opened.encryptionPrivateKey, encryptionPrivateKey);
      expect(opened.selfEncryptionKey, selfEncryptionKey);
    });
  });

  group('where the material may still come from', () {
    test('an AtChops, for a caller that has not moved yet', () async {
      // The door this package is closing, kept working while it is open.
      final l = emptyLookUp();
      // ignore: deprecated_member_use
      final chops = AtChopsImpl(AtChopsKeys.create(
          AtEncryptionKeyPair.create(encryptionPublicKey, encryptionPrivateKey),
          null)
        ..selfEncryptionKey = AESKey(selfEncryptionKey));

      await EnrollmentApprover().approve(wrappedDecision(), l.lookUp,
          // ignore: deprecated_member_use
          approverChops: chops);

      final opened = unsealed(l.commands.single);
      expect(opened.encryptionPrivateKey, encryptionPrivateKey);
      expect(opened.selfEncryptionKey, selfEncryptionKey);
    });

    test('and with neither, it refuses', () async {
      // The control: without it the arms above would say nothing about where
      // the material came from.
      final l = emptyLookUp();

      await expectLater(
          () => EnrollmentApprover().approve(mintedDecision(), l.lookUp),
          throwsA(predicate((dynamic e) =>
              e is AtAuthenticationException &&
              e.message.contains('authentication keys are not initialized'))));
    });
  });
}
