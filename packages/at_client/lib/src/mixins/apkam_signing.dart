import 'dart:async' show Completer;

import 'package:at_auth/at_auth.dart' show AtKeys, KeyEntryStatus;
import 'package:at_chops/at_chops.dart' show AtPkamKeyPair, SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions, PutRequestOptions;
import 'package:at_commons/at_commons.dart'
    show AtClientException, AtKey, AtKeyNotFoundException, EnrollmentConstants;
import 'package:at_client/src/signing/apsk_composition.dart'
    show apskEntries, apskValueOf;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, apskUri, canSignEnvelopeWith;
import 'package:at_client/src/signing/resolved_signing_algo.dart'
    show signingAlgoOf;
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// The tail of each client's `_apsk` write chain, so [serialiseApskWrite] can
/// queue behind whatever is already running for that client.
///
/// Keyed on the [AtClient] rather than the atSign: two clients of one atSign
/// are two enrollments writing two different records.
final Expando<Future<void>> _apskWriteChain = Expando('apskWriteChain');

/// Runs [action] with no other `_apsk` write for [client] interleaved.
///
/// A minter publishes its new key before it files it, so that no envelope is
/// ever signed under a key the advertisement does not name. Between those two
/// steps the keyfile does not yet hold what was advertised, and any other
/// writer composing from the keyfile sees no signing key, takes the
/// authentication-key fallback, and overwrites the advertisement with it.
///
/// ⚠️ This is in-process only and claims nothing more: a concurrent second
/// client of the same atSign in another process can still interleave, which is
/// accepted.
///
/// A failed predecessor never wedges the chain: its error is the caller's to
/// see, not the next writer's to inherit.
Future<T> serialiseApskWrite<T>(
    AtClient client, Future<T> Function() action) async {
  final previous = _apskWriteChain[client];
  final release = Completer<void>();
  _apskWriteChain[client] = release.future;
  if (previous != null) {
    await previous.catchError((Object _) {});
  }
  try {
    return await action();
  } finally {
    release.complete();
  }
}

mixin ApkamSigning {
  AtClient get atClient;

  AtSignLogger get logger;

  String get enrollmentId {
    final id = atClient.enrollmentId;
    if (id == null) {
      logger.finer('No enrollment id; using '
          '"${EnrollmentConstants.primaryEnrollmentId}"');
    }
    return id ?? EnrollmentConstants.primaryEnrollmentId;
  }

  /// Where this enrollment's signing keys are advertised, e.g.
  /// `public:_apsk.<enrollment_id>.a.__e@atsign`. The record holds
  /// [publicSigningKeyValue] — every key, not one.
  String get publicSigningKeyUri =>
      apskUri(atClient.getCurrentAtSign()!, enrollmentId);

  /// Publishes this client's signing keys at [publicSigningKeyUri], if what is
  /// there is not already what it holds.
  ///
  /// This is the only writer for an `_apsk` that no `enroll:request` can
  /// carry. A client whose keyfile names no enrollment publishes under
  /// `primary` — the name the atServer answers a bare `pkam:` with — and has
  /// no id of its own to send an `enroll:update` for, so it writes the record
  /// directly.
  ///
  /// [value] overrides what is published, for the one caller that must
  /// advertise a key before filing it: [publicSigningKeyValue] is composed from
  /// what the keyfile holds, and a minter publishes first so that no envelope
  /// is ever signed under a key the advertisement does not name.
  ///
  /// Serialised against every other `_apsk` write this process makes for this
  /// client — see [serialiseApskWrite]. The composition happens inside the
  /// lock, so it cannot read a keyfile a mint has not finished writing and
  /// publish the fallback computed from it.
  Future publishPublicSigningKey({String? value}) => serialiseApskWrite(
      atClient, () => publishPublicSigningKeyLocked(value: value));

  /// [publishPublicSigningKey] without taking the lock, for a caller that
  /// already holds it. Taking it twice from one call chain would deadlock: the
  /// second acquire waits on a chain entry only the first can complete.
  Future publishPublicSigningKeyLocked({String? value}) async {
    value ??= await publicSigningKeyValue;

    String? published;
    try {
      logger.finer('publishPublicSigningKey: checking $publicSigningKeyUri');
      final current = await atClient.get(
        AtKey.fromString(publicSigningKeyUri),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      published = current.value is String ? current.value as String : null;
    } on AtKeyNotFoundException catch (err) {
      logger.info('${err.message} - publishing now');
    }

    if (published == value) {
      logger.finer('publishPublicSigningKey: have already published');
      return;
    }
    if (published != null) {
      logger.info('publishPublicSigningKey: what is published is not what this '
          'client holds - republishing');
    }
    // NOTE: this writes the value alone — a chain link riding this record's
    // `appMetadata` is not carried over.
    await atClient.put(
      AtKey.fromString(publicSigningKeyUri),
      value,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
  }

  /// What [publishPublicSigningKey] writes: what signs for this enrollment now
  /// plus the signing keys it has withdrawn from service, composed by
  /// [apskEntries] and spelled by [apskValueOf].
  ///
  /// The same rule decides the enrollment path's `apsk`-versus-`apskLegacy`,
  /// and the two must agree: they describe one record.
  Future<String> get publicSigningKeyValue async => apskValueOf(apskEntries(
        signing: await heldSigningKeys,
        withdrawn: await withdrawnSigningKeys,
        authentication: await authenticationSigningKey,
      ));

  /// This client's signing keys, strongest algorithm first — one entry per
  /// algorithm this enrollment holds a key for. Never empty.
  ///
  /// Sourced from the keyfile through [AtClient.atKeysIo] and read on every
  /// call: a cached copy goes stale the moment an `enroll:update` rotates the
  /// material, and signing with a key the keyfile has retired produces a
  /// signature that verifies against nothing. `atChops` is not a source — it
  /// carries the APKAM **authentication** keypair, which is separate material.
  ///
  /// Falls back to that authentication keypair when the enrollment holds no
  /// signing material this build can sign with, or when the client has no key
  /// source at all. [apskEntries] advertises that key on exactly the same
  /// condition, so what signs and what is advertised cannot drift apart.
  ///
  /// ⚠️ A mint publishes its new key before it files it, so between those two
  /// writes the keyfile does not yet hold what the advertisement names. On an
  /// enrollment holding no signing key, a read here then takes the
  /// authentication fallback at the moment the advertisement stops naming it,
  /// and the envelope verifies against nothing.
  Future<List<ApkamSigningKeys>> get signingKeys async {
    final held = await heldSigningKeys;
    if (held.isNotEmpty) return held;

    return [(await authenticationSigningKey)!];
  }

  /// The APKAM **authentication** keypair as a signing key: the keyfile's for
  /// [enrollmentId] — typed material first, the flat pair as `rsa2048`
  /// otherwise — else the client's `AtChops` keypair, for a client built
  /// without a key source; null when it holds neither.
  ///
  /// Two jobs, one key, for as long as an enrollment holds no signing material
  /// of its own: it authenticates the connection and it signs what the
  /// enrollment attests to. Once signing keys exist it stops doing the second
  /// job and drops out of the advertisement entirely ([apskEntries]) — safe
  /// because a credential whose posture wants a stronger authentication
  /// algorithm retrofits into a new enrollment rather than reclassifying this
  /// key, so the old enrollment's record keeps verifying what this key signed.
  Future<ApkamSigningKeys?> get authenticationSigningKey async {
    final fromKeyfile = (await _readKeyfile('authentication key'))
        ?.authenticationKeyPairFor(enrollmentId);
    if (fromKeyfile != null) {
      return ApkamSigningKeys(
        algorithm: fromKeyfile.algorithm,
        publicKey: fromKeyfile.publicKey,
        privateKey: fromKeyfile.privateKey,
      );
    }
    // NOTE: the door for a client built from an AtChops and no keyfile.
    final keyPair = atClient.atChops?.atChopsKeys.atPkamKeyPair;
    if (keyPair == null) return null;
    return ApkamSigningKeys(
      algorithm: signingAlgoOf(atClient),
      publicKey: keyPair.atPublicKey.publicKey,
      privateKey: keyPair.atPrivateKey.privateKey,
    );
  }

  /// [atClient]'s keyfile, or null when it has no key source or the read
  /// fails; a failure is logged naming [purpose], and the caller falls back.
  Future<AtKeys?> _readKeyfile(String purpose) async {
    final io = atClient.atKeysIo;
    final atSign = atClient.getCurrentAtSign();
    if (io == null || atSign == null) return null;
    try {
      return await io.read(atSign);
    } on Object catch (e) {
      logger.warning('Cannot read $atSign\'s keyfile for its $purpose ($e) — '
          'falling back to the APKAM authentication key');
      return null;
    }
  }

  /// What the keyfile holds for [enrollmentId], filtered to what this build
  /// can sign an envelope with. Empty when the client has no key source, when
  /// the read fails, or when the enrollment holds none.
  Future<List<ApkamSigningKeys>> get heldSigningKeys async {
    final keys = await _readKeyfile('signing keys');
    if (keys == null) return const [];

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

  /// The public half of every signing key this enrollment has taken out of
  /// service, each with the status the keyfile gives it — the non-active
  /// entries of its advertisement, which keep envelopes signed before the key
  /// was withdrawn verifiable.
  ///
  /// The status token is carried across verbatim, because the keyfile's
  /// vocabulary and the advertisement's are both open: a token a newer build
  /// wrote is what this enrollment's owner said about that key.
  ///
  /// ⚠️ Not filtered by [canSignEnvelopeWith], unlike [heldSigningKeys]: that
  /// filter asks what *this* build can sign with, and these entries exist for
  /// *other* parties to verify with.
  ///
  /// Empty when the client has no key source, when the read fails, or when
  /// nothing has been withdrawn from service.
  Future<
      List<
          ({
            SigningAlgoType algorithm,
            String publicKey,
            KeyEntryStatus status
          })>> get withdrawnSigningKeys async {
    final io = atClient.atKeysIo;
    final atSign = atClient.getCurrentAtSign();
    if (io == null || atSign == null) return const [];

    try {
      final keys = await io.read(atSign);
      return [
        for (final key in keys.withdrawnSigningKeysFor(enrollmentId))
          (
            algorithm: key.algorithm,
            publicKey: key.publicKey,
            status: KeyEntryStatus.of(key.status),
          ),
      ];
    } on Object catch (e) {
      logger.warning('Cannot read $atSign\'s withdrawn signing keys ($e) — '
          'advertising without them, so anything they signed will not verify '
          'until a later publish succeeds');
      return const [];
    }
  }

  /// The APKAM authentication keypair's halves, as at_client 3.14.0 returned
  /// them.
  ///
  /// Kept for a caller written against that version — they read the same
  /// place it did, `AtClient.atChops`. Two reasons they are deprecated, and
  /// the first is the one that bites:
  ///
  /// - **`_apsk` stops advertising this key** once the enrollment holds
  ///   signing keys of its own ([apskEntries] lists the authentication key
  ///   only while there are none), so a signature made with it verifies
  ///   against nothing. That is why a post-quantum posture makes these shout.
  /// - a key per algorithm is the model now, so one key cannot describe what
  ///   this enrollment signs with; [signingKeys] is the replacement, and
  ///   [publicSigningKeyValue] is what gets advertised.
  ///
  /// Throws when this enrollment authenticates with anything but `rsa2048`:
  /// the slot then holds base64 raw bytes of a post-quantum key, and handing
  /// those to a caller expecting an RSA key is a corrupted value rather than
  /// a policy mismatch. Also throws when the client holds no APKAM keypair at
  /// all, which 3.14.0 met with a null-check failure.
  @Deprecated('Read signingKeys instead: `_apsk` stops advertising the '
      'authentication key once this enrollment holds signing keys of its own, '
      'so what this returns may verify against nothing. Removed with '
      'AtClient.atChops in at_client 4.0.')
  String get publicSigningKey => _authenticationKeyPair().atPublicKey.publicKey;

  /// The private half of [publicSigningKey]; everything said there applies.
  @Deprecated('Sign with signingKeys instead: `_apsk` stops advertising the '
      'authentication key once this enrollment holds signing keys of its own, '
      'so signatures made with this may verify against nothing. Removed with '
      'AtClient.atChops in at_client 4.0.')
  String get privateSigningKey =>
      _authenticationKeyPair().atPrivateKey.privateKey;

  /// The keypair behind the two deprecated accessors, with the refusals and
  /// the warning they share.
  AtPkamKeyPair _authenticationKeyPair() {
    final algorithm = signingAlgoOf(atClient);
    if (algorithm != SigningAlgoType.rsa2048) {
      throw AtClientException.message(
          '${atClient.getCurrentAtSign()} authenticates enrollment '
          '$enrollmentId with ${algorithm.name}, so this accessor would hand '
          'back base64 ${algorithm.name} bytes where an RSA key is expected. '
          'Read signingKeys, which reports every key with its algorithm.');
    }
    // ignore: deprecated_member_use_from_same_package
    final keyPair = atClient.atChops?.atChopsKeys.atPkamKeyPair;
    if (keyPair == null) {
      throw AtClientException.message(
          '${atClient.getCurrentAtSign()} holds no APKAM keypair, so this '
          'accessor has nothing to return. Read signingKeys, which sources '
          'the keyfile.');
    }
    if (atClient.getPreferences()?.posture.configuresPqProviders ?? false) {
      logger.shout(
          'publicSigningKey/privateSigningKey read under a posture that '
          'configures post-quantum providers: `_apsk` may no longer advertise '
          'this key for enrollment $enrollmentId, and anything signed with it '
          'would then verify against nothing. Read signingKeys instead.');
    }
    return keyPair;
  }
}
