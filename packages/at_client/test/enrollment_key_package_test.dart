import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

import 'test_utils/envelope_tamper.dart';

/// The builder that puts a key package on `enroll:request`.
///
/// It runs at the one moment this is possible — the APKAM keypair exists and
/// the enrollment record does not — so the two things worth pinning are that
/// the private half it mints is kept somewhere durable, and that what it signs
/// verifies against the APKAM key the atServer will publish as `_apsk`.
void main() {
  const atSign = '@alice';

  /// The AtKeys at_auth hands the builder: the APKAM keypair it just
  /// generated, and no enrollmentId — the atServer has not assigned one.
  Future<(InMemoryAtKeysIo, AtKeys, AtPkamKeyPair)> freshKeys() async {
    final apkam = AtChopsUtil.generateAtPkamKeyPair();
    final keys = AtKeys()
      ..apkamPublicKey = AtBytes.fromString(apkam.atPublicKey.publicKey)
      ..apkamPrivateKey = AtBytes.fromString(apkam.atPrivateKey.privateKey);
    final io = InMemoryAtKeysIo();
    await io.write(atSign, keys);
    return (io, keys, apkam);
  }

  test('the X-Wing private half is kept in the AtKeys the enrollment persists',
      () async {
    final (io, keys, _) = await freshKeys();

    final metadata = await enrollmentKeyPackageBuilder(atSign)(io);

    final payload =
        SignedEnvelope.fromJson(metadata!['keyPackage'] as Map).payload as Map;
    final advertised = (payload['keys'] as List).single as Map;
    final kpid = advertised['kid'] as String;

    final private =
        keys.getAtSignKey(kpid, CryptographicKeyType.privateDecapsulation);
    expect(private, isNotNull,
        reason:
            'this AtKeys is the object at_auth flushes into the app keyfile '
            'on approval — a published encapsulation target whose private half '
            'was never kept leaves every sender sealing to a key that can '
            'never be opened');
    expect(private!.keyAlgorithmType, KeyAlgorithmType.xWing);

    // The public half is stored too, under the same keyId, so the pair can be
    // recovered together. Both are untagged at this point — the builder runs
    // before the atServer has assigned an enrollment id — so they sit in the
    // atSign's own container until the persist adopts them into the
    // enrollment.
    final public = keys.getAtSignKey(kpid, CryptographicKeyType.publicEncapsulation);
    expect(public, isNotNull);
    expect(base64Encode(public!.bytes.bytes), advertised['pub']);
  });

  test('the stored private half actually opens what the advertised half seals',
      () async {
    final (io, keys, _) = await freshKeys();

    final metadata = await enrollmentKeyPackageBuilder(atSign)(io);
    final payload =
        SignedEnvelope.fromJson(metadata!['keyPackage'] as Map).payload as Map;
    final advertised = (payload['keys'] as List).single as Map;
    final kpid = advertised['kid'] as String;

    // Seal to the advertised public half, exactly as a sender would...
    // The subject here is whether the filed private half matches the
    // advertised public one, not the binding, so both ends say Uint8List(0)
    // rather than borrowing a substrate's info.
    final sealed = await pqSeal(
      XWingPureDartAlgo.instance,
      base64Decode(advertised['pub'] as String),
      Uint8List.fromList(utf8.encode('a secret for the new device')),
      info: Uint8List(0),
    );
    // ...and open it with the half that was filed away.
    final private =
        keys.getAtSignKey(kpid, CryptographicKeyType.privateDecapsulation)!;
    final opened = await pqOpen(
      XWingPureDartAlgo.instance,
      Uint8List.fromList(private.bytes.bytes),
      sealed,
      info: Uint8List(0),
    );

    expect(utf8.decode(opened), 'a secret for the new device',
        reason: 'storing a private half that does not match the advertised '
            'public half would pass every structural check and fail only when '
            'a real secret arrived');
  });

  test(
      'the signature verifies against the APKAM key the atServer publishes '
      'as _apsk', () async {
    final (io, _, apkam) = await freshKeys();

    final metadata = await enrollmentKeyPackageBuilder(atSign)(io);
    final envelope = SignedEnvelope.fromJson(metadata!['keyPackage'] as Map);

    // _apsk is populated by the atServer from the record's apkamPublicKey, so
    // this is the key a verifier will actually check against.
    await verifyEnvelope(envelope,
        signerPublicKey: apkam.atPublicKey.publicKey,
            expecting: EnvelopeType.keyPackage);
  });

  test('a tampered package fails that verification', () async {
    final (io, _, apkam) = await freshKeys();

    final metadata = await enrollmentKeyPackageBuilder(atSign)(io);
    final envelope =
        SignedEnvelope.fromJson(metadata!['keyPackage'] as Map);
    final payload = Map<String, Object?>.from(envelope.payload as Map);
    // Substitute an encapsulation target — the attack the signature exists to
    // stop, since every structural field still agrees afterwards.
    final other = await XWingPureDartAlgo.instance.generateKeyPair();
    payload['keys'] = [
      {
        'use': 'enc',
        'alg': 'x-wing',
        'pub': base64Encode(other.publicKey),
        'kid': 'unchanged',
      }
    ];

    await expectLater(
      () => verifyEnvelope(envelope.withPayloadJson(payload),
          signerPublicKey: apkam.atPublicKey.publicKey,
              expecting: EnvelopeType.keyPackage),
      throwsA(isA<AtSigningVerificationException>()),
    );
  });

  // The builder used to take an envelopeVersion, so that a posture could
  // choose the shape a key package froze into. The package rides the
  // write-once metadata.keyPackage, which made picking the wrong one
  // unrecoverable; there is one shape now, so there is nothing to pick.

  test('carries no enrollmentId claim — the atServer has not assigned one yet',
      () async {
    final (io, _, _) = await freshKeys();

    final metadata = await enrollmentKeyPackageBuilder(atSign)(io);
    final envelope = SignedEnvelope.fromJson(metadata!['keyPackage'] as Map);

    expect(envelope.signerEnrollmentId, isNull,
        reason: 'a guessed or sentinel id would be frozen inside the signature '
            'where nobody could correct it, and the verifier compares the '
            'claim against the record id — so every package would be rejected');
  });

  test('throws rather than advertising a package it cannot sign', () async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys()); // no APKAM keypair

    expect(enrollmentKeyPackageBuilder(atSign)(io), throwsA(isA<StateError>()));
  });

  group('when the enrollment owns a signing key', () {
    // Ruling 98.3, amended 2026-08-14: `_apsk` verifies the key package as
    // well as the enrollment's envelopes, so whichever key the record names
    // must be the key that signed the package. Once the enrollment owns a
    // signing key, `_apsk` names THAT — so the package has to be signed with
    // it and not with the APKAM keypair, or every peer refuses to seal to the
    // enrollment and it receives no conveyed material at all.
    test('the package is signed by the signing key, not the APKAM key',
        () async {
      final (io, _, apkam) = await freshKeys();
      final signing = RsaKeyPair.generate();

      final metadata = await enrollmentKeyPackageBuilder(atSign,
          advertisedSigningKey: (
            algorithm: SigningAlgoType.rsa2048,
            publicKey: signing.atPublicKey.publicKey,
            privateKey: signing.atPrivateKey.privateKey
          ))(io);
      final envelope = SignedEnvelope.fromJson(metadata!['keyPackage'] as Map);

      // The peer's check with the peer's input: _apsk names the signing key.
      await verifyEnvelope(envelope,
          signerPublicKey: signing.atPublicKey.publicKey,
              expecting: EnvelopeType.keyPackage);

      // The differential. Without it this passes for a build that never
      // changed signer, because a package signed by the APKAM key is still a
      // validly signed package — it just verifies against the wrong record.
      await expectLater(
        () => verifyEnvelope(envelope,
            signerPublicKey: apkam.atPublicKey.publicKey,
                expecting: EnvelopeType.keyPackage),
        throwsA(isA<Exception>()),
        reason: 'a package still signed by the APKAM key verifies against '
            'that key and fails against _apsk, which is the silent conveyance '
            'break the amendment exists to prevent',
      );
    });

    test('without one, the APKAM key still signs it', () async {
      // The `now` path, unchanged: no signing key of its own means the APKAM
      // key both authenticates and signs, and _apsk names it.
      final (io, _, apkam) = await freshKeys();

      final metadata = await enrollmentKeyPackageBuilder(atSign)(io);

      await verifyEnvelope(
          SignedEnvelope.fromJson(metadata!['keyPackage'] as Map),
          signerPublicKey: apkam.atPublicKey.publicKey,
              expecting: EnvelopeType.keyPackage);
    });
  });
}
