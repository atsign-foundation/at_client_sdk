import 'package:at_auth/at_auth.dart'
    show
        AtEnrollment,
        EnrollmentUpdateRequest,
        CryptographicMaterialAlgorithm,
        KeyEntryStatus,
        WrittenAtKeysIo;
import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, RsaKeyPair, SigningAlgoType;
import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/mixins/apkam_signing.dart'
    show ApkamSigning, serialiseApskWrite;
import 'package:at_client/src/signing/apsk_composition.dart'
    show apskEntries, apskValueOf, bareApskValueOf;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_utils.dart' show AtSignLogger, AtUtils;

/// Brings an enrollment's signing keys into line with
/// [AtClientPreference.dataSigningKeyAlgorithms] — minting one for every
/// algorithm the set names and the enrollment does not hold, and retiring
/// every one it holds that the set no longer names.
///
/// A key is published before it is filed, and a withdrawal from service is
/// filed after the addition, so that at every instant every key this client
/// might sign with is named in the advertisement.
class SigningKeyMinting with ApkamSigning {
  /// Reconciles [atClient]'s signing keys, publishing through [enrollment] when
  /// one is supplied and a fresh [AtEnrollment] otherwise.
  SigningKeyMinting(this.atClient, {AtEnrollment? enrollment})
      : _enrollment = enrollment ?? AtEnrollment.create();

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('SigningKeyMinting');

  final AtEnrollment _enrollment;

  /// Mints, advertises and files what the in-use set names and the enrollment
  /// lacks; retires what it holds and the set no longer names, leaving a
  /// retired key advertised so that what it already signed still verifies.
  ///
  /// Returns both lists, each empty when there was nothing to do — as with an
  /// empty in-use set, which is inert, or a client with no key source.
  Future<({List<SigningAlgoType> minted, List<SigningAlgoType> retired})>
      reconcileSigningKeys() async {
    const nothing = (minted: <SigningAlgoType>[], retired: <SigningAlgoType>[]);

    final wanted = atClient.getPreferences()?.dataSigningKeyAlgorithms ??
        const <SigningAlgoType>{};
    if (wanted.isEmpty) return nothing;

    final atSign = atClient.getCurrentAtSign();
    final io = atClient.atKeysIo;
    if (atSign == null || io == null) return nothing;
    if (io is! WrittenAtKeysIo) {
      logger.warning('Not minting signing keys for $atSign: this AtKeysIo '
          'cannot persist, so the key would be published and then lost at the '
          'next start, leaving an advertisement nothing can sign under');
      return nothing;
    }

    final held = await heldSigningKeys;
    // NOTE: scoped to rsa2048, because that is the only case where one keypair
    // does both jobs — a legacy keyfile's flat fields, which AtKeys cannot read
    // back as typed signing material. Excluding whatever algorithm the
    // authentication keypair reports would instead stop an mldsa65 signing key
    // from ever being minted.
    final authenticationIsAlsoTheSigningKey = held.isEmpty &&
        authenticationSigningKey?.algorithm == SigningAlgoType.rsa2048;
    final missing = [
      for (final algorithm in SigningAlgoType.strongestFirst)
        if (wanted.contains(algorithm) &&
            !held.any((key) => key.algorithm == algorithm) &&
            !(authenticationIsAlsoTheSigningKey &&
                algorithm == SigningAlgoType.rsa2048))
          algorithm
    ];
    final superseded = [
      for (final key in held)
        if (!wanted.contains(key.algorithm)) key
    ];
    if (missing.isEmpty && superseded.isEmpty) return nothing;

    final minted = [for (final algorithm in missing) await _mint(algorithm)];
    final keeping = [
      for (final key in held)
        if (wanted.contains(key.algorithm)) key
    ];
    if (missing.isNotEmpty) {
      logger.info('Minted ${missing.map((a) => a.name).join(', ')} signing '
          'key(s) for $enrollmentId; publishing before filing');
    }
    if (superseded.isNotEmpty) {
      logger.info(
          'Retiring ${superseded.map((k) => k.algorithm.name).join(', ')} '
          'signing key(s) for $enrollmentId: the in-use set no longer names '
          'them. They stay advertised as retired, so what they signed still '
          'verifies');
    }

    // NOTE: publish and file are one critical section. In the window between
    // them another writer in this process composes from a keyfile that does not
    // yet hold the minted key and overwrites what was just advertised.
    await serialiseApskWrite(atClient, () async {
      await _publish(
          _strongestFirst([...minted, ...keeping], (key) => key.algorithm),
          retiring: superseded);
      for (final key in minted) {
        await _file(io, atSign, key);
      }
      for (final key in superseded) {
        await _retire(io, atSign, key.algorithm);
      }
    });
    return (
      minted: missing,
      retired: [for (final key in superseded) key.algorithm]
    );
  }

  /// [keys] ordered by [SigningAlgoType.strongestFirst], the order an
  /// advertisement lists them in.
  static List<T> _strongestFirst<T>(
          Iterable<T> keys, SigningAlgoType Function(T) algorithmOf) =>
      [
        for (final algorithm in SigningAlgoType.strongestFirst)
          ...keys.where((key) => algorithmOf(key) == algorithm)
      ];

  Future<ApkamSigningKeys> _mint(SigningAlgoType algorithm) async {
    switch (algorithm) {
      case SigningAlgoType.mldsa65:
        final pair = await MlDsa65KeyPair.generate();
        return ApkamSigningKeys(
            algorithm: algorithm,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey);
      case SigningAlgoType.rsa2048:
        final pair = RsaKeyPair.generate();
        return ApkamSigningKeys(
            algorithm: algorithm,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey);
      default:
        throw ArgumentError.value(algorithm.name, 'algorithm',
            'no minting routine, though the preference accepted it');
    }
  }

  /// Advertises [active] plus this enrollment's retired signing keys —
  /// [retiring], which this call is about to withdraw from service, and the
  /// ones it withdrew earlier.
  ///
  /// The publish rewrites the whole record, so anything left out is withdrawn
  /// from the advertisement; [retiring] is passed in rather than read back
  /// because the keyfile still holds those keys as active at this point.
  Future<void> _publish(List<ApkamSigningKeys> active,
      {required List<ApkamSigningKeys> retiring}) async {
    final entries = apskEntries(
        signing: active,
        withdrawn: _strongestFirst([
          for (final key in retiring)
            (
              algorithm: key.algorithm,
              publicKey: key.publicKey,
              status: KeyEntryStatus.retired,
            ),
          ...await withdrawnSigningKeys,
        ], (key) => key.algorithm),
        authentication: authenticationSigningKey);
    final atLookUp = atClient.getRemoteSecondary()?.atLookUp;

    if (isAtSignCredential(atLookUp?.enrollmentId)) {
      // NOTE: the unlocked variant — the caller holds the lock for the whole
      // publish-then-file section, and re-acquiring it here deadlocks.
      await publishPublicSigningKeyLocked(value: apskValueOf(entries));
      return;
    }
    final bare = bareApskValueOf(entries);
    await _enrollment.update(
        EnrollmentUpdateRequest(
            enrollmentId: atLookUp!.enrollmentId!,
            signingKeys: bare == null ? entries : null,
            apskLegacy: bare),
        atLookUp);
  }

  Future<void> _file(
      WrittenAtKeysIo io, String atSign, ApkamSigningKeys key) async {
    // NOTE: the store's atomic update, never a hand-rolled read-mutate-write —
    // a sibling writer on the same keyfile would drop this addition.
    await io.update(AtUtils.fixAtSign(atSign).toAtsign(), (keys) {
      keys.fileSigningMaterial(
          enrollmentId: enrollmentId,
          algorithm: _materialAlgorithmOf(key.algorithm),
          publicKey: key.publicKey,
          privateKey: key.privateKey);
      return true;
    });
  }

  /// Withdraws this enrollment's [algorithm] signing keypair from service: both
  /// halves move to `retired` and neither is removed, so that what the public
  /// one signed still verifies.
  ///
  /// Through the store's atomic update, like [_file]; with nothing to retire
  /// the write is abandoned.
  Future<void> _retire(
      WrittenAtKeysIo io, String atSign, SigningAlgoType algorithm) async {
    await io.update(AtUtils.fixAtSign(atSign).toAtsign(), (keys) {
      final retired =
          keys.retireSigningKeys(enrollmentId, _materialAlgorithmOf(algorithm));
      if (retired.isEmpty) {
        logger.warning('Nothing to retire for $enrollmentId under '
            '${algorithm.name}, though it was held a moment ago — leaving the '
            'keyfile alone. The advertisement already published lists it as '
            'retired, so nothing verifies differently, and the next start '
            'reconciles again');
        return false;
      }
      return true;
    });
  }

  /// The keyfile's spelling of [algorithm]. It matches [SigningAlgoType]'s
  /// member name for both, and `AtKeys.signingKeysFor` reads it back by that
  /// name — a second spelling here would file material the reader skips.
  CryptographicMaterialAlgorithm _materialAlgorithmOf(
          SigningAlgoType algorithm) =>
      switch (algorithm) {
        SigningAlgoType.mldsa65 => CryptographicMaterialAlgorithm.mlDsa65,
        SigningAlgoType.rsa2048 => CryptographicMaterialAlgorithm.rsa2048,
        _ => CryptographicMaterialAlgorithm.of(algorithm.name),
      };
}
