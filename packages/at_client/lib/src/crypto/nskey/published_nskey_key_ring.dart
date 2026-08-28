import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:typed_data' show Uint8List;

import 'package:at_client/src/crypto/crypto.dart'
    show FiledNskeyPrivate, SignalsPrivateFiling;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/mint_lock.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart';
import 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/mixins/at_client_envelope_signer.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show EnvelopeType, SignedEnvelope;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart' show experimental, visibleForTesting;

final _logger = AtSignLogger('PublishedNskeyKeyRing');

/// Asks this atSign's other enrollments for one missing nskey private, then
/// waits for a holder to answer and **files** the answer.
///
/// One body, two callers — `PqClientBootstrap` and the default a ring builds
/// for itself — because the two halves are not separable. Asking alone puts
/// the reply in the in-memory secret store and nothing files it from there
/// mid-session: `NskeyPrivateFiling.filePending` runs at start and says so
/// itself. A heal that only broadcast would repair the client at its *next*
/// start, measured live 2026-08-17 with the holder replying correctly and the
/// answer sitting unfiled.
///
/// The wait is unawaited and best-effort: a holder may be offline for a long
/// time and a read must not block on one.
Future<void> requestAndFileNskeyPrivate(
  PairwiseSecretSharing sharing,
  NskeyPrivateFiling? filing,
  String namespace,
  String secretName, {
  required AtSignLogger logger,
  Duration timeout = NskeyPrivateFiling.conveyanceWait,
}) async {
  await sharing.requestSecretsFromNamespace(namespace, names: [secretName]);
  unawaited(sharing
      .waitForSecret(namespace, secretName, timeout: timeout)
      .then((secret) async => await filing?.file(secret) ?? false)
      .then((filed) {
    if (filed) {
      logger.info('Filed the nskey private $namespace:$secretName that a '
          'holder conveyed on request');
    }
  }).catchError((Object e) {
    // info, not warning: no holder replying within the window is ordinary
    // (they may all be offline), and the next start asks again.
    logger.info('No holder conveyed $namespace:$secretName within the wait; '
        'the next start asks again: $e');
  }));
}

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
/// the key somewhere the operator does not control.
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
      if (key.offeredForNewOperations) sealable++;
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
/// secret-sharing substrate is what supplies them instead of [mintAndPublish].
/// One freshly minted key: the seed that is filed, and the pair it derives.
typedef _MintedKey = ({
  String keyAlgo,
  NskeySeed seed,
  Uint8List publicKey,
  Uint8List secretKey,
});

/// Everything a mint computes **before** it holds the lock — the keys, the
/// advertisement built from them, and this enrollment's signature over it.
typedef _PreparedMint = ({
  List<_MintedKey> minted,
  NskeyAdvertisement advertisement,
  String signedPayload,
});

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
  /// This is the read path's half of the self-heal: a value can arrive before
  /// the private that opens it — a new enrollment that missed the mint-time push
  /// is the ordinary case, not an edge — and the reader asks rather than
  /// failing forever. The request is store-and-forward: any current holder
  /// answers when it next runs.
  ///
  /// Null here does **not** mean silence: a ring with a [privateFiling]
  /// derives its own ask — see [_ask] — so a client built from an `AtClient`
  /// alone heals like one wired by `PqClientBootstrap`. What the bootstrap
  /// supplies that cannot be derived is the **gate**: only it knows
  /// `PqStartupGates.askOnReadMiss`, and passing null with no filing to derive
  /// from is what turns asking off.
  ///
  /// Whoever supplies it owns waiting for the answer and filing it — see
  /// [requestAndFileNskeyPrivate], which both callers share, and the warning
  /// on [_askForMissingPrivate], where the arrival path this field's dartdoc
  /// used to claim turned out not to exist.
  final Future<void> Function(String namespace, String secretName)?
      _requestConveyance;

  /// When each generation was last asked for, so a burst of failed reads
  /// collapses to one broadcast.
  ///
  /// ⚠️ This used to be a `Set` with no expiry, documented as "per instance
  /// and never expiring: the answer is filed durably when it arrives, and a
  /// fresh client (or the next start) asks again if it never did". The second
  /// half is the whole session's worth of asking: a long-lived client that
  /// asked once and was never answered never asked again, so a notification
  /// waiting on that generation had nothing left that could rescue it.
  ///
  /// A timestamp keeps the burst collapse — which is a sub-second phenomenon
  /// — and drops the permanent silence.
  final Map<String, DateTime> _askedConveyance = {};

  /// How long after asking for a generation this ring stays quiet about it.
  ///
  /// Long enough to collapse the burst a synced backlog produces, short
  /// enough that a request nobody answered is asked again while the reader
  /// that needs it is still waiting.
  @visibleForTesting
  Duration askCooldown = const Duration(seconds: 5);

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
    // Before the lock, not inside it — see [_prepareMint].
    final prepared = await _prepareMint(owner, namespace);
    final minted = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl),
        (lease) => _mintUnlessPublished(owner, namespace, lease, prepared),
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
      await _warnIfPrivateMissing(
          owner,
          namespace,
          published,
          'read as a '
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

  Future<NskeyAdvertisement> _mintUnlessPublished(String owner,
      String namespace, MintLease lease, _PreparedMint prepared) async {
    final published = await publishedAdvertisement(owner, namespace);
    if (published == null) return _mint(owner, namespace, lease, prepared);
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

    // Before the lock, not inside it — see [_prepareMint]. A rotation that
    // loses the lock throws and discards this, which is the same trade the
    // cold-start mint makes.
    final prepared = await _prepareMint(owner, namespace);
    final rotated = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl),
        (lease) => _mint(owner, namespace, lease, prepared));
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

  /// Adds this client's missing key-establishment material to the **current**
  /// generation, in place. Returns the advertisement now published, or null if
  /// nothing was added.
  ///
  /// **Not a rotation, and the difference is what it costs.** A rotation mints
  /// a whole fresh generation, so every peer that had fetched the old one cuts
  /// and conveys a new content key at its next write. An add leaves every
  /// existing key, id and status exactly where it was — the generation keeps
  /// its own identity, `createdAt` included — so a peer sealing under an
  /// algorithm that was already there notices nothing and re-cuts nothing.
  ///
  /// **Why it exists at all.** Only a build that *implements* an algorithm can
  /// mint material for it, so a client cannot mint on another version's behalf
  /// however much it knows about the fleet. A generation therefore assembles
  /// incrementally: whichever client rotates writes the algorithms it can do,
  /// and each client that finds one of its own missing adds it. Reaching the
  /// same set by successive rotations would make every peer re-cut once per
  /// algorithm, for something cryptographically new to only one of them.
  ///
  /// **Takes the same mint lock as a rotation**, because two clients adding at
  /// once is a read-mutate-write over one durable record and the loser would
  /// overwrite the winner's entry. A client that fails the lock adds nothing
  /// and returns null; the next start asks again, by which time either another
  /// client has added what this one wanted or it still has to.
  ///
  /// **Conveys only what it minted.** The authorised enrollments already hold
  /// everything else in the generation.
  ///
  /// ⚠️ **The conveyance excludes nobody.** A revoked enrollment is off the
  /// roster, but a child it self-spawned before being revoked is not — so an
  /// add after a revocation reaches that child, exactly as a rotation
  /// excluding only the named id does.
  @experimental
  Future<NskeyAdvertisement?> add(String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final current = await publishedAdvertisement(owner, namespace);
    if (current == null) {
      // Nothing published is a cold start, which wants a whole generation
      // rather than an addition to one. Saying so rather than minting here:
      // `mintAndPublish` resolves a lost election by adopting, and an add must
      // never adopt — it would report success having added nothing.
      _logger.info('Not adding to the nskey for $owner:$namespace: nothing is '
          'published there, so what it needs is a mint');
      return null;
    }

    final missing = _missingAlgorithms(current);
    if (missing.isEmpty) return current;

    // Prepared before the lock, for the reason [_prepareMint] gives: a keygen
    // and a signature are the expensive parts and neither needs the lock, so a
    // client that loses the election throws away work that is local and cheap
    // rather than holding a remote, ttl-bounded window open across it.
    final prepared = await _prepareMint(owner, namespace,
        algorithms: missing,
        retaining: current.keys,
        createdAt: current.createdAt);

    final added = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl), (lease) async {
      // Re-read INSIDE the lock, which is what the lock is worth taking for:
      // the check above ran outside it, and a rotation that landed in the
      // window between the two would leave this client about to publish an
      // advertisement built from a generation that no longer exists —
      // silently rolling the rotation back.
      final fresh = await publishedAdvertisement(owner, namespace);
      if (fresh == null || !_sameGeneration(fresh, current)) {
        _logger.info('Not adding to the nskey for $owner:$namespace: the '
            'generation changed between deciding to add and taking the lock, '
            'so the prepared material belongs to a generation that is gone. '
            'The next start re-decides against whatever is published then');
        return null;
      }
      return _mint(owner, namespace, lease, prepared);
    });

    if (added == null) {
      _logger.info('Did not add ${missing.join(', ')} to the nskey for '
          '$owner:$namespace this time; the next start asks again');
      return null;
    }
    _logger.info('Added ${missing.join(', ')} to the nskey generation for '
        '$owner:$namespace, minted at ${current.createdAt}: '
        '${added.keys.map((k) => '${k.alg}/${k.kid}').join(', ')}');
    return added;
  }

  /// Which of this client's configured algorithms [current] offers no key for.
  ///
  /// A **retired** entry does not count as offering one: it is kept so that
  /// what it sealed still opens, and adding beside it is how the generation
  /// regains something to seal *to*.
  List<String> _missingAlgorithms(NskeyAdvertisement current) =>
      wantedKeyAlgorithms()
          .where((alg) => !current.keys.any((key) =>
              key.alg == alg &&
              key.use == SecretSharingAlgos.useEnc &&
              key.offeredForNewOperations))
          .toList();

  /// Whether [a] and [b] are the same generation.
  ///
  /// By `createdAt` **and** the set of key ids, not by `nskeyKid`: that getter
  /// names whichever entry a sender with no preference would take, so on a
  /// generation carrying two it would call one that had gained a third
  /// unchanged.
  static bool _sameGeneration(NskeyAdvertisement a, NskeyAdvertisement b) =>
      a.createdAt.isAtSameMomentAs(b.createdAt) &&
      a.keys.map((k) => k.kid).toSet().containsAll(b.keys.map((k) => k.kid)) &&
      a.keys.length == b.keys.length;

  /// Everything a mint can compute **before** it holds the lock: the keypair,
  /// the advertisement built from it, and the signature over that
  /// advertisement.
  ///
  /// Hoisted out of the critical section deliberately. A mint lock is a window
  /// bounded by a ttl, and everything done while holding it is time in which
  /// another enrollment cannot mint and this one can still lose its lease —
  /// so the section should contain the writes that have to be serialised and
  /// as little else as possible. A KEM keygen and an ML-DSA signature are the
  /// two expensive things here and neither needs the lock: they touch nothing
  /// shared and the material never leaves this process until the write.
  ///
  /// The cost of preparing first is that a client which then loses the
  /// election, or finds a sibling published while it was racing, throws this
  /// away. That is the right trade: the work is local and cheap, while the
  /// lock window it removes is remote and bounded.
  Future<_PreparedMint> _prepareMint(String owner, String namespace,
      {List<String>? algorithms,
      List<PackageKey> retaining = const [],
      DateTime? createdAt}) async {
    final wanted = algorithms ?? wantedKeyAlgorithms();

    // Minted before the advertisement is built, because the advertisement is
    // built FROM the keys: its `suites` is what this generation can open, and
    // that is fixed by the KEMs it actually holds rather than by what this
    // build implements.
    final minted = <_MintedKey>[];
    for (final keyAlgo in wanted) {
      final kem = SecretSharingAlgos.kemFor(keyAlgo)!;
      // The SEED is what is filed and what everything re-derives from; for
      // ML-KEM the decapsulation key is expanded and cannot be turned back
      // into a public half, so filing it would leave the generation unopenable
      // after a restart.
      final seed = NskeySeed(kem.newSeed());
      final pair = await kem.keyPairFromSeed(seed.bytes);
      minted.add((
        keyAlgo: keyAlgo,
        seed: seed,
        publicKey: pair.publicKey,
        secretKey: pair.secretKey,
      ));
    }

    final advertisement = NskeyAdvertisement(
      v: nskeyAdvertisementVersion,
      // Carried across for an ADD, which joins the current generation in
      // place: refreshing it would make a generation minted before a
      // revocation read as one minted after, and the rotation that revocation
      // is owed would never fire.
      createdAt: createdAt ?? DateTime.now().toUtc(),
      keys: [
        ...retaining,
        for (final key in minted)
          PackageKey.fromBytes(
              use: SecretSharingAlgos.useEnc,
              alg: key.keyAlgo,
              pub: key.publicKey),
      ],
    );

    // One codec, both directions. Each entry carries its own `alg`, without
    // which a sender has an opaque byte string and no way to tell which KEM it
    // belongs to; `suites` says which *construction* the owner can unwrap,
    // without which a new one could only ever arrive by upgrading every reader
    // first — release-ordering agility rather than negotiated agility.
    final signedPayload = await _signer.wrapAndSignAndJsonEncode(
        advertisement.toPayload(),
        type: EnvelopeType.nskeyRing);

    return (
      minted: minted,
      advertisement: advertisement,
      signedPayload: signedPayload,
    );
  }

  /// The key-establishment algorithms this client mints for, in the
  /// preference's own order.
  ///
  /// **Every configured algorithm, not the first.** A generation holds a key
  /// per algorithm the fleet needs, and only a build that *implements* one can
  /// mint material for it — so a client configured for two and able to do both
  /// mints both, and the fleet's set assembles from what its members can
  /// actually produce.
  ///
  /// **Nothing is filtered here.** `AtClientPreference` refuses an empty list
  /// and refuses any algorithm this build does not implement, both at
  /// construction — so a preference that exists names a non-empty set this
  /// build can mint. Repeating either guard would be a claim about that class
  /// rather than a check, and would be unreachable.
  ///
  /// A duplicate is dropped, because two entries under one algorithm are two
  /// keys where a sender takes the first and the second is minted, filed and
  /// conveyed for nobody.
  @visibleForTesting
  List<String> wantedKeyAlgorithms() {
    final configured = _atClient.getPreferences()?.keyEstablishmentAlgorithms ??
        const [SecretSharingAlgos.xWing];
    final wanted = <String>[];
    for (final keyAlgo in configured) {
      if (!wanted.contains(keyAlgo)) wanted.add(keyAlgo);
    }
    return wanted;
  }

  Future<NskeyAdvertisement> _mint(
    String owner,
    String namespace,
    MintLease lease,
    _PreparedMint prepared,
  ) async {
    final advertisement = prepared.advertisement;
    final payload = prepared.signedPayload;

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
      // Every key this mint produced, each under its own id. A generation can
      // hold a key per algorithm the fleet needs, and one filed under the
      // generation's "primary" id would leave every other entry advertised
      // with no private anywhere — peers sealing to something the owner
      // cannot open.
      for (final key in prepared.minted) {
        final stored = await filing.store(
          namespace: namespace,
          nskeyKid: nskeyKidOf(key.publicKey),
          seed: key.seed,
          keyAlgo: key.keyAlgo,
        );
        if (!stored) {
          throw StateError(
              'could not store the ${key.keyAlgo} nskey private for '
              '$owner:$namespace, so its public half is deliberately not '
              'published');
        }
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

    // The verification key a peer checks the (already computed) signature
    // against. Still inside the lock: it is a network write, not the CPU work
    // this section was trimmed of, and it must land before the advertisement
    // that depends on it.
    await _signer.publishPublicSigningKey();

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

    // The atServer, and only the atServer. An advertisement is useful once a
    // *peer* can fetch it, so it goes straight out rather than through a
    // local-first put that would leave it unpublished until the next sync.
    //
    // Deliberately not written to local storage as well. A local write of a
    // sync-eligible key appends the key's *name* to the client→server sync
    // queue, and a drain sends whatever local storage holds at the moment it
    // runs — so a drain landing between this update and that write pushes the
    // **superseded** generation back over the one just published. Nothing
    // corrects it: the atServer's newest value for the key is then the old
    // generation, so this client pulls it back over its own copy and the queued
    // push re-sends it. The atSign goes on advertising a key it rotated away
    // from, which for a rotation that accompanied a revocation is the
    // generation the revoked enrollment still holds.
    //
    // Local storage still ends up with this record: sync pulls it down as a
    // server-originated change, and that is the one write path that never
    // enqueues a push. [currentPublic] reads local first and falls back to the
    // atServer, so it answers correctly in the window before that arrives.
    await _atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
      ..atKey = advertisementKey
      ..value = payload);

    _ownCurrent[_scope(owner, namespace)] = advertisement;
    for (final key in prepared.minted) {
      _ownPrivates[_generation(owner, namespace, nskeyKidOf(key.publicKey))] =
          NskeyDecapsulationKey(key.secretKey);
    }
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
          await _getLocalThenRemote(nskeyAdvertisementKey(owner, namespace));
      if (value == null) return _staleOrNothing(cached);
      payload = value;
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

  /// Reads [atKey] from local storage, falling back to the atServer when it is
  /// not held there.
  ///
  /// Local first because [currentPublic] sits on the write path —
  /// `CkManager.ensureCurrent` reaches it on every `put` — so a round trip by
  /// default would break offline writes.
  ///
  /// The fallback is what makes it correct to publish the advertisement to the
  /// atServer alone. Local storage is no longer where that record is written;
  /// it arrives when sync pulls it down. Without the fallback, a client that
  /// has just minted, or whose sibling enrollment minted a moment ago, reads
  /// its own published namespace as a cold start for as long as that takes —
  /// and a client that "fixed" a cold start by minting would rotate the key out
  /// from under every peer that had already fetched it.
  ///
  /// What the atServer answers is filed locally on the way back, so a device
  /// whose sync is disabled or paused pays the round trip once rather than on
  /// every read.
  ///
  /// A general enough shape that it may belong on `AtClient`, most naturally as
  /// an option on `GetRequestOptions` rather than a method of its own. Private
  /// until a second caller wants it.
  Future<String?> _getLocalThenRemote(AtKey atKey) async {
    try {
      final local = await _atClient.get(atKey);
      if (local.value != null) return local.value as String;
    } on AtKeyNotFoundException {
      // Absent locally is the ordinary state for a record this device has not
      // synced yet, so it is a reason to ask the atServer rather than a
      // failure. Both exception types, because the local keystore and the
      // client's own validation raise different ones for the same absence.
    } on KeyNotFoundException {
      // As above.
    }
    final remote = await _atClient.get(atKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    final value = remote.value as String?;
    if (value != null) await _fileFetched(atKey, value);
    return value;
  }

  /// Files a value this client just fetched from the atServer into local
  /// storage, without offering it back to the atServer.
  ///
  /// `cameFromServer: true` is the whole mechanism: it is the flag
  /// `LocalSecondary._enqueueForSync` refuses on, so this write queues no
  /// client→server push. An ordinary `put` here would re-create the defect the
  /// minter's own local write was removed for — a queued entry carries the
  /// key's *name*, so the push sends whatever local storage holds when it
  /// drains, which can be a generation the atServer has already moved past.
  ///
  /// **Our own atSign only.** A peer's advertisement is not ours to publish,
  /// and a record written under its own name is exactly what a push would
  /// offer; the shared-key path caches a peer's public key under
  /// `cached:public:publickey@<peer>` for the same reason. For a peer the
  /// [advertisementTtl] cache is the mechanism, and it is unchanged.
  ///
  /// Failure is logged and swallowed. This is an optimisation applied to a
  /// read that already has its answer, so failing it would turn a working
  /// fetch into a failed one.
  Future<void> _fileFetched(AtKey atKey, String value) async {
    if (atKey.sharedBy != _atClient.getCurrentAtSign()) return;
    try {
      await _atClient.getLocalSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = atKey
            ..value = value,
          cameFromServer: true);
    } on Object catch (e) {
      _logger.finer('could not file the fetched $atKey locally: $e');
    }
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

  /// How this ring asks, supplied or derived.
  ///
  /// Built on the miss rather than in the constructor, which is the whole
  /// reason a default is possible at all: reaching the substrate eagerly would
  /// construct it in every fixture that only ever reads. `forClient` is
  /// per-client cached, so a ring that derives its own ask uses the **same**
  /// `AtClientSecretSharing` the bootstrap holds rather than a rival one.
  ///
  /// Null when there is nowhere to file the answer. Asking without filing
  /// leaves the reply in the in-memory secret store and repairs the client at
  /// its next start rather than this one, which reads as a heal that worked
  /// and did nothing.
  Future<void> Function(String namespace, String secretName)? get _ask {
    final supplied = _requestConveyance;
    if (supplied != null) return supplied;
    final filing = privateFiling;
    if (filing == null) return null;
    return (namespace, secretName) => requestAndFileNskeyPrivate(
        AtClientSecretSharing.forClient(_atClient),
        filing,
        namespace,
        secretName,
        logger: _logger);
  }

  /// Whether a read miss on an own generation will broadcast a pull.
  ///
  /// The mechanism a test asserts instead of the substrate traffic: a ring
  /// that answers false here cannot heal, however the rest of it is wired.
  @visibleForTesting
  bool get asksOnReadMiss => _ask != null;

  void _askForMissingPrivate(String namespace, String nskeyKid) {
    final ask = _ask;
    if (ask == null) return;
    // One broadcast per generation per [askCooldown]: every conveyance of a
    // synced backlog fails through here in a burst, and N identical requests
    // buy nothing the first did not. Past the cooldown they do buy something
    // — the first ask may have reached holders that could not serve it.
    final generation = _generation('own', namespace, nskeyKid);
    final asked = _askedConveyance[generation];
    if (asked != null && DateTime.now().difference(asked) < askCooldown) {
      return;
    }
    _askedConveyance[generation] = DateTime.now();

    final secretName = '${NskeyPrivateFiling.secretNamePrefix}$nskeyKid';
    unawaited(ask(namespace, secretName).then((_) {
      _logger.info('Asked the other enrollments for the nskey private '
          '$namespace:$nskeyKid; the answer is filed when a holder replies');
    }).catchError((Object e) {
      // Clear the stamp so the next miss re-asks rather than waiting out a
      // cooldown earned by a request that never went out.
      _askedConveyance.remove(generation);
      _logger.info('Could not request the missing nskey private for '
          '$namespace:$nskeyKid, and the next read miss will ask again: $e');
    }));
  }
}
