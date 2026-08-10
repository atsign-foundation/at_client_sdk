import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_mint_lock.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show envelopePayloadOf, envelopeVersionOf, jwsEnvelopeVersion;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart' show visibleForTesting;

final _logger = AtSignLogger('PublishedNskeyKeyRing');

/// Checks that a fetched advertisement really came from the atSign that claims
/// it, before anything is encapsulated to it.
///
/// Every advertised encapsulation key is an APKAM-signed envelope, verified
/// against the publishing enrollment's `_apsk` — the same path same-atSign and
/// cross-atSign.
abstract class AdvertisedKeyVerifier {
  /// Return the advertisement carried by [payload], or throw if it cannot be
  /// trusted as [owner]'s.
  Future<NskeyAdvertisement> verify(String owner, String payload);
}

/// The version stamped on the nskey advertisement payload.
///
/// The payload carried none until 2026-08-06, which left a reader nothing to
/// dispatch on if the construction changed — every other signed payload in the
/// design carries one. The record IS rewritable (a rotation overwrites it), so
/// this is cheap insurance rather than a deadline, and it is the hatch that
/// makes moving the envelope to JWS reversible.
const int nskeyAdvertisementVersion = 1;

/// Verifies an advertisement's APKAM signature against the `_apsk` public key
/// that the signing enrollment published under [owner]'s atSign.
///
/// Two gates stand between an attacker and the key a sender encapsulates to,
/// and it takes both to place one:
///
/// - **The write gate.** `__nskey.<ns>` sits in `<ns>`, so the atServer accepts
///   the write only from an enrollment authorised for that namespace.
/// - **This signature.** The envelope names its signing enrollment, and the
///   signature is checked against the `_apsk` only that enrollment may write.
///
/// So a rogue enrollment holding some other namespace can sign but not publish,
/// and anything that reaches the record unsigned — or signed by an enrollment
/// whose `_apsk` does not verify it — is rejected rather than sealed to.
///
/// What this does **not** defend against is the operator of [owner]'s atServer,
/// which serves both the advertisement and the `_apsk` it is checked against
/// and so can substitute a consistent pair. Removing that requires anchoring
/// the key somewhere the operator does not control; see the trust boundary in
/// `docs/projects/pq/design.md`.
class ApkamSignedAdvertisedKeys implements AdvertisedKeyVerifier {
  final AtClientEnvelopeSigner _signer;

  ApkamSignedAdvertisedKeys(AtClient atClient)
      : _signer = AtClientEnvelopeSigner(atClient);

  @override
  Future<NskeyAdvertisement> verify(String owner, String payload) async {
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(payload) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner is not JSON: ${e.message}');
    }
    // Every field the verify reads, checked up front: a missing one otherwise
    // surfaces as a cast error, which reads like a bug rather than the refusal
    // it is. Which fields those are depends on the wrapper shape — the JWS
    // wrapper carries its algorithm and signer claim inside `protected`.
    final wrapperFields = envelopeVersionOf(envelope) == jwsEnvelopeVersion
        ? ['signature', 'protected', 'payload']
        : ['signature', 'enrollmentId', 'signingAlgo', 'hashingAlgo'];
    if (wrapperFields.any((field) => envelope[field] is! String)) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner carries no APKAM signature, so the '
          'key sealed to would be only as trustworthy as the server that '
          'served it');
    }

    await _signer.verifyEnvelopeSignature(envelope, signerAtSign: owner);

    final advertised = envelopePayloadOf(envelope);
    if (advertised is! Map) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner has a signature over a payload that '
          'is not an advertisement');
    }
    // Absent means the pre-2026-08-06 shape, which is this one without the
    // field — accept it. A version this build has no code for is refused
    // rather than read as if it were v1, because the fields it would go on to
    // parse might mean something else entirely.
    final version = advertised['v'];
    if (version != null && version != nskeyAdvertisementVersion) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner declares payload version $version, '
          'which this build has no code for — refusing rather than reading it '
          'as version $nskeyAdvertisementVersion');
    }

    // Absent means the pre-2026-08-07 shape, which was X-Wing by construction
    // — it was the only KEM that existed. An algorithm this build cannot
    // resolve is refused rather than guessed at: encapsulating under the wrong
    // KEM produces a conveyance the owner can never open, and the failure
    // would surface on their side with nothing to point at.
    final declaredAlg = advertised['alg'] ?? SecretSharingAlgos.xWing;
    if (declaredAlg is! String ||
        SecretSharingAlgos.kemFor(declaredAlg) == null) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner names key-establishment algorithm '
          '"$declaredAlg", which this build cannot encapsulate to');
    }

    final publicKey =
        Uint8List.fromList(base64Decode(advertised['publicKey'] as String));
    final nskeyKid = advertised['nskeyKid'] as String;
    if (nskeyKid != nskeyKidOf(publicKey)) {
      // A kid that does not name its own key would let a rotation be reported
      // as a generation the recipient never minted, so a conveyance sealed to
      // it could never be opened.
      throw AtSigningVerificationException(
          'the advertised nskey for $owner names a kid that is not the digest '
          'of the key it carries');
    }
    // Absent means the pre-suites shape, which supported exactly the one
    // construction that existed then. Entries this build does not know are
    // kept — the list is the OWNER's statement about what it can open, and a
    // newer owner may name a construction we simply do not use yet.
    final declaredSuites = advertised['suites'];
    return (
      nskeyKid: nskeyKid,
      publicKey: publicKey,
      alg: declaredAlg,
      suites: declaredSuites is List
          ? declaredSuites.whereType<String>().toList()
          : legacyNskeySuites,
    );
  }
}

/// An [NskeyKeyRing] that publishes the owner's nskey and discovers other
/// atSigns' by `plookup`.
///
/// Own privates are held in memory here; conveying them per-APKAM over the
/// secret-sharing substrate is SS-4's job, and when it lands it supplies them
/// instead of [mintAndPublish].
class PublishedNskeyKeyRing implements NskeyKeyRing {
  final AtClient _atClient;
  final AdvertisedKeyVerifier verifier;

  /// How long a fetched advertisement is trusted before it is re-fetched.
  ///
  /// This is the lever on how long a rotation can go unnoticed. A sender never
  /// sees a recipient's decapsulation fail, so re-fetching is the *only* way it
  /// learns the recipient rotated — and a sender still sealing to a superseded
  /// generation hands a revoked enrollment a key it can still open. Total
  /// exposure is this window plus one content-key lifetime.
  ///
  /// It is a window rather than a check per write because `ensureCurrent` runs
  /// on every `put`: fetching each time would put a round trip to the
  /// recipient's atServer on the write path and break offline writes.
  final Duration advertisementTtl;

  /// How far past [advertisementTtl] a *failed* re-fetch may keep serving the
  /// advertisement it already has, before this stops answering for the
  /// destination at all.
  ///
  /// Without a bound this fails open: a re-fetch that keeps erroring — an
  /// unreachable atServer, a network partition — would serve the cached
  /// generation forever, and the stated exposure of "one TTL plus one content
  /// key" would be unbounded in exactly the case that matters, since a peer
  /// that has rotated *because of a revocation* is the peer a sender most needs
  /// to stop sealing to. A short grace absorbs an ordinary blip; past it, the
  /// write fails rather than silently handing a revoked enrollment a key it can
  /// still open.
  final Duration advertisementStaleGrace;

  PublishedNskeyKeyRing(
    this._atClient, {
    AdvertisedKeyVerifier? verifier,
    this.advertisementTtl = const Duration(minutes: 15),
    this.advertisementStaleGrace = const Duration(minutes: 15),
    NskeyMintLock? mintLock,
    this.privateFiling,
    Future<void> Function(String namespace, String secretName)?
        requestConveyance,
  })  : verifier = verifier ?? ApkamSignedAdvertisedKeys(_atClient),
        mintLock = mintLock ?? NskeyMintLock(_atClient),
        _requestConveyance = requestConveyance,
        _signer = AtClientEnvelopeSigner(_atClient);

  /// Broadcasts a pull request for a missing own-atSign private, when
  /// [privateHalf] comes up empty for a generation this atSign has published.
  ///
  /// This is the read path's half of the self-heal ruling
  /// (`docs/projects/pq/decisions.md` 38): a value can arrive before the
  /// private that opens it — a new enrollment that missed the mint-time push
  /// is the ordinary case, not an edge — and the reader asks rather than
  /// failing forever. The request is store-and-forward: any current holder
  /// answers when it next runs, the answer is filed by the arrival path, and
  /// the next read finds it.
  ///
  /// Injectable so tests observe the ask without a live substrate; null wires
  /// the real one lazily (constructing it eagerly would pull the substrate
  /// into every fixture that only ever reads).
  final Future<void> Function(String namespace, String secretName)?
      _requestConveyance;

  /// Generations already asked for, so a burst of failed reads collapses to
  /// one broadcast. Per instance and never expiring: the answer is filed
  /// durably when it arrives, and a fresh client (or the next start) asks
  /// again if it never did.
  final Set<String> _askedConveyance = {};

  /// Serialises minting between this atSign's own enrollments.
  final NskeyMintLock mintLock;

  /// Where a minted private is made durable **before** its public half is
  /// published. Null keeps privates in memory only — a fixture posture, since
  /// a published key whose private did not survive the process leaves senders
  /// sealing to something nobody can open.
  final NskeyPrivateFiling? privateFiling;

  /// Signs this atSign's own advertisements. A recipient that cannot check who
  /// generated the key it is about to seal to has no protection left but the
  /// atServer's word, so publishing unsigned is not an option the ring offers.
  final AtClientEnvelopeSigner _signer;

  final Map<String, NskeyAdvertisement> _ownCurrent = {};

  /// Record a generation as this client's own, without minting one.
  ///
  /// [mintAndPublish] is the production caller; this exists so a test can put a
  /// ring into the "already minted" state without a remote secondary.
  @visibleForTesting
  void rememberOwn(
          String owner, String namespace, NskeyAdvertisement advertisement) =>
      _ownCurrent[_scope(owner, namespace)] = advertisement;
  final Map<String, NskeyDecapsulationKey> _ownPrivates = {};
  final Map<String, ({NskeyAdvertisement advertisement, DateTime fetchedAt})>
      _remote = {};

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  static String _generation(String owner, String namespace, String kid) =>
      '${_scope(owner, namespace)}|$kid';

  /// Mint a generation for `(currentAtSign, namespace)` and publish its public
  /// half immediately.
  ///
  /// Called again for the same namespace this is a **rotation**: the new
  /// generation becomes current and the previous private is retained, so
  /// conveyances sealed to it still open.
  Future<NskeyAdvertisement> mintAndPublish(String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final minted = await mintLock.withLock(
        owner, namespace, () => _mint(owner, namespace));
    if (minted != null) return minted;

    // Another enrollment is minting. Re-read rather than wait: whatever it is
    // doing ends with an advertisement published, and this client needs that
    // one — minting a second would rotate the first out from under any peer
    // that had already fetched it.
    final published = await currentPublic(owner, namespace);
    if (published != null) return published;
    throw StateError(
        'another enrollment holds the mint lock for $owner:$namespace but has '
        'published no advertisement yet');
  }

  /// Rotates `(currentAtSign, namespace)` onto a fresh generation: mints the
  /// next keypair, **overwrites** the published advertisement with it, and
  /// keeps every private this client already held.
  ///
  /// Retention is by construction rather than by policy — privates are filed
  /// per `nskeyKid` and nothing removes them — which is what keeps retained
  /// `__ck` records sealed to an earlier generation readable. Rotation
  /// replaces the key; it does not decrypt or re-encrypt the past.
  ///
  /// Differs from [mintAndPublish] in one way, and it is the way that matters:
  /// **losing the mint lock is a failure here, not a resolution.** A cold-start
  /// mint that loses the race adopts the winner's key and is done — the atSign
  /// has a key, which is all that was wanted. A rotation that adopts what it
  /// finds has rotated nothing while reporting success, leaving the enrollment
  /// the caller was rotating away from holding the live generation. Since
  /// rotation is the revocation lever, that failure is silent *and* is the one
  /// case where silence costs exactly what the operation was for.
  ///
  /// Rotating a namespace with no published key throws for the same reason: it
  /// is a cold-start mint wearing a rotation's name, and a caller that meant to
  /// supersede a generation should hear that there was none.
  Future<NskeyAdvertisement> rotate(String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final superseded = await currentPublic(owner, namespace);
    if (superseded == null) {
      throw StateError(
          'nothing to rotate for $owner:$namespace — no nskey is published '
          'there, so this is a cold-start mint rather than a rotation');
    }

    final rotated = await mintLock.withLock(
        owner, namespace, () => _mint(owner, namespace));
    if (rotated == null) {
      throw StateError(
          'another enrollment holds the mint lock for $owner:$namespace, so '
          'this rotation did not happen; retry once it releases. Reporting '
          'success here would leave the excluded enrollment holding the live '
          'generation');
    }
    _logger.info('Rotated $owner:$namespace from ${superseded.nskeyKid} to '
        '${rotated.nskeyKid}; the superseded private is retained so records '
        'sealed to it still open');
    return rotated;
  }

  Future<NskeyAdvertisement> _mint(String owner, String namespace) async {
    final String keyAlgo =
        _atClient.getPreferences()?.keyEstablishmentAlgo ??
            SecretSharingAlgos.xWing;
    final AtKemAlgorithm? kem = SecretSharingAlgos.kemFor(keyAlgo);
    if (kem == null) {
      throw StateError(
          'cannot mint an nskey for $owner:$namespace under "$keyAlgo" — this '
          'build has no implementation for it. Supported: '
          '${SecretSharingAlgos.keyAlgos}');
    }

    // The SEED is what is filed and what everything re-derives from; for
    // ML-KEM the decapsulation key is expanded and cannot be turned back into
    // a public half, so filing it would leave the generation unopenable after
    // a restart.
    final seed = NskeySeed(kem.newSeed());
    final pair = await kem.keyPairFromSeed(seed.bytes);
    final advertisement = (
      nskeyKid: nskeyKidOf(pair.publicKey),
      publicKey: pair.publicKey,
      alg: keyAlgo,
      // Derived from the key, never stated from the build's own list: what
      // this generation can open is fixed by the KEM it is a key for.
      suites: SecretSharingAlgos.openableSuitesFor(keyAlgo),
    );

    final advertisementKey = nskeyAdvertisementKey(owner, namespace);
    // Signed with this client's APKAM keypair, so a peer can tell the key came
    // from an enrollment of this atSign rather than from whoever served it.
    // The APKAM public half must already be published, or the peer has nothing
    // to check the signature against.
    // Durable BEFORE the advertisement goes out. A key published ahead of its
    // private leaves every sender sealing to something nobody can open, and no
    // later repair recovers what was written in between — rotation replaces the
    // key, it does not decrypt the past.
    final filing = privateFiling;
    if (filing != null) {
      final stored = await filing.store(
        namespace: namespace,
        nskeyKid: advertisement.nskeyKid,
        seed: seed,
        keyAlgo: keyAlgo,
      );
      if (!stored) {
        throw StateError(
            'could not store the nskey private for $owner:$namespace, so its '
            'public half is deliberately not published');
      }
    }

    await _signer.publishPublicSigningKey();
    final payload = await _signer.wrapAndSignAndJsonEncode({
      'v': nskeyAdvertisementVersion,
      'nskeyKid': advertisement.nskeyKid,
      'publicKey': base64Encode(advertisement.publicKey),
      // Without this a sender has an opaque byte string and no way to tell
      // which KEM it belongs to.
      'alg': keyAlgo,
      // And without this it cannot tell which *construction* the owner can
      // unwrap, so a new one could only ever arrive by upgrading every reader
      // first — release-ordering agility rather than negotiated agility.
      'suites': advertisement.suites,
    });

    // Straight to the atServer first: an advertisement is only useful once a
    // *peer* can fetch it, and going through the local-first put would leave it
    // unpublished until the next sync.
    await _atClient.getRemoteSecondary()!.executeVerb(
        UpdateVerbBuilder()
          ..atKey = advertisementKey
          ..value = payload,
        sync: true);

    // …then locally, so the owner's own clients hold it across restarts without
    // a round trip. A `public:__` key carries a real commit id, so the two
    // converge rather than diverging.
    await _atClient.put(advertisementKey, payload);

    _ownCurrent[_scope(owner, namespace)] = advertisement;
    _ownPrivates[_generation(owner, namespace, advertisement.nskeyKid)] =
        NskeyDecapsulationKey(pair.secretKey);
    return advertisement;
  }

  @override
  Future<NskeyAdvertisement?> currentPublic(
      String owner, String namespace) async {
    // What this client minted itself, if anything — held in memory so the
    // common case costs nothing. Falling through when it has minted *nothing*
    // is the point: another of the owner's enrollments, or this one after a
    // restart, holds no `_ownCurrent` entry while the advertisement sits on the
    // owner's own atServer. Returning null here would report a published
    // namespace as cold start, and a client that "fixed" that by minting would
    // rotate the key out from under every peer that had already fetched it.
    //
    // The lookup below serves the owner's own advertisement exactly as it
    // serves a peer's, signature check included — which is what makes the
    // design's "one verify path, same-atSign and cross-atSign" true rather than
    // aspirational.
    final own = _ownCurrent[_scope(owner, namespace)];
    if (own != null) return own;

    final scope = _scope(owner, namespace);
    final cached = _remote[scope];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < advertisementTtl) {
      return cached.advertisement;
    }

    final String payload;
    try {
      final value =
          await _atClient.get(nskeyAdvertisementKey(owner, namespace));
      if (value.value == null) return _staleOrNothing(cached);
      payload = value.value as String;
    } catch (_) {
      // No advertisement: under eager publication that means the recipient has
      // never used this namespace, which is the cold-start case. Keep any
      // previously-fetched one rather than losing a working key to a blip —
      // but only for as long as the grace allows.
      return _staleOrNothing(cached);
    }

    final advertisement = await verifier.verify(owner, payload);
    _remote[scope] = (advertisement: advertisement, fetchedAt: DateTime.now());
    return advertisement;
  }

  /// Serve a cached advertisement whose re-fetch just failed, but only inside
  /// the grace window — beyond it, answer with nothing so the write fails
  /// loudly rather than sealing to a generation that may have been rotated
  /// away from.
  NskeyAdvertisement? _staleOrNothing(
      ({NskeyAdvertisement advertisement, DateTime fetchedAt})? cached) {
    if (cached == null) return null;
    final age = DateTime.now().difference(cached.fetchedAt);
    if (age <= advertisementTtl + advertisementStaleGrace) {
      return cached.advertisement;
    }
    _logger.warning(
        'the advertised nskey last fetched ${age.inMinutes}m ago cannot be '
        'refreshed and is past its stale grace — refusing to keep sealing to '
        'it, because a peer that rotated on a revocation is exactly the peer '
        'this must stop trusting');
    return null;
  }

  @override
  Future<NskeyDecapsulationKey?> privateHalf(
      String owner, String namespace, String nskeyKid) async {
    // Memory first — this process minted it, or has already read it once.
    final held = _ownPrivates[_generation(owner, namespace, nskeyKid)];
    if (held != null) return held;

    // Then the durable copy, which is what a restart or another of this
    // atSign's enrollments actually has. `owner` is the nskey owner, and only
    // this atSign's own privates are ever filed, so a request for a peer's
    // private has nothing to find here and correctly returns null.
    if (owner != _atClient.getCurrentAtSign()) return null;
    final filed = await privateFiling?.read(namespace, nskeyKid);
    if (filed != null) {
      _ownPrivates[_generation(owner, namespace, nskeyKid)] = filed;
      return filed;
    }

    // A generation of our own atSign that we do not hold: ask the other
    // enrollments for it rather than failing forever. Fire-and-forget — the
    // caller still gets its miss (and its typed error), and the answer is
    // filed by the arrival path so a later read finds it.
    _askForMissingPrivate(namespace, nskeyKid);
    return null;
  }

  void _askForMissingPrivate(String namespace, String nskeyKid) {
    final ask = _requestConveyance;
    if (ask == null) return;
    // One broadcast per generation per instance: every conveyance of a synced
    // backlog fails through here in a burst, and N identical requests buy
    // nothing the first did not.
    if (!_askedConveyance.add(_generation('own', namespace, nskeyKid))) return;

    final secretName = '${NskeyPrivateFiling.secretNamePrefix}$nskeyKid';
    unawaited(ask(namespace, secretName).then((_) {
      _logger.info('Asked the other enrollments for the nskey private '
          '$namespace:$nskeyKid; the answer is filed when a holder replies');
    }).catchError((Object e) {
      // Retried naturally: the next instance (or the next start's sweep) asks
      // again, and the miss itself is already surfacing as a typed error.
      _logger.info('Could not request the missing nskey private for '
          '$namespace:$nskeyKid: $e');
    }));
  }
}
