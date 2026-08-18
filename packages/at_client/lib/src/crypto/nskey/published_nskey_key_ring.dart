import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/crypto/crypto.dart'
    show FiledNskeyPrivate, SignalsPrivateFiling;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/mint_lock.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyEntryStatus;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
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
    final SignedEnvelope envelope;
    try {
      // fromJson is the structural check: a payload string and at least one
      // signatures entry carrying a readable protected header. Doing it here
      // rather than letting a member surface as a cast error keeps a
      // malformed advertisement a refusal rather than something that reads
      // like a bug.
      envelope = SignedEnvelope.fromJson(jsonDecode(payload) as Map);
    } on FormatException catch (e) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner is not JSON: ${e.message}');
    } on AtSigningVerificationException catch (e) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner carries no APKAM signature, so the '
          'key sealed to would be only as trustworthy as the server that '
          'served it: ${e.message}');
    }

    await _signer.verifyEnvelopeSignature(envelope,
        signerAtSign: owner, expecting: EnvelopeType.nskeyRing);

    final NskeyAdvertisement advertisement;
    try {
      advertisement = NskeyAdvertisement.fromPayload(envelope.payload);
    } on FormatException catch (e) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner ${e.message}');
    }

    // An entry naming an algorithm this build does not implement is SKIPPED,
    // not refused: that is what lets an owner advertise a new KEM beside an old
    // one without cutting off every peer that predates it. What is refused is
    // an advertisement with nothing left after the skipping — a reader that
    // understands no entry refuses outright rather than falling back to a key
    // it derived some other way.
    //
    // Every entry this build DOES understand is checked, including ones it will
    // not choose. A malformed entry beside a good one is a signal about the
    // advertisement as a whole, and sealing to the good one while ignoring it
    // would be reading past evidence that the owner's publishing is broken.
    var understood = 0;
    var sealable = 0;
    for (final key in advertisement.keys) {
      if (SecretSharingAlgos.kemFor(key.alg) == null) continue;
      understood++;
      // A retired entry is still checked — it has to be well formed to be
      // believed at all — but it is not something to seal to, so it does not
      // count towards this advertisement having an encapsulation target.
      if (key.status == KeyEntryStatus.active) sealable++;
      // Length before anything is sealed to it. A kid is the digest of
      // whatever bytes are carried, so it matches a forged key as readily as a
      // real one and the check below cannot see a wrong-length key at all.
      // Without this the first sign of trouble is inside the KEM, one seal
      // later, on a stack naming neither the owner nor the advertisement.
      final expected = SecretSharingAlgos.publicKeyLengthFor(key.alg);
      if (expected == null) {
        // kemFor accepted this algorithm a few lines up, so the two switches
        // have drifted. Refuse rather than let the length check quietly not
        // happen.
        throw AtSigningVerificationException(
            'the advertised nskey for $owner names "${key.alg}", which this '
            'build can encapsulate to but cannot state a key length for');
      }
      if (key.pubBytes.length != expected) {
        throw AtSigningVerificationException(
            'the advertised nskey for $owner carries a ${key.pubBytes.length}-'
            'byte key for "${key.alg}", which takes $expected bytes');
      }
      if (key.kid != nskeyKidOf(key.pubBytes)) {
        // A kid that does not name its own key would let a rotation be reported
        // as a generation the recipient never minted, so a conveyance sealed to
        // it could never be opened.
        throw AtSigningVerificationException(
            'the advertised nskey for $owner names a kid that is not the digest '
            'of the key it carries');
      }
    }
    if (understood == 0) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner offers only key-establishment '
          'algorithms this build cannot encapsulate to '
          '(${advertisement.keys.map((k) => '"${k.alg}"').join(', ')}) — '
          'refusing rather than sealing under one it did not name');
    }
    if (sealable == 0) {
      // A separate refusal from the one above because it is a different
      // situation for whoever reads the log: the algorithms are fine and the
      // owner has withdrawn every key from new use. This record's writer never
      // does that — it overwrites on rotation — so the reader is looking at
      // something a newer or a foreign implementation published.
      throw AtSigningVerificationException(
          'the advertised nskey for $owner retires every key this build can '
          'encapsulate to, so it names nothing to seal to now');
    }
    return advertisement;
  }
}

/// An [NskeyKeyRing] that publishes the owner's nskey and discovers other
/// atSigns' by `plookup`.
///
/// Own privates are held in memory here; conveying them per-APKAM over the
/// secret-sharing substrate is SS-4's job, and when it lands it supplies them
/// instead of [mintAndPublish].
class PublishedNskeyKeyRing implements NskeyKeyRing, SignalsPrivateFiling {
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
    MintLock? mintLock,
    this.lockTtl = mintLockTtl,
    NskeyPrivateFiling? privateFiling,
    Future<void> Function(String namespace, String secretName)?
        requestConveyance,
  })  : verifier = verifier ?? ApkamSignedAdvertisedKeys(_atClient),
        mintLock = mintLock ?? MintLock(_atClient),
        privateFiling = privateFiling ?? _filingFor(_atClient),
        _requestConveyance = requestConveyance,
        _signer = AtClientEnvelopeSigner(_atClient);

  /// The filing a ring builds for itself when its caller named none.
  ///
  /// A client that was handed an `AtKeysIo` has already said where its key
  /// material belongs, and an nskey private is the one kind that cannot be
  /// re-derived or re-fetched: minting it anywhere else discards it. So the
  /// client's own key source is the default, and null means the client has
  /// none — not that this ring should keep privates in memory beside a
  /// keyfile that was there all along.
  ///
  /// Composed here rather than shared with whatever else the client built, so
  /// a ring is constructible from an `AtClient` alone. Two filings over one
  /// keyfile are safe — `AtKeysIo.update` serialises the read-mutate-write
  /// across processes, and [NskeyPrivateFiling.store] is idempotent — but
  /// they carry separate `privatesFiled` streams, so a caller that needs a
  /// filing's *events* must pass the instance it is listening to.
  static NskeyPrivateFiling? _filingFor(AtClient atClient) {
    final keysIo = atClient.atKeysIo;
    if (keysIo == null) return null;
    final atSign = atClient.getCurrentAtSign();
    if (atSign == null) return null;
    return NskeyPrivateFiling(keysIo: keysIo, atSign: atSign);
  }

  /// Broadcasts a pull request for a missing own-atSign private, when
  /// [privateHalf] comes up empty for a generation this atSign has published.
  ///
  /// This is the read path's half of the self-heal ruling
  /// (`docs/projects/pq/decisions.md` 38): a value can arrive before the
  /// private that opens it — a new enrollment that missed the mint-time push
  /// is the ordinary case, not an edge — and the reader asks rather than
  /// failing forever. The request is store-and-forward: any current holder
  /// answers when it next runs.
  ///
  /// ⚠️ **Null means this ring does not ask at all**, and that is the one
  /// piece of a client's wiring [privateFiling] does not derive for it: a ring
  /// built from an `AtClient` alone files what it mints and still reads a
  /// generation it holds nothing for as a permanent miss. Supplying it is
  /// `PqClientBootstrap`'s job, and the supplier owns waiting for the answer
  /// and filing it — see the warning on [_askForMissingPrivate], which is
  /// where the arrival path this used to claim turned out not to exist.
  final Future<void> Function(String namespace, String secretName)?
      _requestConveyance;

  /// Generations already asked for, so a burst of failed reads collapses to
  /// one broadcast. Per instance and never expiring: the answer is filed
  /// durably when it arrives, and a fresh client (or the next start) asks
  /// again if it never did.
  final Set<String> _askedConveyance = {};

  /// Serialises minting between this atSign's own enrollments.
  final MintLock mintLock;

  /// How long this ring holds a namespace's mint lock once it has taken it.
  ///
  /// Expiry is the only thing that releases the lock, so this is the **cooldown
  /// before another election may be held for the same namespace** — and a
  /// rotation attempted inside it is refused rather than queued. That is the
  /// intended behaviour, not a window to tune away: a rotation that adopted
  /// what it found would have rotated nothing while reporting success.
  ///
  /// A parameter rather than the bare constant because the value is a policy
  /// about how long an election may take, and a caller with a different one —
  /// a live test that cannot wait [mintLockTtl] between a mint and the rotation
  /// it is exercising, an operator on a very slow device — should be able to
  /// state it rather than fork the composer.
  final Duration lockTtl;

  /// Where a minted private is made durable **before** its public half is
  /// published.
  ///
  /// Defaults to a filing over the client's own `AtKeysIo` — see [_filingFor].
  /// It is null only for a client that has no key source at all, and [_mint]
  /// says so at `severe` when it mints anyway: a published key whose private
  /// did not survive the process leaves every sender sealing to something
  /// nobody can open, and no later repair recovers what was written in
  /// between. Pass an instance to share one filing's `privatesFiled` events
  /// with the rest of a client's wiring.
  final NskeyPrivateFiling? privateFiling;

  @override
  Stream<FiledNskeyPrivate> get privatesFiled =>
      privateFiling?.privatesFiled ?? const Stream<FiledNskeyPrivate>.empty();

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
  /// Drop what this ring cached for `(owner, namespace)`, forcing the next
  /// read to go to the atServer.
  ///
  /// For tests that change a **peer's** published advertisement out from under
  /// a client and need it to notice inside [advertisementTtl]. In production
  /// the window is deliberate — `ensureCurrent` runs on every put, and
  /// re-fetching each time would put a round trip to the recipient's atServer
  /// on the write path — so nothing here shortens it. A test asserting what a
  /// client does when a peer's advertisement is substituted is asserting
  /// something about the FETCH, and it cannot observe a fetch that a cache
  /// legitimately answered.
  @visibleForTesting
  void forgetRemote(String owner, String namespace) =>
      _remote.remove(_scope(owner, namespace));

  final Map<String, NskeyDecapsulationKey> _ownPrivates = {};
  final Map<String, ({NskeyAdvertisement advertisement, DateTime fetchedAt})>
      _remote = {};

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  static String _generation(String owner, String namespace, String kid) =>
      '${_scope(owner, namespace)}|$kid';

  /// Mint a generation for `(currentAtSign, namespace)` and publish its public
  /// half immediately.
  ///
  /// This is the cold-start mint. Called again for the same namespace it
  /// usually does produce a new current generation, retaining the previous
  /// private so conveyances sealed to it still open — but **it is not the
  /// rotation lever, and must not be used as one**. Losing the mint lock here
  /// is resolved by adopting the winner's advertisement and returning it, so a
  /// second call can succeed having rotated nothing. [rotate] exists for that
  /// reason and treats the same race as a failure; see its doc for why the
  /// difference is the one that matters.
  Future<NskeyAdvertisement> mintAndPublish(String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final minted = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl),
        (lease) => _mintUnlessPublished(owner, namespace, lease),
        // Safe here and nowhere else in this file: the critical section reads
        // what is published and adopts it, so an enrollment meeting the lock
        // it took a moment ago re-reads rather than minting a second key.
        // `rotate` takes the same lock WITHOUT this, because the cooldown
        // binding rotation is deliberate.
        ownLockIsNotContention: true);
    if (minted != null) return minted;

    // Another enrollment won the election. Re-read once rather than wait: the
    // winner ends with an advertisement published, and this client needs that
    // one — minting a second would rotate the first out from under any peer
    // that had already fetched it.
    final published = await publishedAdvertisement(owner, namespace);
    if (published != null) {
      await _warnIfPrivateMissing(owner, namespace, published, 'read as a '
          'loser of the mint election');
      return published;
    }

    // Nothing published, and this client may not mint: the loser of an
    // election never does, or the election bought nothing. Failing here is
    // deliberate — a `put` waiting on a namespace key fails loudly instead of
    // hanging on another device that may have crashed mid-mint, and the retry
    // is the next client start, which is where minting is triggered from
    // anyway.
    throw StateError(
        'another enrollment holds the mint lock for $owner:$namespace and has '
        'published no advertisement yet, so this client has no namespace key '
        'to seal to and must not mint a second one; retry after the lock\'s '
        'ttl elapses');
  }

  /// [_mint], unless a sibling enrollment published while this client was
  /// taking the lock.
  ///
  /// This re-read is what the lock is worth taking for. Every check made before
  /// it — `NskeySeeding.seed`'s, or a caller's own — ran outside the lock, so a
  /// winner that published in the window between that check and this client
  /// winning the race is invisible to all of them. The advertisement record is
  /// **mutable**: minting on that stale absence overwrites the winner's key,
  /// and every peer that had already fetched it goes on sealing to a generation
  /// its owner will never look for.
  ///
  /// Adopting is the right answer only because this is the cold-start mint,
  /// where the atSign holding *a* key is the whole of what was wanted. [rotate]
  /// runs [_mint] directly for exactly that reason: a rotation that adopted
  /// what it found would have rotated nothing while reporting success, and
  /// rotation is the revocation lever.
  /// Says so when this client adopts an advertisement it cannot open with.
  ///
  /// An advertisement is two halves and only one of them is published. A
  /// client that adopts somebody else's can seal *outward* with it
  /// immediately, and cannot open anything sealed *to* it until the private
  /// arrives — so the gap surfaces later, at an unrelated read, as
  /// [NskeyPrivateUnavailableException] naming a generation with nothing to
  /// say where it came from. This names it at the point it opens.
  ///
  /// **A warning rather than a refusal, deliberately.** An enrollment that has
  /// legitimately just joined holds no private until the conveyance reaches
  /// it, so failing here would break a first start to report a state that is
  /// expected and self-correcting; the read path already throws a typed
  /// exception the notification service parks and re-drives. What was missing
  /// was any record of the adoption that caused it.
  Future<void> _warnIfPrivateMissing(String owner, String namespace,
      NskeyAdvertisement published, String how) async {
    if (owner != _atClient.getCurrentAtSign()) return;
    if (await privateHalf(owner, namespace, published.nskeyKid) != null) return;
    _logger.warning(
        'Adopted nskey generation ${published.nskeyKid} for $owner:$namespace '
        '($how) and hold no private half for it: this client can seal to it '
        'but cannot open anything sealed to it until the private is conveyed '
        'or healed');
  }

  Future<NskeyAdvertisement> _mintUnlessPublished(
      String owner, String namespace, MintLease lease) async {
    final published = await publishedAdvertisement(owner, namespace);
    if (published == null) return _mint(owner, namespace, lease);
    _logger.info(
        'Not minting an nskey for $owner:$namespace: ${published.nskeyKid} was '
        'published between the decision to mint and this client taking the '
        'lock, so it is adopted rather than overwritten');
    await _warnIfPrivateMissing(owner, namespace, published, 'adopted');
    return published;
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
  ///
  /// Returns both generations, so a caller that must name what it superseded —
  /// which every rotation report does — takes it from the read this already
  /// made rather than repeating it. The two reads were the same question asked
  /// of the atServer twice, one round trip apart, with nothing able to act on a
  /// difference between the answers.
  Future<({NskeyAdvertisement rotated, NskeyAdvertisement superseded})> rotate(
      String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final superseded = await publishedAdvertisement(owner, namespace);
    if (superseded == null) {
      throw StateError(
          'nothing to rotate for $owner:$namespace — no nskey is published '
          'there, so this is a cold-start mint rather than a rotation');
    }

    final rotated = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl),
        (lease) => _mint(owner, namespace, lease));
    if (rotated == null) {
      throw StateError(
          'another enrollment holds the mint lock for $owner:$namespace, so '
          'this rotation did not happen; retry once its ttl elapses. Reporting '
          'success here would leave the excluded enrollment holding the live '
          'generation');
    }
    _logger.info('Rotated $owner:$namespace from ${superseded.nskeyKid} to '
        '${rotated.nskeyKid}; the superseded private is retained so records '
        'sealed to it still open');
    return (rotated: rotated, superseded: superseded);
  }

  Future<NskeyAdvertisement> _mint(
      String owner, String namespace, MintLease lease) async {
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
    final advertisement = NskeyAdvertisement.single(
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
    } else {
      // No filing and no key source to build one from, so this generation is
      // published with its private held in memory and nowhere else. Said at
      // `severe` and not refused: a fixture may legitimately mint into memory,
      // and refusing here would also refuse the client that has genuinely been
      // given nowhere to write. But it is the loudest failure this class has —
      // an unwritable `AtKeysIo` already shouts one level down, and holding no
      // key source at all is the worse of the two.
      _logger.severe('Minting the nskey for $owner:$namespace with nowhere to '
          'file its private: this client has no AtKeysIo and no filing was '
          'supplied, so the private is held in memory only. Peers will seal to '
          'the published key, and every value they seal becomes permanently '
          'unreadable when this process ends');
    }

    await _signer.publishPublicSigningKey();
    // One codec, both directions. Each entry carries its own `alg`, without
    // which a sender has an opaque byte string and no way to tell which KEM it
    // belongs to; `suites` says which *construction* the owner can unwrap,
    // without which a new one could only ever arrive by upgrading every reader
    // first — release-ordering agility rather than negotiated agility.
    final payload =
        await _signer.wrapAndSignAndJsonEncode(advertisement.toPayload(),
            type: EnvelopeType.nskeyRing);

    // The last thing before the write, and deliberately not earlier: what
    // matters is whether the lease is still good at the moment of publishing,
    // and everything above it — a keygen, a keyfile write, a signature — can
    // take arbitrarily long on a suspended or loaded device.
    //
    // A slow winner whose lease has run out has to abandon rather than publish,
    // because by then another enrollment has legitimately won the next election
    // and is minting. The election bounds when enrollments *attempt*, not how
    // long the winner *takes*, so without this the "only one eventually mints"
    // requirement fails with every other part correct. The private that was
    // just filed is harmless: nothing points at it, and the next mint files its
    // own.
    if (lease.isSpent) {
      throw StateError(
          'the mint lock for $owner:$namespace expired while this client was '
          'minting, so its advertisement is deliberately not published — '
          'another enrollment may already hold the lock and be publishing its '
          'own. Retry: the next attempt takes a fresh lock');
    }

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

  /// What `(owner, namespace)` has published **on the atServer**, fetched with
  /// both caches skipped.
  ///
  /// [currentPublic] answers a different question and must keep answering it
  /// local-first: it is the sender's read, reached from `CkManager.ensureCurrent`
  /// on every `put`, so a round trip there would sit on the write path and break
  /// offline writes. This is the mint path's read, where the question is not
  /// "what may I seal to" but "has another of this atSign's enrollments already
  /// published a generation" — and a sibling's publication reaches local storage
  /// only when sync gets round to it. That lag is the window in which a second
  /// mint overwrites the first.
  ///
  /// Both caches are skipped deliberately. `_ownCurrent` holds what *this*
  /// client minted, and `_remote` what it fetched up to [advertisementTtl] ago;
  /// neither can hold a generation a sibling published a moment ago, so a mint
  /// that trusted either would be minting on a stale absence.
  ///
  /// Null means the atServer says there is none. Any other failure throws: a
  /// mint must not read an unreachable atServer as a cold start, because that
  /// is the reading that publishes a second key.
  ///
  /// ⚠️ **One exception, and only at this atSign's own address: an
  /// advertisement that does not verify also reads as none.** For a peer's
  /// address a failed verification is the substitution defence doing its job
  /// and must propagate — sealing to a key nobody proved the peer minted is
  /// the attack the signature exists to stop. For our own, the same failure
  /// means the record we are responsible for is unusable, and the only client
  /// that can replace it is this one. Throwing there left it unreplaceable by
  /// anybody: both mint paths read through here, so a corrupt or hostile write
  /// to our own advertisement could never be minted over. Returning null lets
  /// the mint proceed and overwrite it, which is the whole point of holding
  /// the key material.
  Future<NskeyAdvertisement?> publishedAdvertisement(
      String owner, String namespace) async {
    final AtValue value;
    try {
      value = await _atClient.get(
        nskeyAdvertisementKey(owner, namespace),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } on KeyNotFoundException {
      return null;
    } on AtKeyNotFoundException {
      return null;
    }
    if (value.value == null) return null;

    final NskeyAdvertisement advertisement;
    try {
      advertisement = await verifier.verify(owner, value.value as String);
    } on Object catch (e) {
      if (owner != _atClient.getCurrentAtSign()) rethrow;
      // Warning, not info: something wrote an advertisement to our own address
      // that we cannot verify, and the next line replaces it. That is the
      // right outcome and still worth a record of having happened.
      _logger.warning(
          'Our own advertisement at ${nskeyAdvertisementKey(owner, namespace)} '
          'does not verify ($e) — treating it as unpublished so a mint can '
          'replace it');
      return null;
    }
    // Kept, because a verified fetch straight from the atServer is strictly
    // fresher than whatever the sender-side cache holds: the next
    // [currentPublic] for this scope answers from it instead of paying for a
    // round trip of its own.
    _remote[_scope(owner, namespace)] =
        (advertisement: advertisement, fetchedAt: DateTime.now());
    return advertisement;
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
    // caller still gets its miss (and its typed error).
    //
    // ⚠️ **The asking side does not file.** This used to say "the answer is
    // filed by the arrival path so a later read finds it", and there is no such
    // arrival path mid-session: nothing subscribes to `receivedSecrets` to file
    // an nskey private, and `NskeyPrivateFiling.filePending` runs at start.
    // Whoever supplies `requestConveyance` owns waiting for the answer and
    // filing it — `PqClientBootstrap` does, and without that the heal repaired
    // the client only at its next start.
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
