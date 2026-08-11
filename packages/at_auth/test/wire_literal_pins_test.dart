/// Exact-string pins over the enroll/otp verb commands and keyfile tokens
/// at_auth owns, ahead of the PQ refactor that will relocate or consolidate
/// their emitters.
///
/// The enroll:request variants already have exact wire pins
/// (first_enrollment_test.dart, at_self_enrollment_test.dart). What this file
/// pins is the rest of the verb surface — approve/deny/revoke/list/otp —
/// where today's tests match `startsWith('enroll:approve')` and would stay
/// green through any change to the JSON that follows the prefix.
///
/// Everything here is FROZEN wire or at-rest contract.
library;

import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

void main() {
  const atSign = '@alice🛠';

  /// A lookup whose atChops holds the demo keys, recording every command.
  ({MockAtLookUp lookUp, List<String> commands}) lookUp(
      {String response = 'data:{"status":"approved","enrollmentId":"id-1"}'}) {
    final mock = MockAtLookUp();
    final commands = <String>[];
    final atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            encryptionPublicKeyMap[atSign]!, encryptionPrivateKeyMap[atSign]!),
        AtPkamKeyPair.create(
            pkamPublicKeyMap[atSign]!, pkamPrivateKeyMap[atSign]!));
    atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKeyMap[atSign]!);
    atChopsKeys.selfEncryptionKey = AESKey(aesKeyMap[atSign]!);
    when(() => mock.atChops).thenReturn(AtChopsImpl(atChopsKeys));
    when(() => mock.executeCommand(any(), auth: true)).thenAnswer((inv) async {
      commands.add(inv.positionalArguments[0] as String);
      return response;
    });
    return (lookUp: mock, commands: commands);
  }

  group('FROZEN: the enroll verb commands past their prefixes', () {
    test('enroll:approve carries exactly these five JSON keys', () async {
      final l = lookUp();
      // approve() RSA-decrypts the conveyed key before it builds the command,
      // so the decision must carry a genuinely encrypted one.
      final encryptedApkamSymmetricKey =
          RSAPublicKey.fromString(encryptionPublicKeyMap[atSign]!)
              .encrypt(apkamSymmetricKeyMap[atSign]!);
      final decision = EnrollmentRequestDecision.approved(
        enrollmentId: 'id-1',
        apkamSymmetricKey: AtBytes.fromString(encryptedApkamSymmetricKey),
        atSign: atSign,
      );

      await AtEnrollmentImpl().approve(decision, l.lookUp);

      final command = l.commands.single;
      expect(command, startsWith('enroll:approve:'));
      expect(command, endsWith('\n'));
      final json = jsonDecode(
              command.substring('enroll:approve:'.length, command.length - 1))
          as Map<String, dynamic>;
      // The long first key is an INLINE literal in the emitter:
      // 'encryptedDefaultEncryptionPrivateKey'. AtConstants has a
      // similarly-named constant whose value is the DIFFERENT string
      // 'encryptedDefaultEncPrivateKey' — a consolidation that "fixes"
      // approve onto the constant changes the wire. This pin is what makes
      // that fail loudly.
      expect(json.keys.toList(), [
        'enrollmentId',
        'encryptedDefaultEncryptionPrivateKey',
        'encPrivateKeyIV',
        'encryptedDefaultSelfEncryptionKey',
        'selfEncKeyIV',
      ]);
      expect(json['enrollmentId'], 'id-1');
    });

    test('enroll:deny is the builder form', () async {
      final l = lookUp(
          response: 'data:{"status":"denied","enrollmentId":"id-1"}');

      await AtEnrollmentImpl()
          .deny(EnrollmentRequestDecision.denied('id-1', atSign), l.lookUp);

      expect(l.commands.single, 'enroll:deny:{"enrollmentId":"id-1"}\n');
    });

    test('enroll:revoke is the builder form', () async {
      final l = lookUp(
          response: 'data:{"status":"revoked","enrollmentId":"id-1"}');

      await AtEnrollmentImpl()
          .revoke(EnrollmentRequestDecision.denied('id-1', atSign), l.lookUp);

      expect(l.commands.single, 'enroll:revoke:{"enrollmentId":"id-1"}\n');
    });

    test('enroll:list without filters is the bare verb', () async {
      final l = lookUp(response: 'data:{}');

      await AtEnrollmentImpl().list(null, l.lookUp);

      expect(l.commands.single, 'enroll:list\n');
    });

    test('enroll:list joins all statuses into ONE array element', () async {
      final l = lookUp(response: 'data:{}');

      await AtEnrollmentImpl().list(
          [EnrollmentStatus.approved, EnrollmentStatus.pending], l.lookUp);

      // Not a JSON list of names — the filter values are comma-joined inside
      // a single array element. The atServer parses this form, so it is the
      // contract, however it looks; EnrollVerbBuilder would generate a proper
      // string list, which is precisely why this hand-built emitter needs its
      // own pin before any consolidation onto the builder.
      expect(l.commands.single,
          'enroll:list:{"enrollmentStatusFilter":["approved,pending"]}\n');
    });
  });

  group('FROZEN: the post-approval handshake key fetches', () {
    test('the two keys:get commands, full string including .__manage suffix',
        () async {
      // The emitters build these from inline segment literals; the existing
      // pins match only the prefix, leaving '.__manage<atSign>\n' unguarded.
      // The CLI carries its own duplicate declaration of the same two wire
      // strings — when the consolidation deletes that copy and delegates
      // here, these emitters become the single source, and this the guard.
      final mock = MockAtLookUp();
      final commands = <String>[];
      final apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
      final iv = AtChopsUtil.generateRandomIV(16);
      final ivB64 = base64Encode(iv.ivBytes);
      final aes = StringAESEncryptor(AESKey(apkamSymmetricKey));
      when(() => mock.pkamAuthenticate(enrollmentId: '123'))
          .thenAnswer((_) async => true);
      // The fetches ride the just-authenticated connection: executeCommand
      // is called with NO auth argument (unlike every enroll: verb).
      when(() => mock.executeCommand(any())).thenAnswer((inv) async {
        final command = inv.positionalArguments[0] as String;
        commands.add(command);
        return jsonEncode({
          'value': aes.encrypt(
              command.contains('default_enc_private_key')
                  ? encryptionPrivateKeyMap[atSign]!
                  : aesKeyMap[atSign]!,
              iv: iv),
          'iv': ivB64,
        });
      });

      final response = AtEnrollmentResponse('123', EnrollmentStatus.pending)
        // ignore: deprecated_member_use_from_same_package
        ..atSign = atSign
        // ignore: deprecated_member_use_from_same_package
        ..rootDomain = const AtRootDomain('vip.ve.atsign.zone', 64)
        ..atAuthKeys = (AtKeys(atsign: atSign.toAtsign())
          ..apkamPublicKey = AtBytes.fromString(pkamPublicKeyMap[atSign]!)
          ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKeyMap[atSign]!)
          ..defaultEncryptionPublicKey =
              AtBytes.fromString(encryptionPublicKeyMap[atSign]!)
          ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey));

      await AtEnrollmentImpl().waitForApproval(response,
          atLookup: mock, retryInterval: Duration.zero, logProgress: false);

      expect(commands, [
        'keys:get:keyName:123.default_enc_private_key.__manage$atSign\n',
        'keys:get:keyName:123.default_self_enc_key.__manage$atSign\n',
      ]);
    });
  });

  group('FROZEN: the otp verb commands', () {
    test('otp:get with the default 5-minute ttl', () async {
      final l = lookUp(response: 'data:ABC123');

      await AtEnrollmentImpl().generateOtp(l.lookUp);

      expect(l.commands.single, 'otp:get:ttl:300000\n');
    });

    test('otp:put carries the spp and ttl', () async {
      final l = lookUp(response: 'data:ok');

      await AtEnrollmentImpl().setSpp('ABC123', l.lookUp);

      expect(l.commands.single, 'otp:put:ABC123:ttl:300000\n');
    });
  });

  group('FROZEN: keyfile tokens shared with the wire', () {
    test('KeyAlgorithmType tokens, as raw strings', () {
      // rsa2048 / mldsa65 / ecc_secp256r1 double as the pkam and
      // enroll-request signingAlgo wire values; xwing / mlkem1024 are the
      // deliberately-unhyphenated keyfile twins of the wire's 'x-wing' /
      // 'ml-kem-1024'. The field is an open String — unknown tokens must
      // round-trip — so these pins protect writers, never reject readers.
      expect(KeyAlgorithmType.known, {
        'aes256',
        'rsa2048',
        'ecc_secp256r1',
        'ed25519',
        'x25519',
        'mlkem768',
        'mlkem1024',
        'mldsa65',
        'xwing',
      });
    });

    test('the keyfile tokens and enum names are the SAME strings', () {
      // AtKeys.signingAlgorithmForEnrollment resolves keyfile tokens back to
      // SigningAlgoType by `.name` equality, and at_auth files material with
      // `signingAlgo.name` directly — renaming either side breaks every PQ
      // keyfile's ability to authenticate, with no compile error.
      expect(KeyAlgorithmType.mlDsa65, SigningAlgoType.mldsa65.name);
      expect(KeyAlgorithmType.rsa2048, SigningAlgoType.rsa2048.name);
      expect(KeyAlgorithmType.eccSecp256r1, SigningAlgoType.ecc_secp256r1.name);
    });

    test('CryptographicKeyType tokens and KeyPartStatus names', () {
      expect(CryptographicKeyType.known, {
        'symmetricEncryption',
        'symmetricAuthentication',
        'publicEncryption',
        'privateDecryption',
        'publicVerification',
        'privateSigning',
        'publicEncapsulation',
        'privateDecapsulation',
        'publicKeyAgreement',
        'privateKeyAgreement',
        'privateAuthentication',
        'publicAuthentication',
      });
      expect(KeyPartStatus.values.map((s) => s.name).toList(),
          ['active', 'retired', 'dead']);
    });

    test('the typed keyfile ids APKAM and signing material file under', () {
      // Pinned against the WRITERS, not against hand-built materials: a pin
      // that constructs the id it then asserts pins nothing, and the shape is
      // only frozen if the code that emits it is what produced the string.
      final atKeys = AtKeys(atsign: '@alice'.toAtsign());

      atKeys.fileApkamMaterial(
          enrollmentId: 'enroll-1',
          algorithm: KeyAlgorithmType.mlDsa65,
          publicKey: 'QUJD',
          privateKey: 'REVG');
      expect(atKeys.keysForKeyId('apkam:enroll-1:1'), hasLength(2),
          reason: 'apkam:<enrollmentId>:<generation> is the at-rest id for an '
              'enrollment authentication keypair');

      atKeys.fileSigningMaterial(
          enrollmentId: 'enroll-1',
          algorithm: KeyAlgorithmType.mlDsa65,
          publicKey: 'R0hJ',
          privateKey: 'SktM');
      expect(atKeys.keysForKeyId('sign:enroll-1:mldsa65:1'), hasLength(2),
          reason: 'sign:<enrollmentId>:<algorithm>:<generation> is the '
              'at-rest id for an enrollment signing keypair');

      expect(
          atKeys
              .getKey('apkam:enroll-1:1',
                  CryptographicKeyType.privateAuthentication)!
              .toJson()['keyAlgorithmType'],
          'mldsa65');
    });
  });
}
