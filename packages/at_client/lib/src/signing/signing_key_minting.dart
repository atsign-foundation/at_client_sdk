import 'package:at_auth/at_auth.dart'
    show
        AtEnrollment,
        EnrollmentUpdateRequest,
        KeyAlgorithmType,
        WrittenAtKeysIo;
import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, RsaKeyPair, SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/signing/apsk_composition.dart'
    show apskEntries, apskValueOf;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_utils.dart' show AtSignLogger, AtUtils;

/// Gives an enrollment a signing key of its own for every algorithm
/// [AtClientPreference.inUseSigningAlgorithms] names and it does not hold.
///
/// A signing keypair can be minted unilaterally, which is the practical payoff
/// of separating the two jobs: it needs no server approval and no change to the
/// enrollment record's authority, unlike the APKAM authentication key, whose
/// replacement the atServer has to accept. The client mints it, advertises it,
/// and files it.
///
/// **Publish, then file — in that order, and the order is the design.** Between
/// the two a client holds a key it has not advertised, or advertises a key it
/// does not hold, and those two failures are not symmetrical:
///
/// - File first and the client signs with a key its `_apsk` does not name.
///   Envelopes are stored durably and verified whenever they are read, so every
///   envelope written before the publish lands is permanently unverifiable —
///   and nothing retries, because the next start finds the key already held and
///   has nothing to mint.
/// - Publish first and the advertisement names a key nobody holds. Nothing
///   signs with it, so no envelope refers to it; a verifier resolving an
///   algorithm simply finds one more candidate key that does not match, and the
///   entry disappears at the next publish, since the advertisement is composed
///   from what the keyfile holds.
///
/// This is the opposite of the rule for nskey privates (`NskeyPrivateFiling`
/// files before publishing the public half) and the asymmetry is real: an
/// encapsulation key published without its private makes senders seal data
/// nobody can open, which is a data loss no later repair undoes. A signing key
/// advertised without its private costs nothing.
class SigningKeyMinting with ApkamSigning {
  SigningKeyMinting(this.atClient, {AtEnrollment? enrollment})
      : _enrollment = enrollment ?? AtEnrollment.create();

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('SigningKeyMinting');

  final AtEnrollment _enrollment;

  /// Mints, advertises and files what the in-use set names and the enrollment
  /// lacks, returning the algorithms minted — empty when there was nothing to
  /// do, which is the ordinary case on every start after the first.
  ///
  /// Inert with an empty in-use set (the 3.x default) and inert for a client
  /// with no key source: a minted key that cannot be filed is one this client
  /// signs with until it restarts and never again, having published it.
  Future<List<SigningAlgoType>> mintMissing() async {
    final wanted = atClient.getPreferences()?.inUseSigningAlgorithms ??
        const <SigningAlgoType>{};
    if (wanted.isEmpty) return const [];

    final atSign = atClient.getCurrentAtSign();
    final io = atClient.atKeysIo;
    if (atSign == null || io == null) return const [];
    if (io is! WrittenAtKeysIo) {
      logger.warning('Not minting signing keys for $atSign: this AtKeysIo '
          'cannot persist, so the key would be published and then lost at the '
          'next start, leaving an advertisement nothing can sign under');
      return const [];
    }

    final held = await heldSigningKeys;
    final missing = [
      for (final algorithm in SigningAlgoType.strongestFirst)
        if (wanted.contains(algorithm) &&
            !held.any((key) => key.algorithm == algorithm))
          algorithm
    ];
    if (missing.isEmpty) return const [];

    final minted = [for (final algorithm in missing) await _mint(algorithm)];
    logger.info('Minted ${missing.map((a) => a.name).join(', ')} signing '
        'key(s) for $enrollmentId; publishing before filing');

    await _publish(_strongestFirst([...minted, ...held]));
    for (final key in minted) {
      await _file(io, atSign, key);
    }
    return missing;
  }

  /// [keys] ordered by [SigningAlgoType.strongestFirst], which is the order an
  /// advertisement lists them in — a reader selects by algorithm and does not
  /// depend on it, but the record then reads the way the signer would state it.
  List<ApkamSigningKeys> _strongestFirst(List<ApkamSigningKeys> keys) => [
        for (final algorithm in SigningAlgoType.strongestFirst)
          ...keys.where((key) => key.algorithm == algorithm)
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
        // RsaKeyPair, not AtChopsUtil.generateAtPkamKeyPair: that returns an
        // AtPkamKeyPair, which at_chops deprecates in favour of this one.
        final pair = RsaKeyPair.generate();
        return ApkamSigningKeys(
            algorithm: algorithm,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey);
      default:
        // Unreachable: AtClientPreference refuses an in-use set naming an
        // algorithm this build cannot sign an envelope under, and those are
        // exactly the two above. Throwing rather than asserting, because the
        // two would have to have drifted apart for this to be reached.
        throw ArgumentError.value(algorithm.name, 'algorithm',
            'no minting routine, though the preference accepted it');
    }
  }

  /// Advertises [active] plus the retained APKAM authentication key.
  ///
  /// Which writer depends on whether there is an enrollment record to carry it.
  /// An enrolled client sends `enroll:update`, because the atServer is the only
  /// writer of an enrollment's `_apsk` — one writer for the record's whole
  /// life, which is what makes a rotation atomic from every reader's view. A
  /// client with no enrollment publishes the record itself, under `primary`,
  /// which has no enrollment record for the atServer to compose one from.
  Future<void> _publish(List<ApkamSigningKeys> active) async {
    final entries =
        apskEntries(signing: active, authentication: authenticationSigningKey);
    final atLookUp = atClient.getRemoteSecondary()?.atLookUp;

    if (atLookUp?.enrollmentId == null) {
      await publishPublicSigningKey(value: apskValueOf(entries));
      return;
    }
    await _enrollment.update(
        EnrollmentUpdateRequest(
            enrollmentId: atLookUp!.enrollmentId!, signingKeys: entries),
        atLookUp);
  }

  Future<void> _file(
      WrittenAtKeysIo io, String atSign, ApkamSigningKeys key) async {
    // The store's own atomic update, never a hand-rolled read → mutate →
    // write: a client's start files conveyed key material through the same
    // keyfile, and whichever of the two flushed second would drop the other's
    // addition.
    await io.update(AtUtils.fixAtSign(atSign).toAtsign(), (keys) {
      keys.fileSigningMaterial(
          enrollmentId: enrollmentId,
          algorithm: _materialAlgorithmOf(key.algorithm),
          publicKey: key.publicKey,
          privateKey: key.privateKey);
      return true;
    });
  }

  /// The keyfile's spelling of [algorithm]. It matches [SigningAlgoType]'s
  /// member name for both, and `AtKeys.signingKeysFor` reads it back by that
  /// name — a second spelling here would file material the reader skips.
  String _materialAlgorithmOf(SigningAlgoType algorithm) =>
      switch (algorithm) {
        SigningAlgoType.mldsa65 => KeyAlgorithmType.mlDsa65,
        SigningAlgoType.rsa2048 => KeyAlgorithmType.rsa2048,
        _ => algorithm.name,
      };
}
