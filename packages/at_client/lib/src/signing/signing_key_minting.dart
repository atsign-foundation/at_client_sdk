import 'package:at_auth/at_auth.dart'
    show
        AtEnrollment,
        EnrollmentUpdateRequest,
        KeyAlgorithmType,
        WrittenAtKeysIo;
import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, RsaKeyPair, SigningAlgoType;
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
/// A signing keypair can be minted unilaterally, which is the practical payoff
/// of separating the two jobs: it needs no server approval and no change to the
/// enrollment record's authority, unlike the APKAM authentication key, whose
/// replacement the atServer has to accept. The client mints it, advertises it,
/// and files it.
///
/// **This is the heal path, not the only producer.** An enrollment created by
/// a build that mints at enrollment-request time already holds its signing key
/// before it is approved, and finds nothing missing here. What reaches this
/// class is an enrollment created before that — which holds none — and a
/// client whose in-use set has changed since the last start, which is a stage
/// transition. Both are repairs to a keyfile that is already in service, which
/// is why every write here is composed from what the keyfile holds rather than
/// from what this run happens to know.
///
/// ⚠️ **A heal is an `enroll:update`, and the record it rewrites is read by
/// peers that predate all of this.** The advertisement's *form* therefore
/// matters as much as its content: a single active `rsa2048` key travels as
/// the bare string, in `apskLegacy`, because every deployed `_apsk` consumer
/// base64-decodes the value as an RSA key. This class sent the array
/// unconditionally until 2026-08-14, which put JSON on exactly the record
/// rollout 1 exists to keep readable.
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
///
/// **A withdrawal is filed after the addition**, for the same reason and in
/// the same direction: at every instant between the publish and the last
/// write, every key this client might sign with is named in the
/// advertisement. Filing the retirement first would leave a moment where the
/// enrollment holds no active signing key at all, and [ApkamSigning.signingKeys]
/// falls back to the APKAM authentication key there — a key the advertisement
/// has already stopped naming, so anything signed in that window would never
/// verify.
class SigningKeyMinting with ApkamSigning {
  SigningKeyMinting(this.atClient, {AtEnrollment? enrollment})
      : _enrollment = enrollment ?? AtEnrollment.create();

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('SigningKeyMinting');

  final AtEnrollment _enrollment;

  /// Mints, advertises and files what the in-use set names and the enrollment
  /// lacks; retires what it holds and the set no longer names. Returns both,
  /// each empty when there was nothing to do — which is the ordinary case on
  /// every start after the first.
  ///
  /// **Retirement is what makes a stage transition a transition.** Moving from
  /// an in-use set of `{rsa2048}` to `{mldsa65}` mints the ML-DSA key, and
  /// without this the RSA one stays *active*: the enrollment then holds two
  /// active signing keys, every envelope carries a second signature nothing
  /// asked for, and `_apsk` advertises both as current where the stage says
  /// one is retired. The retired key stays advertised — as `retired` — because
  /// it is retained for what it already signed.
  ///
  /// Inert with an empty in-use set (the 3.x default) and inert for a client
  /// with no key source: a minted key that cannot be filed is one this client
  /// signs with until it restarts and never again, having published it.
  ///
  /// ⚠️ **An empty set retires nothing**, and that is not the same rule as
  /// "every algorithm has left the set". It is the released posture, where a
  /// client that holds a signing key goes on signing with it and advertising
  /// it bare — which is exactly what that posture publishes. Retiring on it
  /// would drop the enrollment back to signing with its authentication key and
  /// turn the advertisement into an array (the retired entry beside the auth
  /// key), which is the breakage the staged rollout exists to avoid, on the
  /// stage that must never see it.
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
    final missing = [
      for (final algorithm in SigningAlgoType.strongestFirst)
        if (wanted.contains(algorithm) &&
            !held.any((key) => key.algorithm == algorithm))
          algorithm
    ];
    // What this build can sign with and the set no longer names. A held key
    // whose algorithm this build has no signing routine for is not here,
    // because heldSigningKeys does not return it: this client neither signs
    // with it nor advertises it as active, so there is nothing to withdraw.
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

    // Publish and file are one critical section, not two steps that happen to
    // run in order. The window between them is exactly where another writer in
    // this process composes from a keyfile that does not yet hold the minted
    // key, takes the authentication-key fallback, and overwrites what was just
    // advertised. Holding the lock across both means such a writer composes
    // after the filing and finds nothing to change.
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

  /// [keys] ordered by [SigningAlgoType.strongestFirst], which is the order an
  /// advertisement lists them in — a reader selects by algorithm and does not
  /// depend on it, but the record then reads the way the signer would state it.
  ///
  /// One definition for both halves of the advertisement, since the active and
  /// retired entries are differently shaped records and a second ordering rule
  /// would be a second chance to disagree about what "strongest" means.
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

  /// Advertises [active] plus this enrollment's retired signing keys —
  /// [retiring], which this call is about to withdraw, and the ones it
  /// withdrew earlier.
  ///
  /// The earlier ones are re-read here rather than assumed empty: this publish
  /// rewrites the whole record, so anything it leaves out is withdrawn. An
  /// enrollment that had retired a key and then minted a new one would
  /// otherwise lose the retired entry at the moment it gained a replacement,
  /// which is exactly when the old key's envelopes still need verifying.
  ///
  /// [retiring] is passed in rather than read back for the same reason it must
  /// not be left out: the keyfile still holds those keys as **active** at this
  /// point, because the publish comes first, so reading the retired set would
  /// return the record's history and miss the withdrawal this call is
  /// announcing. The key would vanish from the advertisement entirely rather
  /// than move to `retired`, and every envelope it signed — and the key
  /// package it signed, under rollout 1 — would stop verifying for good.
  ///
  /// Which writer depends on whether there is an enrollment record to carry it.
  /// An enrolled client sends `enroll:update`, so that the atServer writes the
  /// record from the enrollment it already holds. A client with no enrollment
  /// publishes the record itself, under `primary`, which has no enrollment
  /// record for the atServer to compose one from.
  ///
  /// ⚠️ **This used to say the atServer is the *only* writer of an enrolled
  /// enrollment's `_apsk`, "one writer for the record's whole life, which is
  /// what makes a rotation atomic from every reader's view". That is false and
  /// was corrected 2026-08-14.** [ApkamSigning.publishPublicSigningKey] writes
  /// the record directly, and two call sites in this package reach it for an
  /// enrolled client — `KeyPackageRegistration.register` and
  /// `PublishedNskeyKeyRing`. Both compose through `publicSigningKeyValue`, so
  /// they agree with this path on *content*; what the sentence claimed and
  /// nothing establishes is that there is a single writer.
  ///
  /// ⚠️ **The plurality has one measured cost, and it is ACCEPTED rather than
  /// guarded.** The caller publishes
  /// before it files, deliberately, so that no envelope is ever signed under a
  /// key the advertisement does not name. Between the two the keyfile does not
  /// yet hold what was advertised, so a concurrent
  /// `publishPublicSigningKey` — which composes from the keyfile — sees no
  /// signing key, falls back to the APKAM **authentication** key, and
  /// overwrites: measured, a PQ-native enrollment's ML-DSA array replaced by a
  /// bare RSA string.
  ///
  /// It heals. That getter composes from the keyfile, which by the next call
  /// holds the post-mint state, and `KeyPackageRegistration.register` reaches
  /// it on every start; verification reads the record live, so envelopes
  /// signed in the window verify again once it heals. The exposure is one
  /// process lifetime of refused envelopes.
  ///
  /// ⚠️ **Three guards against it were built and all three broke the live
  /// enrollment path.** The one that
  /// matters for anyone tempted to try a fourth: the rule "never drop an
  /// advertised key" cannot be stated over `public:_apsk.primary.a.__e`,
  /// which no single client owns and which non-enrolled clients overwrite in
  /// turn by design.
  Future<void> _publish(List<ApkamSigningKeys> active,
      {required List<ApkamSigningKeys> retiring}) async {
    final entries = apskEntries(
        signing: active,
        retired: _strongestFirst([
          for (final key in retiring)
            (algorithm: key.algorithm, publicKey: key.publicKey),
          ...await retiredSigningKeys,
        ], (key) => key.algorithm),
        authentication: authenticationSigningKey);
    final atLookUp = atClient.getRemoteSecondary()?.atLookUp;

    if (atLookUp?.enrollmentId == null) {
      // The unlocked variant: reconcileSigningKeys already holds the lock for
      // this whole publish-then-file section, and acquiring it again here would
      // wait on a chain entry only this call chain can complete.
      await publishPublicSigningKeyLocked(value: apskValueOf(entries));
      return;
    }
    // Which FIELD carries the advertisement is the same question as which
    // form the value takes, so it is answered by the same rule rather than by
    // a second one here. A single active rsa2048 key travels as the bare
    // string every deployed consumer base64-decodes; anything else has to be
    // the array, which those consumers fail on. Sending the array where the
    // bare form would do is the breakage rollout 1 exists to prevent, and it
    // is reachable from here whenever this client heals an enrollment that
    // was created without a signing key of its own.
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

  /// Withdraws this enrollment's [algorithm] signing keypair from service:
  /// both halves move to `retired`, and neither is removed. The public one is
  /// what the advertisement goes on carrying so that what it signed still
  /// verifies, and the private one stays because nothing in a keyfile is
  /// deleted.
  ///
  /// Through the store's atomic update, like [_file] and for the same reason.
  /// A status change read-mutate-written by hand is as losable as an addition:
  /// a sibling writer's flush computed from the pre-retirement snapshot puts
  /// the key back to active with nothing reporting it.
  ///
  /// Filing nothing when there is nothing to retire abandons the write rather
  /// than rewriting the keyfile to say what it already says. That case is not
  /// expected — the caller retires only what it just read as held — but a
  /// keyfile rewritten on every start is a durable store taking a write for
  /// no change.
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
  String _materialAlgorithmOf(SigningAlgoType algorithm) => switch (algorithm) {
        SigningAlgoType.mldsa65 => KeyAlgorithmType.mlDsa65,
        SigningAlgoType.rsa2048 => KeyAlgorithmType.rsa2048,
        _ => algorithm.name,
      };
}
