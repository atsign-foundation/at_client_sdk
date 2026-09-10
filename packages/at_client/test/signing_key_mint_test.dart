import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/enroll/signing_key_mint.dart'
    show mintAdvertisedSigningKey;
import 'package:at_client/src/preference/pq_posture.dart' show PqPosture;
import 'package:test/test.dart';

/// The one home for minting the data signing keypair an enrollment owns from
/// birth. What matters is that the algorithm it returns is the one the
/// enrollment will keep: mint anything else and the first start finds the
/// in-use algorithm missing, mints a second keypair and republishes `_apsk`,
/// orphaning the key the enrollment record already advertised.
void main() {
  group('the algorithm minted is the one the in-use set names', () {
    test('an empty set mints nothing', () async {
      expect(await mintAdvertisedSigningKey({}), isNull,
          reason: 'the legacy posture holds no data signing key at all; its '
              'authentication keypair does both jobs');
    });

    test('rsa2048', () async {
      final minted = await mintAdvertisedSigningKey({SigningAlgoType.rsa2048});

      expect(minted?.algorithm, SigningAlgoType.rsa2048);
      expect(minted!.publicKey, isNotEmpty);
      expect(minted.privateKey, isNotEmpty);
      expect(minted.publicKey, isNot(minted.privateKey));
    });

    test('mldsa65', () async {
      final minted = await mintAdvertisedSigningKey({SigningAlgoType.mldsa65});

      expect(minted?.algorithm, SigningAlgoType.mldsa65,
          reason: 'at pqActive the enrollment keeps ML-DSA-65, so minting '
              'rsa2048 here would leave its first start minting again and '
              'republishing the record the request just created');
      expect(minted!.publicKey, isNotEmpty);
      expect(minted.privateKey, isNotEmpty);
    });

    test('two mints are two different keypairs', () async {
      final a = await mintAdvertisedSigningKey({SigningAlgoType.rsa2048});
      final b = await mintAdvertisedSigningKey({SigningAlgoType.rsa2048});

      expect(a!.publicKey, isNot(b!.publicKey),
          reason: 'a fresh keypair per enrollment, or two enrollments would '
              'advertise one key and either could sign as the other');
    });
  });

  group('what it refuses rather than guessing', () {
    test('a set naming two algorithms', () async {
      expect(
          () => mintAdvertisedSigningKey(
              {SigningAlgoType.rsa2048, SigningAlgoType.mldsa65}),
          throwsA(isA<ArgumentError>()),
          reason: 'an envelope carries one signature per active signing key, '
              'so the weaker of two is only ever the one passed over or the '
              'one an attacker strips to. No posture names two');
    });

    test('an algorithm with no mint path', () async {
      expect(() => mintAdvertisedSigningKey({SigningAlgoType.ecc_secp256r1}),
          throwsA(isA<ArgumentError>()),
          reason: 'defaulting to one of the others would advertise a key the '
              'caller did not ask for');
    });
  });

  group('each posture gets the key it keeps', () {
    test('legacy mints none', () async {
      expect(
          await mintAdvertisedSigningKey(
              PqPosture.legacy.dataSigningKeyAlgorithms),
          isNull);
    });

    test('pqReady mints rsa2048', () async {
      final minted = await mintAdvertisedSigningKey(
          PqPosture.pqReady.dataSigningKeyAlgorithms);

      expect(minted?.algorithm, SigningAlgoType.rsa2048,
          reason: 'the bare `_apsk` form takes exactly one active rsa2048 '
              'entry, and that is the spelling an un-upgraded peer parses');
    });

    test('pqActive mints mldsa65', () async {
      final minted = await mintAdvertisedSigningKey(
          PqPosture.pqActive.dataSigningKeyAlgorithms);

      expect(minted?.algorithm, SigningAlgoType.mldsa65);
    });
  });
}
