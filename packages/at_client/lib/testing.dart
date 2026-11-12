/// Test support for programs that verify signed envelopes: an offline signer
/// and the `_apsk` that verifies what it signs.
///
/// Import this from tests only. Apps get it through their platform package,
/// as `package:at_client_cli/testing.dart` or
/// `package:at_client_flutter/testing.dart`.
library;

import 'dart:convert' show base64Encode;

import 'package:at_auth/at_auth.dart' show ApskSigningKey, KeyEntryStatus;
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, RsaKeyPair, SigningAlgoType;
import 'package:at_client/src/signing/apsk_composition.dart' show apskValueOf;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, EnvelopeType, SignedEnvelope, signEnvelope;
import 'package:at_client/src/signing/envelope_verification.dart'
    show PublishedApsk;
import 'package:at_commons/atsign.dart' show Atsign, AtsignString;
import 'package:meta/meta.dart' show experimental;

export 'package:at_client/src/collections/collections.dart'
    show
        collectionWithInjectedBoth,
        collectionWithInjectedDataEvents,
        collectionWithInjectedNotifications;

/// Signs offline as [atSign]'s enrollment [enrollmentId] with a fresh key
/// pair, for tests; needs no AtClient.
@experimental
final class TestEnvelopeSigner {
  TestEnvelopeSigner._(
      this.atSign, this.enrollmentId, this._key, this.listedAs);

  /// A signer with a fresh key pair under [algorithm], which
  /// [publishedApsk] lists as [listedAs]: active, retired, or any token, such
  /// as one this build does not know.
  ///
  /// Throws [ArgumentError] for an [algorithm] envelopes are not signed
  /// under.
  static Future<TestEnvelopeSigner> create({
    required String atSign,
    required String enrollmentId,
    SigningAlgoType algorithm = SigningAlgoType.mldsa65,
    KeyEntryStatus listedAs = KeyEntryStatus.active,
  }) async {
    final ApkamSigningKeys key;
    switch (algorithm) {
      case SigningAlgoType.mldsa65:
        final pair = await MlDsa65PureDartAlgo().generateKeyPair();
        key = ApkamSigningKeys(
            algorithm: algorithm,
            publicKey: base64Encode(pair.publicKey),
            privateKey: base64Encode(pair.secretKey));
      case SigningAlgoType.rsa2048:
        final pair = RsaKeyPair.generate();
        key = ApkamSigningKeys(
            algorithm: algorithm,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey);
      default:
        throw ArgumentError.value(
            algorithm, 'algorithm', 'envelopes are not signed under it');
    }
    return TestEnvelopeSigner._(atSign.toAtsign(), enrollmentId, key, listedAs);
  }

  /// The Atsign, canonical.
  final Atsign atSign;

  final String enrollmentId;

  /// The status [publishedApsk] lists this signer's key under.
  final KeyEntryStatus listedAs;

  final ApkamSigningKeys _key;

  SigningAlgoType get algorithm => _key.algorithm;

  /// An application envelope over [payload], stamped with `iss` and `enid`.
  SignedEnvelope sign(Object? payload) => signEnvelope(payload,
      keys: [_key],
      type: EnvelopeType.app,
      atSign: atSign,
      enrollmentId: enrollmentId);

  /// The `_apsk` this signer's enrollment would publish, listing its key as
  /// [listedAs].
  PublishedApsk get publishedApsk => PublishedApsk(
      atSign: atSign,
      enrollmentId: enrollmentId,
      value: apskValueOf([
        ApskSigningKey.forPublicKey(
            alg: _key.algorithm, pub: _key.publicKey, status: listedAs)
      ]));
}
