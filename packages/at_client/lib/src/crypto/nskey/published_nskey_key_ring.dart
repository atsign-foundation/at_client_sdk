import 'dart:async' show StreamSubscription, unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysIo, AtKeysSourceAbsentException;
import 'package:at_client/src/crypto/crypto.dart'
    show FiledNskeyPrivate, SignalsPrivateFiling;
import 'package:at_client/src/enroll/at_sign_credential.dart'
    show isAtSignCredential;
import 'package:at_client/src/enroll/authorised_namespaces.dart'
    show isSeedableNamespace;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/data_event.dart';
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/conveyed_key_collection.dart'
    show collectConveyedKeyMaterial;
import 'package:at_client/src/client/server_mutex.dart'
    show ServerMutexLease, checkedServerMutexTtl;
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
import 'package:at_client/src/util/swallowed_error.dart';
import 'package:meta/meta.dart' show internal, visibleForTesting;

final _logger = AtSignLogger('PublishedNskeyKeyRing');

/// Asks this atSign's other enrollments for one missing nskey private, then
/// waits for a holder to answer and files the answer.
///
/// Throws only when the ask cannot be sent. Otherwise completes once the
/// answer is filed, the wait for it ends, or no other enrollment was there to
/// ask, so a caller can tell an ask that is still outstanding; a read must not
/// await it, since a holder may be offline for a long time.
Future<void> requestAndFileNskeyPrivate(
  PairwiseSecretSharing sharing,
  NskeyPrivateFiling? filing,
  String namespace,
  String secretName, {
  required AtSignLogger logger,
  Duration timeout = NskeyPrivateFiling.conveyanceWait,
}) async {
  final sent =
      await sharing.requestSecretsFromNamespace(namespace, names: [secretName]);
  if (sent == 0) {
    logger.info('Wanted the nskey private $namespace:$secretName but found no '
        'other key package to ask');
    return;
  }
  logger.info('Asked the other enrollments for the nskey private '
      '$namespace:$secretName; the answer is filed when a holder replies');
  try {
    final secret =
        await sharing.waitForSecret(namespace, secretName, timeout: timeout);
    if (await filing?.file(secret) ?? false) {
      logger.info('Filed the nskey private $namespace:$secretName that a '
          'holder conveyed on request');
    }
  } on StoppedException {
    logger.warning('Stopped waiting for the nskey private '
        '$namespace:$secretName: the client stopped, and the next start '
        'asks again');
  } catch (e) {
    logger.info('No holder conveyed $namespace:$secretName within the wait; '
        'a read miss after it asks again: $e');
  }
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
/// Does not defend against the operator of [owner]'s atServer, which serves
/// both the advertisement and the `_apsk` it is checked against and so can
/// substitute a consistent pair.
class ApkamSignedAdvertisedKeys implements AdvertisedKeyVerifier {
  final AtClientEnvelopeSigner _signer;

  ApkamSignedAdvertisedKeys(AtClient atClient)
      : _signer = AtClientEnvelopeSigner(atClient);

  @override
  Future<NskeyAdvertisement> verify(String owner, String payload) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException catch (e) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner is not JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner is not a JSON object');
    }
    final SignedEnvelope envelope;
    try {
      envelope = SignedEnvelope.fromJson(decoded);
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

    // NOTE: an entry naming an algorithm this build cannot do is skipped, not
    // refused, so an owner can advertise a new KEM beside an old one without
    // cutting off every peer that predates it. What is refused is an
    // advertisement with nothing left after the skipping.
    var understood = 0;
    var sealable = 0;
    for (final key in advertisement.keys) {
      if (SecretSharingAlgos.kemFor(key.alg) == null) continue;
      understood++;
      if (key.offeredForNewOperations) sealable++;
      // NOTE: the length is checked because a kid is the digest of whatever
      // bytes are carried, so it matches a forged key as readily as a real one
      // and cannot see a wrong-length key at all.
      final expected = SecretSharingAlgos.publicKeyLengthFor(key.alg);
      if (expected == null) {
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
        throw AtSigningVerificationException(
            'the advertised nskey for $owner names a kid that is not the digest '
            'of the key it carries');
      }
    }
    if (understood == 0) {
      throw _UnusableAdvertisementException(
          'the advertised nskey for $owner offers only key-establishment '
          'algorithms this build cannot encapsulate to '
          '(${advertisement.keys.map((k) => '"${k.alg}"').join(', ')}) — '
          'refusing rather than sealing under one it did not name');
    }
    if (sealable == 0) {
      throw _UnusableAdvertisementException(
          'the advertised nskey for $owner retires every key this build can '
          'encapsulate to, so it names nothing to seal to now');
    }
    return advertisement;
  }
}

/// An advertisement whose signature verifies and that names nothing this build
/// can encapsulate to now.
class _UnusableAdvertisementException extends AtSigningVerificationException {
  _UnusableAdvertisementException(super.message);
}

/// Whether [e], from verifying this atSign's own advertisement, says the record
/// may be minted over: it was read and does not verify, or the enrollment that
/// signed it publishes no `_apsk`.
bool _replaceableOwnAdvertisement(Object e) =>
    (e is AtSigningVerificationException &&
        e is! _UnusableAdvertisementException) ||
    e is AtKeyNotFoundException ||
    e is KeyNotFoundException;

/// One freshly minted key: the seed that is filed, and the pair it derives.
typedef _MintedKey = ({
  String keyAlgo,
  NskeySeed seed,
  Uint8List publicKey,
  Uint8List secretKey,
});

/// An advertisement a ring holds, when it was read, and the verified bytes it
/// came from where known.
typedef _CachedAdvertisement = ({
  NskeyAdvertisement advertisement,
  DateTime fetchedAt,
  String? payload,
});

/// One generation of this client's own atSign.
typedef _OwnGeneration = ({String namespace, String nskeyKid});

/// Everything a mint computes **before** it holds the lock — the keys, the
/// advertisement built from them, and this enrollment's signature over it.
typedef _PreparedMint = ({
  List<_MintedKey> minted,
  NskeyAdvertisement advertisement,
  String signedPayload,
});

/// Rotates onto a fresh generation under the mint lock the caller's mint still
/// holds, conveying through [conveyFirst] and then running [afterPublish] as a
/// mint does.
typedef NskeyRotateHoldingLease = Future<NskeyAdvertisement> Function(
    {Future<void> Function(List<String> nskeyKids)? conveyFirst,
    Future<void> Function(NskeyAdvertisement published)? afterPublish});

/// What a mint or a rotation runs once its advertisement is published, handed
/// that advertisement and a rotation under the lock it still holds; answers
/// the generation published after it, or null when it published nothing more.
typedef NskeyAfterPublish = Future<NskeyAdvertisement?> Function(
    NskeyAdvertisement published, NskeyRotateHoldingLease rotate);

/// An [NskeyKeyRing] that publishes the owner's nskey and discovers other
/// atSigns' by `plookup`.
///
/// Own privates are held in memory here; conveying them per-APKAM over the
/// secret-sharing substrate is what supplies them to an enrollment that did
/// not run [mintAndPublish] itself.
class PublishedNskeyKeyRing implements NskeyKeyRing, SignalsPrivateFiling {
  final AtClient _atClient;
  final AdvertisedKeyVerifier verifier;

  /// How long a fetched advertisement is trusted before it is re-fetched.
  ///
  /// The lever on how long a peer's rotation can go unnoticed: a sender never
  /// sees a recipient's decapsulation fail, so re-fetching is the only way it
  /// learns of one. The worst-case exposure after a rotation is this plus
  /// [advertisementStaleGrace].
  final Duration advertisementTtl;

  /// How far past [advertisementTtl] a re-fetch that cannot reach an answer
  /// may keep serving the advertisement it already has, before the failure is
  /// thrown to the caller.
  ///
  /// A short grace absorbs an ordinary blip; past it the write fails rather
  /// than silently handing a revoked enrollment a key it can still open, since
  /// a peer that rotated *because of a revocation* is the one a sender most
  /// needs to stop sealing to. A not-found gets no grace: the owner's atServer
  /// has said the record is gone.
  final Duration advertisementStaleGrace;

  /// [ownChanges], when given, is where the ring hears that local storage's
  /// copy of this client's own advertisement changed — sync landing a
  /// sibling's rotation — so it re-reads at once rather than when
  /// [advertisementTtl] runs out. It is listened to from the first read of an
  /// own advertisement, so a client that never reads one subscribes to nothing.
  ///
  /// [askOnReadMiss] false makes a miss on an own private touch nothing but
  /// local storage: no advertisement read, no fetch and no ask.
  PublishedNskeyKeyRing(
    this._atClient, {
    AdvertisedKeyVerifier? verifier,
    this.advertisementTtl = const Duration(minutes: 15),
    this.advertisementStaleGrace = const Duration(minutes: 15),
    MintLock? mintLock,
    Duration lockTtl = mintLockTtl,
    this.lockBudgetPerMember = const Duration(seconds: 2),
    NskeyPrivateFiling? privateFiling,
    Future<void> Function(String namespace, String secretName)?
        requestConveyance,
    Future<void> Function()? fetchConveyance,
    Stream<DataEvent> Function()? ownChanges,
    bool askOnReadMiss = true,
  })  : lockTtl = checkedServerMutexTtl(lockTtl, 'lockTtl'),
        verifier = verifier ?? ApkamSignedAdvertisedKeys(_atClient),
        mintLock = mintLock ?? MintLock(_atClient),
        _requestConveyance = requestConveyance,
        _fetchConveyance = fetchConveyance,
        _ownChanges = ownChanges,
        _askOnReadMiss = askOnReadMiss,
        _signer = AtClientEnvelopeSigner(_atClient) {
    _privateFiling = privateFiling ?? _filingFor(_atClient, this);
  }

  final Stream<DataEvent> Function()? _ownChanges;

  /// The filing a ring builds for itself when its caller named none, over the
  /// client's own `AtKeysIo`; null when the client has no key source at all.
  ///
  /// Two filings over one keyfile are safe, but they carry separate
  /// `privatesFiled` streams, so a caller that needs a filing's events must
  /// pass the instance it is listening to.
  static NskeyPrivateFiling? _filingFor(
      AtClient atClient, PublishedNskeyKeyRing ring) {
    final keysIo = atClient.atKeysIo;
    if (keysIo == null) return null;
    final atSign = atClient.getCurrentAtSign();
    if (atSign == null) return null;
    return NskeyPrivateFiling.checkedAgainst(() => ring,
        keysIo: keysIo, atSign: atSign);
  }

  /// Broadcasts a pull request for a missing own-atSign private, when
  /// [privateHalf] comes up empty for a generation this atSign has published.
  ///
  /// The request is store-and-forward: any current holder answers when it next
  /// runs, and whoever supplies this owns waiting for the answer and filing it
  /// — see [requestAndFileNskeyPrivate]. Null is not silence, since a ring
  /// with a [privateFiling] derives its own ask; it asks nothing with no
  /// filing to derive from, or with `askOnReadMiss` false.
  final Future<void> Function(String namespace, String secretName)?
      _requestConveyance;

  /// Fetches the conveyance records addressed to this enrollment from the
  /// atServer and files what they carry, when [privateHalf] comes up empty for
  /// an own generation; derived like [_requestConveyance] when null.
  final Future<void> Function()? _fetchConveyance;

  final bool _askOnReadMiss;

  /// The on-miss fetch in flight, which every concurrent miss shares.
  Future<void>? _fetching;

  /// When the last on-miss fetch started; the startup collection does not
  /// count.
  DateTime? _fetchedOnMiss;

  /// The kids each own namespace's advertisement named when a miss last read
  /// it, kept apart from the advertisements writes seal to.
  final Map<String, Set<String>> _kidsReadOnMiss = {};

  /// When a miss last read each own namespace's advertisement.
  final Map<String, DateTime> _readOnMissAt = {};

  /// The on-miss advertisement read in flight per namespace, which every
  /// concurrent miss in it shares.
  final Map<String, Future<void>> _readingOnMiss = {};

  /// When each own generation was last asked about. Stamps older than
  /// [askCooldown] are dropped.
  final Map<_OwnGeneration, DateTime> _askedAt = {};

  /// The asks whose answer is still awaited, by whichever route they went out.
  final Map<_OwnGeneration, Future<void>> _outstanding = {};

  /// How many namespaces this ring asked about within the last [askCooldown].
  @visibleForTesting
  int get namespacesAskedRecently =>
      _askedAt.keys.map((asked) => asked.namespace).toSet().length;

  /// How long after an on-miss fetch, an on-miss read of an own advertisement,
  /// or an ask about a generation, this ring stays quiet about it.
  ///
  /// Long enough to collapse the burst a synced backlog produces, short
  /// enough that an atServer that could not be reached is tried again while
  /// the reader that needs it is still waiting.
  @visibleForTesting
  Duration askCooldown = const Duration(seconds: 5);

  /// How long a miss on an own private waits for each of the on-miss read of
  /// the own advertisement and the fetch of this enrollment's conveyance
  /// records.
  ///
  /// Each goes on past it: a fetch then files a private that releases
  /// whatever parked waiting for one, and a read records the kids a later
  /// miss sees.
  @visibleForTesting
  Duration fetchOnMissTimeout = const Duration(seconds: 10);

  /// Serialises minting between this atSign's own enrollments.
  final MintLock mintLock;

  /// What each enrollment listed for a namespace adds to [lockTtl] for a mint
  /// that conveys before it publishes, so the lock outlasts the conveyance.
  final Duration lockBudgetPerMember;

  /// How long this ring holds a namespace's mint lock once it has taken it.
  ///
  /// Expiry is the only thing that releases the lock, so this is also the
  /// cooldown before another election may be held for the same namespace, and
  /// a rotation attempted inside it is refused rather than queued.
  final Duration lockTtl;

  /// Where a minted private is made durable **before** its public half is
  /// published.
  ///
  /// Defaults to a filing over the client's own `AtKeysIo` — see [_filingFor]
  /// — and is null only for a client with no key source at all, where [_mint]
  /// says so at `severe` and mints anyway: a published key whose private did
  /// not survive the process leaves every sender sealing to something nobody
  /// can open.
  NskeyPrivateFiling? get privateFiling => _privateFiling;
  late final NskeyPrivateFiling? _privateFiling;

  @override
  Stream<FiledNskeyPrivate> get privatesFiled =>
      privateFiling?.privatesFiled ?? const Stream<FiledNskeyPrivate>.empty();

  /// Signs this atSign's own advertisements.
  final AtClientEnvelopeSigner _signer;

  /// Record a generation as this client's own, without minting one.
  ///
  /// For a test that needs a ring in the "already minted" state without a
  /// remote secondary; [mintAndPublish] is the production caller.
  @visibleForTesting
  void rememberOwn(
          String owner, String namespace, NskeyAdvertisement advertisement) =>
      _remote[_scope(owner, namespace)] = (
        advertisement: advertisement,
        fetchedAt: DateTime.now(),
        payload: null,
      );

  /// Drop what this ring cached for `(owner, namespace)`, forcing the next
  /// read to go to the atServer.
  ///
  /// For a test that changes a peer's published advertisement out from under a
  /// client and needs it to notice inside [advertisementTtl]; nothing in
  /// production shortens that window.
  @visibleForTesting
  void forgetRemote(String owner, String namespace) =>
      _remote.remove(_scope(owner, namespace));

  final Map<String, NskeyDecapsulationKey> _ownPrivates = {};

  /// The public half of each generation this ring minted, beside its private
  /// in [_ownPrivates].
  final Map<String, PackageKey> _mintedPublics = {};

  /// Advertisements this ring has read or published, with when and, where
  /// known, the verified bytes they came from.
  final Map<String, _CachedAdvertisement> _remote = {};

  StreamSubscription<DataEvent>? _ownChangesSubscription;

  /// Starts expiring this client's own cached advertisements whenever local
  /// storage's copy changes.
  void _listenForOwnChanges() {
    final changes = _ownChanges;
    if (changes == null || _ownChangesSubscription != null) return;
    _ownChangesSubscription = changes().listen(_expireOwnOnChange);
  }

  /// Marks the cached advertisement [event] names as due for a re-read,
  /// keeping its bytes so an unchanged copy is not verified again.
  void _expireOwnOnChange(DataEvent event) {
    final own = _atClient.getCurrentAtSign();
    final changed = event.key.toString().toLowerCase();
    for (final scope in _remote.keys.toList()) {
      final bar = scope.indexOf('|');
      final owner = scope.substring(0, bar);
      if (owner != own) continue;
      final name = nskeyAdvertisementKey(owner, scope.substring(bar + 1))
          .toString()
          .toLowerCase();
      if (name != changed) continue;
      final cached = _remote[scope]!;
      _remote[scope] = (
        advertisement: cached.advertisement,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
        payload: cached.payload,
      );
    }
  }

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  static String _generation(String owner, String namespace, String kid) =>
      '${_scope(owner, namespace)}|$kid';

  /// Mint a generation for `(currentAtSign, namespace)` and publish its public
  /// half immediately.
  ///
  /// The cold-start mint, and **not the rotation lever**: losing the mint lock
  /// here is resolved by adopting the winner's advertisement and returning it,
  /// so a call can succeed having rotated nothing. Use [rotate] to supersede a
  /// generation.
  ///
  /// [conveyFirst] is handed the kids of what is about to be published, after
  /// their privates are filed and before the advertisement goes out; if it
  /// throws, nothing is published. [afterPublish] runs once it is out, still
  /// under the lock, and what it answers is returned in its place. [lockTtl]
  /// overrides the ring's for this call.
  Future<NskeyAdvertisement> mintAndPublish(String namespace,
      {Future<void> Function(List<String> nskeyKids)? conveyFirst,
      NskeyAfterPublish? afterPublish,
      Duration? lockTtl}) async {
    final owner = _atClient.getCurrentAtSign()!;
    final prepared = await _prepareMint(owner, namespace);
    final minted = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl ?? this.lockTtl),
        (lease) => _mintUnlessPublished(
            owner, namespace, lease, prepared, conveyFirst, afterPublish));
    if (minted != null) return minted;

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

    throw StateError('another client of this atSign holds the mint lock for '
        '$owner:$namespace and has published no advertisement yet, so this client has no namespace key '
        'to seal to and must not mint a second one; retry after the lock\'s '
        'ttl elapses');
  }

  /// Says so when this client adopts an advertisement it cannot open with.
  ///
  /// A warning rather than a refusal: an enrollment that has legitimately just
  /// joined holds no private until the conveyance reaches it, which is
  /// expected and self-correcting, and the read path already throws a typed
  /// exception for it.
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

  /// [_mint], unless a sibling enrollment published while this client was
  /// taking the lock.
  ///
  /// The advertisement record is mutable, so minting on an absence checked
  /// outside the lock overwrites the winner's key and every peer that had
  /// already fetched it goes on sealing to a generation its owner will never
  /// look for. Adopting is right only for the cold-start mint; [rotate] runs
  /// [_mint] directly.
  Future<NskeyAdvertisement> _mintUnlessPublished(
      String owner,
      String namespace,
      ServerMutexLease lease,
      _PreparedMint prepared,
      Future<void> Function(List<String> nskeyKids)? conveyFirst,
      NskeyAfterPublish? afterPublish) async {
    final published = await publishedAdvertisement(owner, namespace);
    if (published == null) {
      await _retireUnpublished(owner, namespace);
      return _mint(owner, namespace, lease, prepared,
          conveyFirst: conveyFirst, afterPublish: afterPublish);
    }
    _logger.info(
        'Not minting an nskey for $owner:$namespace: ${published.nskeyKid} was '
        'published between the decision to mint and this client taking the '
        'lock, so it is adopted rather than overwritten');
    await _warnIfPrivateMissing(owner, namespace, published, 'adopted');
    return published;
  }

  /// Rotates `(currentAtSign, namespace)` onto a fresh generation: mints the
  /// next keypair, **overwrites** the published advertisement with it, and
  /// keeps every private this client already held, so records sealed to an
  /// earlier generation still open.
  ///
  /// Throws where [mintAndPublish] adopts — on losing the mint lock, and on
  /// finding nothing published to supersede. [conveyFirst], [afterPublish] and
  /// [lockTtl] are as for [mintAndPublish].
  Future<({NskeyAdvertisement rotated, NskeyAdvertisement superseded})> rotate(
      String namespace,
      {Future<void> Function(List<String> nskeyKids)? conveyFirst,
      NskeyAfterPublish? afterPublish,
      Duration? lockTtl}) async {
    final owner = _atClient.getCurrentAtSign()!;
    final superseded = await publishedAdvertisement(owner, namespace);
    if (superseded == null) {
      throw StateError(
          'nothing to rotate for $owner:$namespace — no nskey is published '
          'there, so this is a cold-start mint rather than a rotation');
    }

    final prepared = await _prepareMint(owner, namespace);
    final rotated = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl ?? this.lockTtl),
        (lease) => _mint(owner, namespace, lease, prepared,
            conveyFirst: conveyFirst, afterPublish: afterPublish));
    if (rotated == null) {
      throw StateError('another client of this atSign holds the mint lock for '
          '$owner:$namespace, so this rotation did not happen; retry once its '
          'ttl elapses. Reporting success here would leave the excluded '
          'enrollment holding the live generation');
    }
    _logger.info('Rotated $owner:$namespace from ${superseded.nskeyKid} to '
        '${rotated.nskeyKid}; the superseded private is retained so records '
        'sealed to it still open');
    return (rotated: rotated, superseded: superseded);
  }

  /// Adds this client's missing key-establishment material to the **current**
  /// generation, in place; returns the advertisement now published, or null if
  /// nothing was added.
  ///
  /// **Not a rotation.** Every existing key, id and status stays where it was,
  /// and the generation keeps its `createdAt` and its record stamp, so an add
  /// after a revocation cannot read as a generation minted after it.
  ///
  /// ⚠️ **The conveyance excludes nobody** — a child an enrollment self-spawned
  /// before being revoked receives what this add conveys.
  ///
  /// [conveyFirst] is handed only the kids this add mints; [lockTtl] is as for
  /// [mintAndPublish].
  Future<NskeyAdvertisement?> add(String namespace,
      {Future<void> Function(List<String> nskeyKids)? conveyFirst,
      Duration? lockTtl}) async {
    final owner = _atClient.getCurrentAtSign()!;
    final current = await publishedAdvertisement(owner, namespace);
    if (current == null) {
      _logger.info('Not adding to the nskey for $owner:$namespace: nothing is '
          'published there, so what it needs is a mint');
      return null;
    }

    final missing = _missingAlgorithms(current);
    if (missing.isEmpty) return current;

    final prepared = await _prepareMint(owner, namespace,
        algorithms: missing,
        retaining: current.keys,
        createdAt: current.createdAt);

    final added = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl ?? this.lockTtl),
        (lease) async {
      // NOTE: re-read inside the lock. The check above ran outside it, and a
      // rotation landing in between would be silently rolled back by
      // publishing material built from a generation that is gone.
      final fresh = await publishedRecord(owner, namespace);
      if (fresh == null || !_sameGeneration(fresh.advertisement, current)) {
        _logger.info('Not adding to the nskey for $owner:$namespace: the '
            'generation changed between deciding to add and taking the lock, '
            'so the prepared material belongs to a generation that is gone. '
            'The next start re-decides against whatever is published then');
        return null;
      }
      return _mint(owner, namespace, lease, prepared,
          assertUpdatedAt: fresh.updatedAt, conveyFirst: conveyFirst);
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

  /// Which of this client's configured algorithms [current] offers no key for,
  /// which is what [add] would mint.
  List<String> missingKeyAlgorithms(NskeyAdvertisement current) =>
      _missingAlgorithms(current);

  /// Which of this client's configured algorithms [current] offers no key for.
  ///
  /// A retired entry does not count as offering one: it is kept so that what
  /// it sealed still opens.
  List<String> _missingAlgorithms(NskeyAdvertisement current) =>
      wantedKeyAlgorithms()
          .where((alg) => !current.keys.any((key) =>
              key.alg == alg &&
              key.use == SecretSharingAlgos.useEnc &&
              key.offeredForNewOperations))
          .toList();

  /// Whether [a] and [b] are the same generation.
  ///
  /// By `createdAt` **and** the full set of key ids, not by `nskeyKid`: that
  /// getter names only whichever entry a sender with no preference would take,
  /// so a generation that had gained a key would compare unchanged.
  static bool _sameGeneration(NskeyAdvertisement a, NskeyAdvertisement b) =>
      a.createdAt.isAtSameMomentAs(b.createdAt) &&
      a.keys.map((k) => k.kid).toSet().containsAll(b.keys.map((k) => k.kid)) &&
      a.keys.length == b.keys.length;

  /// Everything a mint can compute **before** it holds the lock: the keypair,
  /// the advertisement built from it, and the signature over that
  /// advertisement.
  ///
  /// Hoisted out of the critical section: a mint lock is a ttl-bounded window
  /// in which no other enrollment can mint, and neither the KEM keygen nor the
  /// signature touches anything shared. A client that then loses the election
  /// throws this away, which is local and cheap.
  Future<_PreparedMint> _prepareMint(String owner, String namespace,
      {List<String>? algorithms,
      List<PackageKey> retaining = const [],
      DateTime? createdAt}) async {
    final wanted = algorithms ?? wantedKeyAlgorithms();

    final minted = <_MintedKey>[];
    for (final keyAlgo in wanted) {
      final kem = SecretSharingAlgos.kemFor(keyAlgo)!;
      // NOTE: the seed is what is filed and what everything re-derives from.
      // An ML-KEM decapsulation key is expanded and cannot be turned back into
      // a public half, so filing that instead leaves the generation unopenable
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
    return _preparedFrom(minted, retaining: retaining, createdAt: createdAt);
  }

  /// Retires every active private filed for [namespace], whichever enrollment
  /// minted it, before a cold-start mint with nothing published there.
  ///
  /// A cold-start mint always publishes a fresh generation, so none filed
  /// before it is ever published. A retired private still opens what was
  /// sealed to it.
  Future<void> _retireUnpublished(String owner, String namespace) async {
    final filing = privateFiling;
    if (filing == null) return;
    final filed = await filing.filedFor(namespace);
    if (filed.isEmpty) return;
    final kids = [for (final f in filed) f.nskeyKid];
    await filing.retire(namespace, kids);
    _logger.info('Retired the nskey private(s) ${kids.join(', ')} filed for '
        '$owner:$namespace, none of them published, before minting a fresh '
        'generation');
  }

  /// The advertisement for [minted] and this enrollment's signature over it.
  Future<_PreparedMint> _preparedFrom(List<_MintedKey> minted,
      {List<PackageKey> retaining = const [], DateTime? createdAt}) async {
    final advertisement = NskeyAdvertisement(
      v: nskeyAdvertisementVersion,
      // NOTE: carried across for an add, which joins the current generation in
      // place. Refreshing it would make a generation minted before a
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
  /// **Every configured algorithm, not the first**, since only a build that
  /// implements one can mint material for it and a generation holds a key per
  /// algorithm the fleet needs. A duplicate is dropped, because the second key
  /// under one algorithm is minted, filed and conveyed for nobody.
  List<String> wantedKeyAlgorithms() {
    final configured = _atClient.getPreferences()?.keyEstablishmentAlgorithms ??
        const [SecretSharingAlgos.xWing];
    final wanted = <String>[];
    for (final keyAlgo in configured) {
      if (!wanted.contains(keyAlgo)) wanted.add(keyAlgo);
    }
    return wanted;
  }

  /// Files every private this mint produced, then publishes the advertisement,
  /// in that order and only while [lease] is still good.
  ///
  /// [assertUpdatedAt] is the record's own previous stamp, asserted back so the
  /// write does not move it — [add]'s discipline, and nothing else's. A
  /// rotation and a cold-start mint pass nothing and take a fresh stamp, which
  /// is what makes `updatedAt` mean *when this generation was minted*; never a
  /// locally computed time.
  ///
  /// [afterPublish] runs once the advertisement is out, handed a rotation under
  /// [lease], and what it answers is returned in place of this generation.
  Future<NskeyAdvertisement> _mint(
    String owner,
    String namespace,
    ServerMutexLease lease,
    _PreparedMint prepared, {
    DateTime? assertUpdatedAt,
    Future<void> Function(List<String> nskeyKids)? conveyFirst,
    NskeyAfterPublish? afterPublish,
  }) async {
    final advertisement = prepared.advertisement;
    final payload = prepared.signedPayload;

    final advertisementKey = nskeyAdvertisementKey(owner, namespace);
    advertisementKey.metadata.updatedAt = assertUpdatedAt;
    // NOTE: every private is made durable BEFORE the advertisement goes out. A
    // key published ahead of its private leaves every sender sealing to
    // something nobody can open, and no later repair recovers what was written
    // in between.
    final filing = privateFiling;
    if (filing != null) {
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
      _logger.severe('Minting the nskey for $owner:$namespace with nowhere to '
          'file its private: this client has no AtKeysIo and no filing was '
          'supplied, so the private is held in memory only. Peers will seal to '
          'the published key, and every value they seal becomes permanently '
          'unreadable when this process ends');
    }

    // NOTE: the verification key must land before the advertisement that
    // depends on it, or a peer has nothing to check the signature against.
    await _signer.publishPublicSigningKey();

    // NOTE: conveyed before the publish, so every enrollment it reaches holds
    // the private by the time anyone can seal to the generation; a mint that
    // dies here leaves a generation nobody can seal to.
    await conveyFirst
        ?.call([for (final key in prepared.minted) nskeyKidOf(key.publicKey)]);

    // NOTE: checked last, not earlier. A keygen, a keyfile write and a
    // signature can each take arbitrarily long on a suspended or loaded
    // device, and a winner whose lease ran out in that time must abandon
    // rather than publish over the enrollment that has since won the next
    // election.
    if (lease.isSpent) {
      throw StateError(
          'the mint lock for $owner:$namespace expired while this client was '
          'minting, so its advertisement is deliberately not published — '
          'another enrollment may already hold the lock and be publishing its '
          'own. Retry: the next attempt takes a fresh lock');
    }

    await _atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
      ..atKey = advertisementKey
      ..value = payload);
    await _fileMinted(advertisementKey, payload);

    _remote[_scope(owner, namespace)] = (
      advertisement: advertisement,
      fetchedAt: DateTime.now(),
      payload: payload,
    );
    for (final key in prepared.minted) {
      final generation =
          _generation(owner, namespace, nskeyKidOf(key.publicKey));
      _ownPrivates[generation] = NskeyDecapsulationKey(key.secretKey);
      _mintedPublics[generation] = PackageKey.fromBytes(
          use: SecretSharingAlgos.useEnc, alg: key.keyAlgo, pub: key.publicKey);
    }
    if (afterPublish == null) return advertisement;
    final next = await afterPublish(
        advertisement,
        ({conveyFirst, afterPublish}) async =>
            _mint(owner, namespace, lease, await _prepareMint(owner, namespace),
                conveyFirst: conveyFirst,
                afterPublish: afterPublish == null
                    ? null
                    : (published, _) async {
                        await afterPublish(published);
                        return null;
                      }));
    return next ?? advertisement;
  }

  @override
  Future<NskeyAdvertisement?> currentPublic(
      String owner, String namespace) async {
    final isOwn = owner == _atClient.getCurrentAtSign();
    if (isOwn) _listenForOwnChanges();

    final scope = _scope(owner, namespace);
    final cached = _remote[scope];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < advertisementTtl) {
      return cached.advertisement;
    }

    final String? payload;
    try {
      payload =
          await _getLocalThenRemote(nskeyAdvertisementKey(owner, namespace));
    } on StoppedException {
      rethrow;
    } catch (_) {
      final stale = _withinGrace(cached);
      if (stale != null) return stale;
      rethrow;
    }
    if (payload == null) {
      _remote.remove(scope);
      return null;
    }

    // NOTE: verifying fetches the signer's _apsk from the atServer, so
    // re-verifying unchanged bytes would stop a client writing its own data
    // once it had been offline longer than the TTL.
    final advertisement = isOwn && cached?.payload == payload
        ? cached!.advertisement
        : await verifier.verify(owner, payload);
    _remote[scope] = (
      advertisement: advertisement,
      fetchedAt: DateTime.now(),
      payload: payload,
    );
    return advertisement;
  }

  /// Files an advertisement this ring just published into local storage, so a
  /// local-first re-read finds it rather than the generation local storage
  /// held before.
  ///
  /// `cameFromServer: true` keeps the write out of the client→server sync
  /// queue: a queued entry carries only the key's *name*, so a drain landing
  /// later would push whatever local storage held by then back over the
  /// published generation. A failure is logged, since the advertisement is
  /// published and sync brings local storage the same copy.
  Future<void> _fileMinted(AtKey advertisementKey, String payload) async {
    try {
      await _atClient.getLocalSecondary()?.executeVerb(
          UpdateVerbBuilder()
            ..atKey = advertisementKey
            ..value = payload,
          cameFromServer: true);
    } on StoppedException {
      rethrow;
    } on Object catch (e) {
      _logger.warning('Published $advertisementKey but could not file it '
          'locally, so local storage holds the previous generation until sync '
          'pulls this one: $e');
    }
  }

  /// Reads [atKey], or null when the atServer says there is none; any other
  /// failure throws.
  ///
  /// For this client's own atSign, local storage first: [currentPublic] sits on
  /// the write path, so a round trip by default would break offline writes. The
  /// fallback to the atServer is what keeps a client that has just minted — or
  /// whose sibling enrollment minted a moment ago — from reading its own
  /// published namespace as a cold start until sync pulls the record down, and
  /// what the atServer answers is filed locally on the way back. Another
  /// atSign's public record is never held locally, so it is read from the
  /// atServer alone, and an offline write to a peer waits for the network.
  Future<String?> _getLocalThenRemote(AtKey atKey) async {
    if (atKey.sharedBy == _atClient.getCurrentAtSign()) {
      try {
        final local = await _atClient.get(atKey);
        if (local.value != null) return local.value as String;
      } on AtKeyNotFoundException {
        // NOTE: absent locally is the ordinary state for a record this device
        // has not synced, and the local keystore and the client's own
        // validation raise different types for it.
      } on KeyNotFoundException {
        // As above.
      }
    }
    final AtValue remote;
    try {
      remote = await _atClient.get(atKey,
          getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    } on AtKeyNotFoundException {
      return null;
    } on KeyNotFoundException {
      return null;
    }
    final value = remote.value as String?;
    if (value != null) await _fileFetched(atKey, value, remote.metadata);
    return value;
  }

  /// Files a value this client just fetched from the atServer into local
  /// storage, with the metadata the atServer answered with, unless local
  /// storage holds one by then — a copy sync landed, which sync keeps current,
  /// and which writing over could put back a generation sync has moved past.
  ///
  /// `cameFromServer: true` is what keeps the write out of the client→server
  /// sync queue: a queued entry carries the key's *name*, so a later drain
  /// would send whatever local storage holds by then, which can be a generation
  /// the atServer has already moved past.
  ///
  /// **Our own atSign only** — a peer's advertisement is not ours to publish,
  /// and for a peer the [advertisementTtl] cache is the mechanism. Failure is
  /// logged and swallowed, since the read already has its answer.
  Future<void> _fileFetched(
      AtKey atKey, String value, Metadata? fetchedMetadata) async {
    if (atKey.sharedBy != _atClient.getCurrentAtSign()) return;
    final filed = AtKey()
      ..key = atKey.key
      ..namespace = atKey.namespace
      ..sharedBy = atKey.sharedBy
      ..metadata = fetchedMetadata ?? (Metadata()..isPublic = true);
    try {
      await _atClient.getLocalSecondary()!.putIfAbsent(
          UpdateVerbBuilder()
            ..atKey = filed
            ..value = value,
          cameFromServer: true);
    } on StoppedException {
      rethrow;
    } on Object catch (e) {
      _logger.finer('could not file the fetched $atKey locally: $e');
    }
  }

  /// The cached advertisement, for a re-fetch that could not reach an answer,
  /// while [advertisementTtl] plus [advertisementStaleGrace] has not passed
  /// since it was fetched; past that, null, so the failure reaches the caller
  /// rather than sealing to a generation that may have been rotated away from.
  NskeyAdvertisement? _withinGrace(_CachedAdvertisement? cached) {
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

  /// The generation [publishedRecord] reads, without its record stamp.
  Future<NskeyAdvertisement?> publishedAdvertisement(
          String owner, String namespace) async =>
      (await publishedRecord(owner, namespace))?.advertisement;

  /// What `(owner, namespace)` has published **on the atServer**, read past
  /// local storage and this ring's own caches, and the atServer's own stamp on
  /// that record.
  ///
  /// Null means the atServer says there is none; any other failure throws,
  /// since a mint must not read an unreachable atServer as a cold start.
  ///
  /// ⚠️ **At this atSign's own address an advertisement that does not verify
  /// also reads as none**, so a corrupt or hostile write can be minted over;
  /// for a peer's address that failure propagates instead. Not being able to
  /// fetch what it is checked against, and an advertisement that verifies but
  /// names nothing this build can seal to, throw at both.
  Future<({NskeyAdvertisement advertisement, DateTime? updatedAt})?>
      publishedRecord(String owner, String namespace) async {
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
      if (owner != _atClient.getCurrentAtSign() ||
          !_replaceableOwnAdvertisement(e)) {
        rethrow;
      }
      _logger.warning(
          'Our own advertisement at ${nskeyAdvertisementKey(owner, namespace)} '
          'does not verify ($e) — treating it as unpublished so a mint can '
          'replace it');
      return null;
    }
    _remote[_scope(owner, namespace)] = (
      advertisement: advertisement,
      fetchedAt: DateTime.now(),
      payload: value.value as String,
    );
    return (advertisement: advertisement, updatedAt: value.metadata?.updatedAt);
  }

  @override
  Future<NskeyDecapsulationKey?> privateHalf(
      String owner, String namespace, String nskeyKid) async {
    final held = await heldPrivateHalf(owner, namespace, nskeyKid);
    if (held != null || owner != _atClient.getCurrentAtSign()) return held;
    if (!_askOnReadMiss) return null;

    // NOTE: no fetch and no ask for a generation no own advertisement names.
    if (!await _advertisedOwn(namespace, nskeyKid)) return null;

    await _fetchOnMiss(namespace, nskeyKid).timeout(fetchOnMissTimeout,
        onTimeout: () => _logger.info('The fetch of the conveyance records '
            'for $namespace:$nskeyKid has run past ${fetchOnMissTimeout.inMilliseconds}ms, '
            'so this miss asks the other enrollments while it goes on'));
    final fetched = await heldPrivateHalf(owner, namespace, nskeyKid);
    if (fetched != null) return fetched;

    // NOTE: the asking side does not file. Whoever supplies `requestConveyance`
    // owns waiting for the answer and filing it; nothing else does, so an ask
    // wired without that repairs the client only at its next start.
    _askForMissingPrivate(namespace, nskeyKid);
    return null;
  }

  /// How this ring fetches its own conveyance records, supplied or derived;
  /// null when there is no key source to file into.
  Future<void> Function()? get _fetch {
    final supplied = _fetchConveyance;
    if (supplied != null) return supplied;
    final keysIo = _atClient.atKeysIo;
    if (keysIo == null || privateFiling == null) return null;
    return () async {
      await collectConveyedKeyMaterial(_atClient, keysIo, ring: this);
    };
  }

  /// Fetches this enrollment's conveyance records at most once per
  /// [askCooldown], whichever generation missed, sharing a fetch already in
  /// flight: one fetch files every record waiting, not only the one missed.
  Future<void> _fetchOnMiss(String namespace, String nskeyKid) {
    final fetch = _fetch;
    if (fetch == null) return Future.value();
    final inFlight = _fetching;
    if (inFlight != null) return inFlight;
    final fetchedAt = _fetchedOnMiss;
    if (fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < askCooldown) {
      return Future.value();
    }
    _fetchedOnMiss = DateTime.now();
    final fetching = _fetchLogged(fetch, namespace, nskeyKid).whenComplete(() {
      _fetching = null;
    });
    _fetching = fetching;
    return fetching;
  }

  /// [fetch], with a failure logged rather than thrown, since the ask that
  /// follows is the fallback.
  Future<void> _fetchLogged(
      Future<void> Function() fetch, String namespace, String nskeyKid) async {
    try {
      await fetch();
    } catch (e) {
      if (e is StoppedException) rethrow;
      logSwallowed(
          _logger,
          e,
          'Could not fetch this enrollment\'s conveyance records for '
          '$namespace:$nskeyKid; asking the other enrollments instead: $e',
          routine: true);
    }
  }

  @override
  Future<PackageKey?> heldPublic(
      String owner, String namespace, String nskeyKid) async {
    if (owner != _atClient.getCurrentAtSign()) return null;
    final minted = _mintedPublics[_generation(owner, namespace, nskeyKid)];
    if (minted != null) return minted;
    final filed = (await privateFiling?.filedFor(namespace))
        ?.where((f) => f.nskeyKid == nskeyKid)
        .firstOrNull;
    if (filed == null) return null;
    final kem = SecretSharingAlgos.kemFor(filed.keyAlgo);
    if (kem == null) return null;
    final pair = await kem.keyPairFromSeed(filed.seed.bytes);
    final derived = PackageKey.fromBytes(
        use: SecretSharingAlgos.useEnc,
        alg: filed.keyAlgo,
        pub: pair.publicKey);
    // NOTE: a seed that re-derives some other kid is not this generation, and
    // sealing to it would leave a copy nobody opens under the kid it names.
    return derived.kid == nskeyKid ? derived : null;
  }

  /// What [privateHalf] answers, without asking the atSign's other enrollments
  /// for a private this client does not hold.
  Future<NskeyDecapsulationKey?> heldPrivateHalf(
      String owner, String namespace, String nskeyKid) async {
    final held = _ownPrivates[_generation(owner, namespace, nskeyKid)];
    if (held != null) return held;

    if (owner != _atClient.getCurrentAtSign()) return null;
    final filed = await privateFiling?.read(namespace, nskeyKid);
    if (filed != null) {
      _ownPrivates[_generation(owner, namespace, nskeyKid)] = filed;
    }
    return filed;
  }

  /// How this ring asks, supplied or derived.
  ///
  /// Built on the miss rather than in the constructor, so a fixture that only
  /// ever reads never constructs the substrate. Null when there is nowhere to
  /// file the answer, since asking without filing leaves the reply in the
  /// in-memory secret store and repairs the client at its next start rather
  /// than this one.
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

  /// Whether an own advertisement this ring holds names [nskeyKid]: the copy
  /// writes seal to, or the one a miss last read.
  bool _namesOwn(String namespace, String nskeyKid) {
    final owner = _atClient.getCurrentAtSign();
    if (owner == null) return false;
    final cached = _remote[_scope(owner, namespace)]
            ?.advertisement
            .keys
            .any((key) => key.kid == nskeyKid) ??
        false;
    return cached || (_kidsReadOnMiss[namespace]?.contains(nskeyKid) ?? false);
  }

  /// Whether this atSign advertises [nskeyKid] in [namespace].
  ///
  /// When no copy this ring holds names it, reads the published advertisement,
  /// at most once per [askCooldown] per namespace and only for a namespace
  /// [_knowsOwn] accepts.
  Future<bool> _advertisedOwn(String namespace, String nskeyKid) async {
    if (_namesOwn(namespace, nskeyKid)) return true;
    if (!await _knowsOwn(namespace)) return false;
    await _readOwnOnMiss(namespace).timeout(fetchOnMissTimeout,
        onTimeout: () => _logger.info('The read of the own advertisement for '
            '$namespace has run past ${fetchOnMissTimeout.inMilliseconds}ms, '
            'so this miss on $nskeyKid fetches and asks nothing'));
    return _namesOwn(namespace, nskeyKid);
  }

  /// Whether this ring holds an own advertisement for [namespace], or the
  /// keyfile holds an nskey private for it or names it among this
  /// enrollment's grants.
  Future<bool> _knowsOwn(String namespace) async {
    final owner = _atClient.getCurrentAtSign();
    if (owner == null) return false;
    if (_remote.containsKey(_scope(owner, namespace))) return true;
    final filing = privateFiling;
    if (filing == null) return false;
    if ((await filing.readAllWhere((ns) => ns == namespace)).isNotEmpty) {
      return true;
    }
    return _grantedOwn(filing.keysIo, owner, namespace);
  }

  /// Whether the keyfile's snapshot of this enrollment's record names
  /// [namespace] in its grants: as the enrollment request named them, and
  /// as each start reconciles them with the atServer's record.
  ///
  /// `*` and the atSign's own credential name no namespace here, since
  /// neither bounds the namespaces a record could name.
  Future<bool> _grantedOwn(
      AtKeysIo keysIo, String owner, String namespace) async {
    final enrollmentId = _atClient.enrollmentId;
    if (isAtSignCredential(enrollmentId) || !isSeedableNamespace(namespace)) {
      return false;
    }
    final AtKeys keys;
    try {
      keys = await keysIo.read(owner);
    } on AtKeysSourceAbsentException {
      return false;
    }
    final folded = namespace.toLowerCase();
    return keys
            .enrollmentInfo(enrollmentId!)
            ?.namespaces
            ?.keys
            .any((granted) => granted.toLowerCase() == folded) ??
        false;
  }

  /// Reads [namespace]'s own advertisement from the atServer at most once per
  /// [askCooldown], sharing a read already in flight.
  Future<void> _readOwnOnMiss(String namespace) {
    final inFlight = _readingOnMiss[namespace];
    if (inFlight != null) return inFlight;
    final now = DateTime.now();
    final readAt = _readOnMissAt[namespace];
    if (readAt != null && now.difference(readAt) < askCooldown) {
      return Future.value();
    }
    _readOnMissAt[namespace] = now;
    final reading = _readOwn(namespace).whenComplete(() {
      _readingOnMiss.remove(namespace);
    });
    _readingOnMiss[namespace] = reading;
    return reading;
  }

  /// Records the kids [namespace]'s published own advertisement names. A
  /// failure is logged and leaves what an earlier read recorded.
  Future<void> _readOwn(String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    try {
      final AtValue value;
      try {
        value = await _atClient.get(nskeyAdvertisementKey(owner, namespace),
            getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
      } on KeyNotFoundException {
        _kidsReadOnMiss.remove(namespace);
        return;
      } on AtKeyNotFoundException {
        _kidsReadOnMiss.remove(namespace);
        return;
      }
      final payload = value.value as String?;
      if (payload == null) {
        _kidsReadOnMiss.remove(namespace);
        return;
      }
      final cached = _remote[_scope(owner, namespace)];
      final advertisement = cached?.payload == payload
          ? cached!.advertisement
          : await verifier.verify(owner, payload);
      _kidsReadOnMiss[namespace] = {
        for (final key in advertisement.keys) key.kid
      };
    } catch (e) {
      if (e is StoppedException) rethrow;
      logSwallowed(
          _logger,
          e,
          'Could not read the own advertisement for $namespace, so a miss on '
          'a generation no copy this client holds names fetches and asks '
          'nothing until a read after the cooldown: $e',
          routine: true);
    }
  }

  /// Whether a read miss on an own generation will broadcast a pull: a ring
  /// that answers false cannot heal, however the rest of it is wired.
  @visibleForTesting
  bool get asksOnReadMiss => _askOnReadMiss && _ask != null;

  /// Asks the other enrollments for one missing own private, unless an ask
  /// for it is outstanding or went out within [askCooldown].
  void _askForMissingPrivate(String namespace, String nskeyKid) {
    final ask = _ask;
    if (ask == null) return;
    final generation = (namespace: namespace, nskeyKid: nskeyKid);
    if (_outstanding.containsKey(generation)) return;
    final now = DateTime.now();
    _askedAt
        .removeWhere((_, askedAt) => now.difference(askedAt) >= askCooldown);
    if (_askedAt.containsKey(generation)) return;

    final secretName = '${NskeyPrivateFiling.secretNamePrefix}$nskeyKid';
    noteOutstandingAsk(
        namespace,
        nskeyKid,
        ask(namespace, secretName).catchError((Object e) {
          // NOTE: the stamp stays, so an ask that keeps failing goes out at
          // most once per [askCooldown].
          logSwallowed(
              _logger,
              e,
              'Could not request the missing nskey private for '
              '$namespace:$nskeyKid, and a read miss once the ask cooldown '
              'has passed asks again: $e',
              routine: true);
        }));
  }

  /// Records an ask for `(namespace, nskeyKid)` whose answer is awaited until
  /// [outstanding] completes, so a read miss meanwhile asks nothing more.
  @internal
  void noteOutstandingAsk(
      String namespace, String nskeyKid, Future<void> outstanding) {
    final generation = (namespace: namespace, nskeyKid: nskeyKid);
    _askedAt[generation] = DateTime.now();
    _outstanding[generation] = outstanding;
    unawaited(outstanding.then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_outstanding[generation], outstanding)) {
        _outstanding.remove(generation);
      }
    }));
  }
}
