import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions, PutRequestOptions;
import 'package:at_commons/at_commons.dart' show AtKey, AtKeyNotFoundException;
import 'package:at_client/src/signing/apsk_composition.dart'
    show apskEntries, apskValueOf;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, apskUri, canSignEnvelopeWith;
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show signingAlgoOf;
import 'package:at_utils/at_utils.dart' show AtSignLogger;

mixin ApkamSigning {
  AtClient get atClient;

  AtSignLogger get logger;

  String get enrollmentId {
    String id =
        atClient.getRemoteSecondary()?.atLookUp.enrollmentId ?? 'primary';
    if (id == 'primary') {
      logger.warning('No enrollmentID ... using "primary"');
    }
    return id;
  }

  /// the uri (e.g. `public:_apsk.<enrollment_id>.a.__e@atsign`) of the
  /// [publicSigningKey]
  String get publicSigningKeyUri =>
      apskUri(atClient.getCurrentAtSign()!, enrollmentId);

  /// Publishes this client's signing keys at [publicSigningKeyUri], if what is
  /// there is not already what it holds.
  ///
  /// This is the only writer for an `_apsk` that no `enroll:request` can carry
  /// — a client with no enrollment publishes under `primary`, which has no
  /// enrollment record for the atServer to compose one from.
  ///
  /// Republishes on a change rather than only when the record is absent. It
  /// used to read the record and log "have already published", so a key that
  /// had rotated never reached the atServer and every envelope signed with the
  /// new one was verified against the old.
  ///
  /// [value] overrides what is published, for the one caller that must
  /// advertise a key before filing it: [publicSigningKeyValue] is composed from
  /// what the keyfile holds, and a minter publishes first precisely so that no
  /// envelope is ever signed under a key the advertisement does not name.
  Future publishPublicSigningKey({String? value}) async {
    value ??= await publicSigningKeyValue;

    String? published;
    try {
      logger.info('publishPublicSigningKey: checking $publicSigningKeyUri');
      final current = await atClient.get(
        AtKey.fromString(publicSigningKeyUri),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      published = current.value is String ? current.value as String : null;
    } on AtKeyNotFoundException catch (err) {
      logger.info('${err.message} - publishing now');
    }

    if (published == value) {
      logger.info('publishPublicSigningKey: have already published');
      return;
    }
    if (published != null) {
      logger.info('publishPublicSigningKey: what is published is not what this '
          'client holds - republishing');
    }
    await atClient.put(
      AtKey.fromString(publicSigningKeyUri),
      value,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
  }

  /// What [publishPublicSigningKey] writes: what signs for this enrollment now
  /// plus the signing keys it has retired, composed by [apskEntries] and
  /// spelled by [apskValueOf].
  ///
  /// The same rule decides the enrollment path's `apsk`-versus-`apskLegacy`,
  /// and the two must agree: they describe one record.
  Future<String> get publicSigningKeyValue async =>
      apskValueOf(apskEntries(
        signing: await heldSigningKeys,
        retired: await retiredSigningKeys,
        authentication: authenticationSigningKey,
      ));

  /// This client's signing keys, strongest algorithm first — one entry per
  /// algorithm this enrollment holds a key for, which is what a
  /// multi-signature writer iterates. Never empty.
  ///
  /// Sourced from the keyfile through [AtClient.atKeysIo], which is where an
  /// enrollment's signing material lives. `atChops` is not a source for it:
  /// what it carries is the APKAM **authentication** keypair, a single pair
  /// that authenticates connections, and an enrollment's signing keys are
  /// separate material with their own lifecycle.
  ///
  /// Read on every call rather than cached. A cached copy goes stale the
  /// moment an `enroll:update` rotates the material out from under it, and
  /// signing with a key the keyfile has retired produces a signature that
  /// verifies against nothing.
  ///
  /// **Falls back to the APKAM authentication keypair** when the enrollment
  /// holds no signing material this build can sign with, or when the client
  /// has no key source at all — a source-less client is a deliberate, tested
  /// property rather than an oversight. [apskEntries] advertises that key on
  /// exactly the same condition, so what signs and what is advertised are one
  /// rule and cannot drift apart. Once the enrollment does hold a signing key
  /// the authentication key stops signing here and stops being advertised
  /// there, in the same step.
  Future<List<ApkamSigningKeys>> get signingKeys async {
    final held = await heldSigningKeys;
    if (held.isNotEmpty) return held;

    return [authenticationSigningKey!];
  }

  /// The APKAM **authentication** keypair as a signing key, or null when this
  /// client holds no `AtChops` keypair.
  ///
  /// Two jobs, one key, for as long as an enrollment holds no signing material
  /// of its own: it authenticates the connection and it signs what the
  /// enrollment attests to. Once signing keys exist it stops doing the second
  /// job and drops out of the advertisement entirely ([apskEntries]) — an
  /// enrollment that holds signing keys held them from birth, so this key
  /// signed nothing that outlives the transition.
  ApkamSigningKeys? get authenticationSigningKey {
    final keyPair = atClient.atChops?.atChopsKeys.atPkamKeyPair;
    if (keyPair == null) return null;
    return ApkamSigningKeys(
      algorithm: signingAlgoOf(atClient),
      publicKey: keyPair.atPublicKey.publicKey,
      privateKey: keyPair.atPrivateKey.privateKey,
    );
  }

  /// What the keyfile holds for [enrollmentId], filtered to what this build
  /// can sign an envelope with. Empty when the client has no key source, when
  /// the read fails, or when the enrollment holds none.
  Future<List<ApkamSigningKeys>> get heldSigningKeys async {
    final io = atClient.atKeysIo;
    final atSign = atClient.getCurrentAtSign();
    if (io == null || atSign == null) return const [];

    AtKeys keys;
    try {
      keys = await io.read(atSign);
    } on Object catch (e) {
      // warning, not info: falling back signs with a key the keyfile may not
      // hold as this enrollment's current one, and a signature produced by an
      // unexpected key is the hardest kind of failure to attribute later.
      logger.warning('Cannot read $atSign\'s signing keys ($e) — signing with '
          'the APKAM authentication key instead');
      return const [];
    }

    return [
      for (final key in keys.signingKeysFor(enrollmentId))
        if (canSignEnvelopeWith(key.algorithm))
          ApkamSigningKeys(
            algorithm: key.algorithm,
            publicKey: key.publicKey,
            privateKey: key.privateKey,
          )
    ];
  }

  /// The public half of every signing key this enrollment has retired — the
  /// `retired` entries of its advertisement, which keep envelopes signed
  /// before the key was withdrawn verifiable.
  ///
  /// ⚠️ **Not filtered by [canSignEnvelopeWith], unlike [heldSigningKeys].**
  /// That filter asks what *this* build can sign with, and these entries exist
  /// for *other* parties to verify with. Dropping one because this build has
  /// no signing routine for its algorithm would withdraw a key from the
  /// advertisement on a fact about the publisher, unverifying that key's
  /// envelopes for every reader that could have handled them.
  ///
  /// Empty when the client has no key source, when the read fails, or when
  /// nothing has been retired — which is every enrollment until a signing key
  /// leaves the in-use set.
  Future<List<({SigningAlgoType algorithm, String publicKey})>>
      get retiredSigningKeys async {
    final io = atClient.atKeysIo;
    final atSign = atClient.getCurrentAtSign();
    if (io == null || atSign == null) return const [];

    try {
      final keys = await io.read(atSign);
      return keys.retiredSigningKeysFor(enrollmentId);
    } on Object catch (e) {
      // warning, not info: publishing without these entries retroactively
      // unverifies every envelope the retired keys signed, and a verification
      // failure read months later names nothing that points back to here.
      logger.warning('Cannot read $atSign\'s retired signing keys ($e) — '
          'advertising without them, so anything they signed will not verify '
          'until a later publish succeeds');
      return const [];
    }
  }

  /// The public key which verifies signatures made using [signingKeys] — the
  /// strongest one held, since [signingKeys] is ordered and never empty.
  ///
  /// **One key out of what may be several, which is why nothing in production
  /// reads this.** An envelope carries a signature per key held and a verifier
  /// picks the strongest algorithm the envelope and the published `_apsk` have
  /// in common, so a caller that took this one would be choosing on the
  /// signer's behalf. What is published is [publicSigningKeyValue], which
  /// names every key.
  Future<String> get publicSigningKey async =>
      (await signingKeys).first.publicKey;
}
