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
import 'package:at_client/src/util/swallowed_error.dart';
import 'package:meta/meta.dart' show experimental, visibleForTesting;

final _logger = AtSignLogger('PublishedNskeyKeyRing');

/// Asks this atSign's other enrollments for one missing nskey private, then
/// waits for a holder to answer and files the answer.
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
/// Does not defend against the operator of [owner]'s atServer, which serves
/// both the advertisement and the `_apsk` it is checked against and so can
/// substitute a consistent pair.
class ApkamSignedAdvertisedKeys implements AdvertisedKeyVerifier {
  final AtClientEnvelopeSigner _signer;

  ApkamSignedAdvertisedKeys(AtClient atClient)
      : _signer = AtClientEnvelopeSigner(atClient);

  @override
  Future<NskeyAdvertisement> verify(String owner, String payload) async {
    final SignedEnvelope envelope;
    try {
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
      throw AtSigningVerificationException(
          'the advertised nskey for $owner offers only key-establishment '
          'algorithms this build cannot encapsulate to '
          '(${advertisement.keys.map((k) => '"${k.alg}"').join(', ')}) — '
          'refusing rather than sealing under one it did not name');
    }
    if (sealable == 0) {
      throw AtSigningVerificationException(
          'the advertised nskey for $owner retires every key this build can '
          'encapsulate to, so it names nothing to seal to now');
    }
    return advertisement;
  }
}

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
  /// learns of one, and total exposure is this window plus one content-key
  /// lifetime.
  final Duration advertisementTtl;

  /// How far past [advertisementTtl] a *failed* re-fetch may keep serving the
  /// advertisement it already has, before this stops answering for the
  /// destination at all.
  ///
  /// A short grace absorbs an ordinary blip; past it the write fails rather
  /// than silently handing a revoked enrollment a key it can still open, since
  /// a peer that rotated *because of a revocation* is the one a sender most
  /// needs to stop sealing to.
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

  /// The filing a ring builds for itself when its caller named none, over the
  /// client's own `AtKeysIo`; null when the client has no key source at all.
  ///
  /// Two filings over one keyfile are safe, but they carry separate
  /// `privatesFiled` streams, so a caller that needs a filing's events must
  /// pass the instance it is listening to.
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
  /// The request is store-and-forward: any current holder answers when it next
  /// runs, and whoever supplies this owns waiting for the answer and filing it
  /// — see [requestAndFileNskeyPrivate]. Null is not silence, since a ring
  /// with a [privateFiling] derives its own ask; null with no filing to derive
  /// from is what turns asking off.
  final Future<void> Function(String namespace, String secretName)?
      _requestConveyance;

  /// When each generation was last asked for, so a burst of failed reads
  /// collapses to one broadcast without a generation ever falling permanently
  /// silent.
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
  final NskeyPrivateFiling? privateFiling;

  @override
  Stream<FiledNskeyPrivate> get privatesFiled =>
      privateFiling?.privatesFiled ?? const Stream<FiledNskeyPrivate>.empty();

  /// Signs this atSign's own advertisements.
  final AtClientEnvelopeSigner _signer;

  final Map<String, NskeyAdvertisement> _ownCurrent = {};

  /// Record a generation as this client's own, without minting one.
  ///
  /// For a test that needs a ring in the "already minted" state without a
  /// remote secondary; [mintAndPublish] is the production caller.
  @visibleForTesting
  void rememberOwn(
          String owner, String namespace, NskeyAdvertisement advertisement) =>
      _ownCurrent[_scope(owner, namespace)] = advertisement;

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
  final Map<String, ({NskeyAdvertisement advertisement, DateTime fetchedAt})>
      _remote = {};

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
  Future<NskeyAdvertisement> mintAndPublish(String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final prepared = await _prepareMint(owner, namespace);
    final minted = await mintLock.withLock(
        nskeyMintLockKey(owner, namespace, ttl: lockTtl),
        (lease) => _mintUnlessPublished(owner, namespace, lease, prepared),
        // NOTE: safe only because this critical section re-reads what is
        // published and adopts it; `rotate` takes the same lock without this,
        // so that the cooldown binds it.
        ownLockIsNotContention: true);
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

    throw StateError(
        'another enrollment holds the mint lock for $owner:$namespace and has '
        'published no advertisement yet, so this client has no namespace key '
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
  /// keeps every private this client already held, so records sealed to an
  /// earlier generation still open.
  ///
  /// Throws where [mintAndPublish] adopts — on losing the mint lock, and on
  /// finding nothing published to supersede.
  Future<({NskeyAdvertisement rotated, NskeyAdvertisement superseded})> rotate(
      String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final superseded = await publishedAdvertisement(owner, namespace);
    if (superseded == null) {
      throw StateError(
          'nothing to rotate for $owner:$namespace — no nskey is published '
          'there, so this is a cold-start mint rather than a rotation');
    }

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
  /// generation, in place; returns the advertisement now published, or null if
  /// nothing was added.
  ///
  /// **Not a rotation.** Every existing key, id and status stays where it was,
  /// and the generation keeps its `createdAt` and its record stamp, so an add
  /// after a revocation cannot read as a generation minted after it.
  ///
  /// ⚠️ **The conveyance excludes nobody** — a child an enrollment self-spawned
  /// before being revoked receives what this add conveys.
  @experimental
  Future<NskeyAdvertisement?> add(String namespace) async {
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
        nskeyMintLockKey(owner, namespace, ttl: lockTtl), (lease) async {
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
          assertUpdatedAt: fresh.updatedAt);
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

  /// Files every private this mint produced, then publishes the advertisement,
  /// in that order and only while [lease] is still good.
  ///
  /// [assertUpdatedAt] is the record's own previous stamp, asserted back so the
  /// write does not move it — [add]'s discipline, and nothing else's. A
  /// rotation and a cold-start mint pass nothing and take a fresh stamp, which
  /// is what makes `updatedAt` mean *when this generation was minted*; never a
  /// locally computed time.
  Future<NskeyAdvertisement> _mint(
    String owner,
    String namespace,
    MintLease lease,
    _PreparedMint prepared, {
    DateTime? assertUpdatedAt,
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

    // NOTE: the atServer, and never a local write as well. A local write of a
    // sync-eligible key queues the key's *name*, and a drain sends whatever
    // local storage holds when it runs — so a drain landing in that window
    // pushes the superseded generation back over the one just published, and
    // nothing corrects it. Local storage still ends up with this record: sync
    // pulls it down as a server-originated change, which is the one write path
    // that never enqueues a push.
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
    // NOTE: falling through when this client has minted nothing is the point.
    // Another of the owner's enrollments, or this one after a restart, holds
    // no `_ownCurrent` entry while the advertisement sits on the owner's own
    // atServer, and reporting a published namespace as a cold start invites a
    // mint that rotates the key out from under every peer.
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
      return _staleOrNothing(cached);
    }

    final advertisement = await verifier.verify(owner, payload);
    _remote[scope] = (advertisement: advertisement, fetchedAt: DateTime.now());
    return advertisement;
  }

  /// Reads [atKey] from local storage, falling back to the atServer when it is
  /// not held there.
  ///
  /// Local first because [currentPublic] sits on the write path, so a round
  /// trip by default would break offline writes; the fallback is what keeps a
  /// client that has just minted — or whose sibling enrollment minted a moment
  /// ago — from reading its own published namespace as a cold start until sync
  /// pulls the record down. What the atServer answers is filed locally on the
  /// way back.
  Future<String?> _getLocalThenRemote(AtKey atKey) async {
    try {
      final local = await _atClient.get(atKey);
      if (local.value != null) return local.value as String;
    } on AtKeyNotFoundException {
      // NOTE: absent locally is the ordinary state for a record this device
      // has not synced, and the local keystore and the client's own validation
      // raise different types for it.
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
  /// `cameFromServer: true` is what keeps the write out of the client→server
  /// sync queue: a queued entry carries the key's *name*, so a later drain
  /// would send whatever local storage holds by then, which can be a generation
  /// the atServer has already moved past.
  ///
  /// **Our own atSign only** — a peer's advertisement is not ours to publish,
  /// and for a peer the [advertisementTtl] cache is the mechanism. Failure is
  /// logged and swallowed, since the read already has its answer.
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

  /// The generation [publishedRecord] reads, without its record stamp.
  Future<NskeyAdvertisement?> publishedAdvertisement(
          String owner, String namespace) async =>
      (await publishedRecord(owner, namespace))?.advertisement;

  /// What `(owner, namespace)` has published **on the atServer**, fetched with
  /// both caches skipped, and the atServer's own stamp on that record.
  ///
  /// Null means the atServer says there is none; any other failure throws,
  /// since a mint must not read an unreachable atServer as a cold start.
  ///
  /// ⚠️ **At this atSign's own address an advertisement that does not verify
  /// also reads as none**, so a corrupt or hostile write can be minted over;
  /// for a peer's address that failure propagates instead.
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
      if (owner != _atClient.getCurrentAtSign()) rethrow;
      _logger.warning(
          'Our own advertisement at ${nskeyAdvertisementKey(owner, namespace)} '
          'does not verify ($e) — treating it as unpublished so a mint can '
          'replace it');
      return null;
    }
    _remote[_scope(owner, namespace)] =
        (advertisement: advertisement, fetchedAt: DateTime.now());
    return (advertisement: advertisement, updatedAt: value.metadata?.updatedAt);
  }

  @override
  Future<NskeyDecapsulationKey?> privateHalf(
      String owner, String namespace, String nskeyKid) async {
    final held = _ownPrivates[_generation(owner, namespace, nskeyKid)];
    if (held != null) return held;

    if (owner != _atClient.getCurrentAtSign()) return null;
    final filed = await privateFiling?.read(namespace, nskeyKid);
    if (filed != null) {
      _ownPrivates[_generation(owner, namespace, nskeyKid)] = filed;
      return filed;
    }

    // NOTE: the asking side does not file. Whoever supplies `requestConveyance`
    // owns waiting for the answer and filing it; nothing else does, so an ask
    // wired without that repairs the client only at its next start.
    _askForMissingPrivate(namespace, nskeyKid);
    return null;
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

  /// Whether a read miss on an own generation will broadcast a pull: a ring
  /// that answers false cannot heal, however the rest of it is wired.
  @visibleForTesting
  bool get asksOnReadMiss => _ask != null;

  void _askForMissingPrivate(String namespace, String nskeyKid) {
    final ask = _ask;
    if (ask == null) return;
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
      // NOTE: clear the stamp, so the next miss re-asks rather than waiting out
      // a cooldown earned by a request that never went out.
      _askedConveyance.remove(generation);
      logSwallowed(
          _logger,
          e,
          'Could not request the missing nskey private for '
          '$namespace:$nskeyKid, and the next read miss will ask again: $e',
          routine: true);
    }));
  }
}
