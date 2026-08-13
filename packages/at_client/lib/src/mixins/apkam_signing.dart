import 'package:at_auth/at_auth.dart' show AtKeys;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions, PutRequestOptions;
import 'package:at_commons/at_commons.dart' show AtKey, AtKeyNotFoundException;
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

  Future publishPublicSigningKey() async {
    try {
      logger.info('publishPublicSigningKey: checking $publicSigningKeyUri');
      await atClient.get(
        AtKey.fromString(publicSigningKeyUri),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      logger.info('publishPublicSigningKey: have already published');
    } on AtKeyNotFoundException catch (err) {
      logger.info('${err.message} - publishing now');
      await atClient.put(
        AtKey.fromString(publicSigningKeyUri),
        await publicSigningKey,
        putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
      );
    }
  }

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
  /// property rather than an oversight. The fallback is not a stopgap: that
  /// key's public half stays published in `_apsk` permanently, because
  /// everything signed before an enrollment held signing keys of its own was
  /// signed by it, and withdrawing it would retroactively unverify all of it.
  Future<List<ApkamSigningKeys>> get signingKeys async {
    final held = await _heldSigningKeys();
    if (held.isNotEmpty) return held;

    final keyPair = atClient.atChops!.atChopsKeys.atPkamKeyPair!;
    return [
      ApkamSigningKeys(
        algorithm: signingAlgoOf(atClient),
        publicKey: keyPair.atPublicKey.publicKey,
        privateKey: keyPair.atPrivateKey.privateKey,
      )
    ];
  }

  /// What the keyfile holds for [enrollmentId], filtered to what this build
  /// can sign an envelope with. Empty when the client has no key source, when
  /// the read fails, or when the enrollment holds none.
  Future<List<ApkamSigningKeys>> _heldSigningKeys() async {
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

  /// The public key which verifies signatures made using [signingKeys] — the
  /// strongest one held, since [signingKeys] is ordered and never empty.
  ///
  /// One key, because [publishPublicSigningKey] writes `_apsk` as a bare
  /// string. The array composer that publishes every held key replaces both.
  Future<String> get publicSigningKey async =>
      (await signingKeys).first.publicKey;
}
