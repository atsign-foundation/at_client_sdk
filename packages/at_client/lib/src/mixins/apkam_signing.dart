import 'dart:async' show Completer;

import 'package:at_auth/at_auth.dart'
    show AtKeys, KeyEntryStatus, publicKeyKidOfBase64;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions, PutRequestOptions;
import 'package:at_commons/at_commons.dart'
    show AtKey, AtKeyNotFoundException, EnrollmentConstants;
import 'package:at_client/src/signing/apsk_composition.dart'
    show apskEntries, apskValueOf;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, apskUri, canSignEnvelopeWith;
import 'package:at_utils/at_utils.dart' show AtSignLogger;

/// The tail of each client's `_apsk` write chain, so [serialiseApskWrite] can
/// queue behind whatever is already running for that client.
///
/// Keyed on the [AtClient] rather than the atSign: two clients of one atSign
/// are two enrollments writing two different records.
final Expando<Future<void>> _apskWriteChain = Expando('apskWriteChain');

/// The `kid`s of the keys each client's own enrollment has a link for, as last
/// read from its `_apsk`; absent until something has read them.
final Expando<Set<String>> _ownLinkedKids = Expando('ownLinkedKids');

/// Records [kids] as the keys [client]'s own enrollment has a link for, which
/// [ApkamSigning.signingKeys] then prefers.
void rememberOwnLinkedKids(AtClient client, Set<String> kids) =>
    _ownLinkedKids[client] = Set.unmodifiable(kids);

/// Runs [action] with no other `_apsk` write for [client] interleaved.
///
/// Every publish of the client data signing keys re-sends a whole record
/// composed from the keyfile, read first. A write landing between another's
/// read and its put is therefore lost, so a caller holds this from that read
/// through its put.
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
  /// [value] overrides what is published, for the one caller that advertises
  /// a key as retired while the keyfile still holds it active:
  /// [publicSigningKeyValue] is composed from what the keyfile holds, and a
  /// minter withdraws a key from the advertisement before it files the
  /// withdrawal.
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

  /// The keys this client signs content with, strongest algorithm first:
  /// those of its client data signing keys that have a link, while any do, and
  /// otherwise every one it holds. Never empty: throws
  /// [AtKeyNotFoundException] when it holds no key to sign with, as when its
  /// keyfile cannot be read.
  ///
  /// Which keys have a link is what [rememberOwnLinkedKids] last recorded;
  /// until something has, every held key signs.
  ///
  /// Sourced from the keyfile through [AtClient.atKeysIo] and read on every
  /// call: a cached copy goes stale the moment an `enroll:update` rotates the
  /// material, and signing with a key the keyfile has retired produces a
  /// signature that verifies against nothing.
  ///
  /// Falls back to that authentication keypair when the enrollment holds no
  /// signing material this build can sign with, or when the client has no key
  /// source at all. [apskEntries] advertises that key on exactly the same
  /// condition, so what signs and what is advertised cannot drift apart.
  ///
  /// ⚠️ A mint files its new key before it publishes it, so between those two
  /// writes this answers a key the advertisement does not name yet. An
  /// envelope signed then verifies once the publish lands, or, if a stop
  /// lands first, once the next start's republish does.
  Future<List<ApkamSigningKeys>> get signingKeys async {
    final held = await heldSigningKeys;
    if (held.isEmpty) {
      return [
        await authenticationSigningKey ??
            (throw AtKeyNotFoundException('${atClient.getCurrentAtSign()} '
                'holds no key enrollment $enrollmentId can sign with'))
      ];
    }

    final linkedKids = _ownLinkedKids[atClient];
    if (linkedKids == null) return held;
    final linked = [
      for (final key in held)
        if (linkedKids.contains(publicKeyKidOfBase64(key.publicKey))) key
    ];
    return linked.isEmpty ? held : linked;
  }

  /// The APKAM **authentication** keypair as a signing key: the keyfile's for
  /// [enrollmentId] — typed material first, the flat pair as `rsa2048`
  /// otherwise — or null when it holds neither.
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
    if (fromKeyfile == null) return null;
    return ApkamSigningKeys(
      algorithm: fromKeyfile.algorithm,
      publicKey: fromKeyfile.publicKey,
      privateKey: fromKeyfile.privateKey,
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
}
