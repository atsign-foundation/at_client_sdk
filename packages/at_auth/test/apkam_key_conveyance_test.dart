import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/at_keys.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

class MockLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

class LookUpVerbBuilderMatcher extends Matcher {
  @override
  Description describe(Description description) => description;

  @override
  bool matches(item, Map matchState) => item is LookupVerbBuilder;
}

void main() {
  const atSign = '@alice🛠';
  final alice = atSign.toAtsign();

  setUpAll(() => registerFallbackValue(MockLookupVerbBuilder()));

  group('the scheme picks a conveyance', () {
    // Signing and conveyance are independent axes — ML-DSA signs, X-Wing
    // encapsulates, and one keypair cannot do both — but each scheme still has
    // a default pairing. `sealed` is what makes this switch exhaustive.
    test('legacy wraps under RSA, postQuantum encapsulates under X-Wing', () {
      expect(AtAuthScheme.legacy.conveyance, isA<RsaKeyConveyance>());
      expect(AtAuthScheme.postQuantum.conveyance, isA<XWingKeyConveyance>());
    });
  });

  group('RsaKeyConveyance', () {
    const conveyance = RsaKeyConveyance();
    final publicKey = AtBytes.fromString(encryptionPublicKeyMap[atSign]!);
    final privateKey = AtBytes.fromString(encryptionPrivateKeyMap[atSign]!);

    test('mints a symmetric key and round-trips it', () async {
      final conveyed = await conveyance.wrap(publicKey);

      // AES-256: wrap mints the secret itself, so the caller never has to.
      expect(conveyed.sharedSecret, hasLength(32));
      expect(await conveyance.unwrap(AtBytes(conveyed.cipher), privateKey),
          conveyed.sharedSecret);
    });

    test('wraps a caller-supplied secret when given one', () async {
      final secret = AesCtrEncryptionAlgo(32).generateKey();

      final conveyed = await conveyance.wrap(publicKey, secret: secret);

      expect(conveyed.sharedSecret, secret);
      expect(await conveyance.unwrap(AtBytes(conveyed.cipher), privateKey),
          secret);
    });

    test('unwraps ciphertext produced outside this package', () async {
      // The approver has no idea what wrapped the key it was handed — only that
      // it is RSA under the atsign's encryption public key.
      final apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
      final wrapped = RSAPublicKey.fromString(encryptionPublicKeyMap[atSign]!)
          .encrypt(apkamSymmetricKey);

      final unwrapped =
          await conveyance.unwrap(AtBytes.fromString(wrapped), privateKey);

      expect(utf8.decode(unwrapped), apkamSymmetricKey);
    });
  });

  group('XWingKeyConveyance', () {
    const conveyance = XWingKeyConveyance();

    test('encapsulates to a keypackage and decapsulates back', () async {
      final keyPair = await XWingPureDartAlgo.instance.generateKeyPair();

      final conveyed = await conveyance.wrap(AtBytes(keyPair.publicKey));

      // A KEM derives the secret rather than transporting one, so there is
      // nothing for a caller to supply — which is why wrap takes only the
      // recipient's key.
      expect(conveyed.sharedSecret, hasLength(32));
      expect(
          await conveyance.unwrap(
              AtBytes(conveyed.cipher), AtBytes(keyPair.secretKey)),
          conveyed.sharedSecret);
    });
  });

  group('the conveyance an enrollment uses', () {
    late AtLookUp mockAtLookUp;
    late List<String> enrollCommands;

    setUp(() {
      mockAtLookUp = MockAtLookUp();
      enrollCommands = [];
      when(() => mockAtLookUp.executeCommand(any(that: startsWith('enroll:'))))
          .thenAnswer((invocation) async {
        enrollCommands.add(invocation.positionalArguments.first as String);
        return 'data:${jsonEncode({
              'enrollmentId': 'enroll-9',
              'status': 'pending'
            })}';
      });
    });

    void stubPublishedPublicKey(String base64PublicKey) {
      when(() =>
              mockAtLookUp.executeVerb(any(that: LookUpVerbBuilderMatcher())))
          .thenAnswer((_) async => 'data:$base64PublicKey');
    }

    Future<AtEnrollmentResponse> submit(AtEnrollment enrollment) =>
        enrollment.enroll(
          atsign: alice,
          rootDomain: AtRootDomain.atsignDomain,
          appName: 'wavi',
          deviceName: 'pixel',
          otp: testOtp(),
          namespaces: [
            NamespacePermission(namespace: 'wavi', read: true, write: true)
          ],
        );

    /// The `encryptedAPKAMSymmetricKey` the atServer would relay to the
    /// approver.
    String conveyedOnTheWire() => jsonDecode(enrollCommands.single.substring(
            enrollCommands.single.indexOf('{')))['encryptedAPKAMSymmetricKey']
        as String;

    test('defaults to RSA, which the approver can unwrap', () async {
      stubPublishedPublicKey(encryptionPublicKeyMap[atSign]!);

      final pending =
          await submit(AtEnrollment.create(mockAtLookUp)) as PendingEnrollment;

      // The approver holds the atsign's encryption private key and nothing
      // else, so what enroll put on the wire has to open with just that.
      final unwrapped = await const RsaKeyConveyance().unwrap(
          AtBytes.fromString(conveyedOnTheWire()),
          AtBytes.fromString(encryptionPrivateKeyMap[atSign]!));

      expect(AtBytes(unwrapped), pending.atKeys.apkamSymmetricKey,
          reason: 'the symmetric key the enrollee kept is the one it conveyed');
    });

    test('takes the injected conveyance over the scheme\'s default', () async {
      // X-Wing conveyance under the *legacy* auth scheme: the two axes are
      // chosen independently, so this pairing has to be reachable.
      final keyPair = await XWingPureDartAlgo.instance.generateKeyPair();
      stubPublishedPublicKey(base64Encode(keyPair.publicKey));

      final pending = await submit(AtEnrollment.create(mockAtLookUp,
          conveyance: const XWingKeyConveyance())) as PendingEnrollment;

      final unwrapped = await const XWingKeyConveyance().unwrap(
          AtBytes.fromString(conveyedOnTheWire()), AtBytes(keyPair.secretKey));

      expect(AtBytes(unwrapped), pending.atKeys.apkamSymmetricKey);
    });
  });
}
