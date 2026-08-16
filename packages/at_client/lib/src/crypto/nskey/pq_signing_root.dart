import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        ApskSigningKey,
        AtKeys,
        AtKeysIo,
        AtKeysMaterial,
        CryptographicKeyType,
        KeyEntryStatus,
        KeyPartStatus,
        WrittenAtKeysIo,
        apskAdvertisement,
        apskSigningKeys,
        publicKeyKid;
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_client/src/crypto/nskey/mint_lock.dart'
    show MintLease, MintLock;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show
        pqSigningRootKey,
        mintLockTtl,
        pqSigningRootMintLockKey,
        pqSigningRootRecordName;
import 'package:at_client/src/crypto/nskey/pq_signing_chain.dart'
    show PqSigningChain;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart'
    show AtBytes, AtKey, AtKeyNotFoundException, AtValue, KeyNotFoundException;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('PqSigningRoot');

/// The atSign's user-owned root of trust: `public:pq_signing_root@<atSign>`.
///
/// ML-DSA-65, and a **signer only** — nothing is ever encapsulated to it. It
/// anchors the chain that vouches for enrollment signing keys, so that a
/// verifier is not left trusting whatever served the record.
///
/// **One root per atSign, and the interlock is a lock rather than the
/// record.** The record is mutable — it is an advertisement of signing keys,
/// and retiring one entry beside its successor is a rewrite, which an
/// immutable record makes unimplementable. What immutability was actually
/// doing is stopping two privileged enrollments each finding no root and each
/// minting one, and that job now sits on `_rootlock@<atSign>`, a short-ttl
/// immutable self key ([MintLock]).
///
/// ⚠️ **A lock is a protocol, not a guarantee.** A refused second create was
/// an absolute answer from the atServer; a lock is a window narrowed to its
/// ttl. What covers the difference is the reconciliation that was already
/// here for a lost create and is unchanged: read the published record, judge
/// what is held against it, retire a private that corresponds to nothing it
/// advertises ([reconcileHeldPrivate]). Two roots would still be
/// unrecoverable — one half of the atSign's enrollments chaining to a root the
/// other half rejected — so nothing here trusts the lock alone.
///
/// Only a **fully privileged** enrollment mints it — `rw` on `*` *and*
/// `__manage`. A namespace-restricted enrollment has no business minting the
/// key that vouches for every other enrollment, and could not convey it to the
/// privileged ones anyway.
@experimental
class PqSigningRoot {
  static const String recordName = pqSigningRootRecordName;

  /// The `AtKeys` role every root keypair is filed under, completed by an
  /// algorithm and a generation: `root:mldsa65:1`, then `:2`, `:3`, … It
  /// carries no namespace — the root is atSign-level, which is exactly what
  /// distinguishes it from an nskey — and it lives in the atSign's own
  /// container rather than any enrollment's.
  ///
  /// Key material is never removed from `AtKeys`, only retired, so the
  /// generation IS the slot: when generation 1 holds the dead remains of a
  /// lost create, a later private files under 2 rather than over it. Readers
  /// go through [privateHalf], which returns the active private the record
  /// says may sign — not simply the first slot holding one.
  ///
  /// ⚠️ Not the record name. The published record is
  /// `public:pq_signing_root@<atSign>` ([recordName]), which is a wire value
  /// and frozen; this is at-rest, where the document is the only reader.
  static const String keyIdRole = 'root';

  /// The `AtKeys` id prefix a root of [algorithm] is filed under.
  ///
  /// Parameterised rather than a constant because the algorithm is part of the
  /// id, and a root of one algorithm must be replaceable by a root of another:
  /// a build that only ever composes `root:mldsa65:` can file no successor
  /// that is not also ML-DSA-65. What *finds* a slot is [keyIdRole] alone —
  /// `AtKeys.isRoleKeyId` matches every algorithm, so a reader is never the
  /// thing that pins the atSign to one.
  static String keyIdPrefixFor(String algorithm) =>
      AtKeys.keyIdPrefix(keyIdRole, algorithm);

  /// Reserved [Secret] name the private travels under.
  ///
  /// Per-enrollment, so [PairwiseSecretSharing.shareAllSecretsWith] never
  /// forwards it: a namespace-scoped enrollment authorised for whatever
  /// namespace the envelope rode would otherwise be handed the key that
  /// vouches for every enrollment on the atSign.
  static const String secretName =
      '${PairwiseSecretSharing.perEnrollmentSecretPrefix}pqSigningRoot';

  /// The published record's version, so a later shape can be told from this
  /// one rather than guessed at.
  static const int currentVersion = 1;

  /// The algorithm a root key is published under.
  ///
  /// `SigningAlgoType.mldsa65`, whose `.name` is what `_apsk` advertises — the
  /// root is an ordinary signing key and says so in the same word every other
  /// signing key uses. It now agrees with [PqSigningChain.rootLinkAlgo], which
  /// has always spelled it this way.
  ///
  /// ⚠️ It used to be the hyphenated `'ml-dsa-65'`, chosen to match the
  /// key-*establishment* vocabulary (`x-wing`, `ml-kem-1024`) that the root
  /// has no part in — nothing is ever encapsulated to a signer. Two spellings
  /// for one algorithm across two records was the accident, not the design.
  static const SigningAlgoType rootKeyAlgo = SigningAlgoType.mldsa65;

  /// [rootKeyAlgo] in the vocabulary `AtKeys` files material under — the same
  /// word, and the one this class composes slot ids from.
  ///
  /// Pinned against `KeyAlgorithmType.mlDsa65` rather than written as it,
  /// because the enum and that constant are separate declarations that agree
  /// today: an id composed from one and material filed under the other would
  /// stop matching the moment either moved, and nothing would go red on the
  /// way past.
  static String get rootKeyAlgoToken => rootKeyAlgo.name;

  /// The algorithms this build can **check** a root signature under.
  ///
  /// Deliberately separate from [rootKeyAlgo], which is the one this build
  /// *mints*. A verifier has to keep working across a change of minting
  /// algorithm — that is what makes the root replaceable at all — so the two
  /// questions cannot share one constant. Widening this set is how a second
  /// algorithm becomes readable; widening [rootKeyAlgo] is how it becomes the
  /// one new roots are minted under, and those are separate decisions taken at
  /// separate times.
  ///
  /// An advertised entry outside this set is **skipped**, not refused: a
  /// record may legitimately carry a root this build has no code for, and
  /// refusing the whole record over it would make every future algorithm a
  /// breaking change for every client that predates it.
  static const Set<SigningAlgoType> verifiableRootAlgos = {
    SigningAlgoType.mldsa65,
  };

  final AtClient atClient;
  final AtKeysIo? keysIo;

  /// Serialises minting between this atSign's own privileged enrollments, now
  /// that the record itself no longer refuses a second create.
  ///
  /// Injectable so a test can stage contention without a live atServer; null
  /// wires the real one.
  final MintLock mintLock;

  PqSigningRoot(this.atClient,
      {this.keysIo, MintLock? mintLock, this.lockTtl = mintLockTtl})
      : mintLock = mintLock ?? MintLock(atClient);

  /// How long this client holds the root's mint lock once it has taken it.
  ///
  /// Expiry is the only thing that releases it, so this is the cooldown before
  /// another election may be held for the root — and it is also the winner's
  /// own budget, since a holder that overruns it abandons rather than
  /// publishing. A parameter for the same reason
  /// `PublishedNskeyKeyRing.lockTtl` is: a caller whose tolerance differs from
  /// the protocol default should state it rather than fork the composer.
  final Duration lockTtl;

  AtKey keyFor(String atSign) => pqSigningRootKey(atSign);

  /// The **active** root public key the record advertises, or null when the
  /// atServer confirms there is no root.
  ///
  /// Singular on purpose, and it is not "the first entry": it is the one entry
  /// whose `status` is active. Once the record can carry a retired predecessor
  /// beside its successor, "the first" and "the current" stop being the same
  /// key, and every caller here wants the current one — what to *sign* with,
  /// and what a freshly minted pair must correspond to.
  ///
  /// Verification wants [publishedPublicKeys] instead: a signature made before
  /// a rotation verifies under the retired key, which is exactly why a retired
  /// entry stays advertised.
  ///
  /// A record that cannot be read or decoded right now **throws** — absent and
  /// unreadable are different answers, and a caller that mints on this must
  /// not be allowed to guess.
  static Future<Uint8List?> publishedPublicKey(
          AtClient atClient, String atSign) async =>
      (await publishedPublicKeys(atClient, atSign, activeOnly: true))
          .firstOrNull;

  /// Every root public key the record advertises that this build can verify
  /// with — active first, then retired, in published order.
  ///
  /// Empty when the atServer confirms there is no root. [activeOnly] drops
  /// retired entries, which is what a signer or a correspondence check wants.
  static Future<List<Uint8List>> publishedPublicKeys(
    AtClient atClient,
    String atSign, {
    bool activeOnly = false,
  }) async =>
      [
        for (final root
            in await publishedRoots(atClient, atSign, activeOnly: activeOnly))
          base64Decode(root.pub)
      ];

  /// The advertised root entries themselves — active first, then retired.
  ///
  /// What [publishedPublicKeys] decodes, kept whole for callers that need more
  /// than the bytes. Checking a private against an entry needs the entry's
  /// **algorithm**, and a caller handed a bare `Uint8List` has to assume one —
  /// which is the assumption that pins an atSign to a single algorithm.
  static Future<List<ApskSigningKey>> publishedRoots(
    AtClient atClient,
    String atSign, {
    bool activeOnly = false,
  }) async {
    final AtValue value;
    try {
      value = await atClient.get(
        AtKey.fromString('public:$recordName$atSign'),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } on KeyNotFoundException {
      return const [];
    } on AtKeyNotFoundException {
      return const [];
    }
    final record = jsonDecode(value.value as String) as Map<String, dynamic>;
    return _rootsFrom(record, activeOnly: activeOnly);
  }

  /// The root entries in [record], read with the same codec `_apsk` uses.
  ///
  /// [apskSigningKeys] is the reader, not a copy of it: the root is an
  /// ordinary signing key and two parsers for one vocabulary are two chances
  /// to disagree. It already skips an entry whose `use` or `alg` this build
  /// has no code for — which is what lets a root be published under two
  /// algorithms without breaking readers that predate the second — and it
  /// keeps retired entries, because they are what verify what they signed.
  ///
  /// Filtered to [verifiableRootAlgos] rather than to [rootKeyAlgo]: what this
  /// build *mints* and what it can *check* are different questions, and using
  /// the minting constant for both is what would drop a root of a second
  /// algorithm on the floor the day one is published.
  ///
  /// Active entries come first regardless of published order, so a caller
  /// taking the head gets the current key rather than the earliest one.
  static List<ApskSigningKey> _rootsFrom(
    Map<String, dynamic> record, {
    bool activeOnly = false,
  }) =>
      apskSigningKeys(record)
          .where((e) => verifiableRootAlgos.contains(e.alg))
          .where((e) => !activeOnly || e.status == KeyEntryStatus.active)
          .toList()
        ..sort((a, b) => a.status == b.status
            ? 0
            : a.status == KeyEntryStatus.active
                ? -1
                : 1);

  /// Mints and publishes the root if this atSign has none, filing both halves
  /// of the pair first. Returns the public half, or null when this client did
  /// not mint (it is not privileged, one is already published, or another of
  /// this atSign's enrollments holds the mint lock).
  ///
  /// Both halves are filed, not just the private: recovery from a crash
  /// between filing and publishing needs the public bytes to republish, and
  /// they cannot be derived from the private. A keyfile found holding an
  /// active pair with no record published is exactly that crash, and the held
  /// public is republished rather than a fresh pair minted — publishing a new
  /// pair would strand the filed private against a record it never matched.
  ///
  /// **The record is read twice, and that is the point of the lock.** The
  /// first read is outside it, so an atSign that already has a root never
  /// takes a lock at all — which is the second and later retrofit of one
  /// atSign, not a per-start saving: nothing on a client start calls this. The
  /// read is then repeated *under* the lock, because a winner that published
  /// between the two is invisible to the first one, and with a mutable record
  /// nothing else would stop this mint overwriting it.
  ///
  /// A client that cannot take the lock mints nothing and files nothing —
  /// there is no losing pair to retire, because it never generated one. The
  /// every-start pull is how it gets the private from the winner.
  ///
  /// ⚠️ **The window the lock leaves open, stated rather than implied.** The
  /// ttl can expire while the holder is still inside the critical section,
  /// which lets a second minter in — so the holder carries its [MintLease] and
  /// refuses to publish once it is spent. That turns "two roots" into "one
  /// root, by whoever won the next election", which is the property wanted.
  /// The second window, a late holder deleting its successor's lock, is gone
  /// with the delete itself: nothing releases a lock now but its ttl.
  ///
  /// What covers a publish that still slips through is not the lock: it is
  /// [reconcileHeldPrivate] on every start, which retires a private the record
  /// does not advertise so the pull can heal that enrollment. Anchoring is
  /// deliberately outside the lock to keep the critical section down to a
  /// re-read, a keygen, a keyfile write and one publish.
  Future<Uint8List?> mintIfAbsent({required bool isFullyPrivileged}) async {
    final atSign = atClient.getCurrentAtSign()?.toAtsign();
    if (atSign == null) return null;

    if (!isFullyPrivileged) {
      _logger.info('Not minting the signing root for $atSign: this enrollment '
          'is not fully privileged, so it receives the root rather than '
          'creating it');
      return null;
    }

    // Confirmed-absent or throws; an unreadable record must abort the mint
    // rather than risk a second root.
    final roots = await publishedRoots(atClient, atSign);

    if (roots.isNotEmpty) {
      await _reconcileAgainstPublished(atSign, roots);
      _logger.info(
          'Not minting a signing root for $atSign: one is already published');
      return null;
    }

    final outcome = await mintLock.withLock(
        pqSigningRootMintLockKey(atSign, ttl: lockTtl),
        (lease) => _mintUnderLock(atSign, lease));
    if (outcome == null) {
      // Deliberately not a wait. The winner ends with a root published, so a
      // later start reads it; and this enrollment's route to the private is
      // the pull, which does not depend on having minted anything.
      _logger.info('Not minting a signing root for $atSign: another of this '
          'atSign\'s enrollments holds the mint lock');
      return null;
    }
    final publicKey = outcome.publicKey;
    if (publicKey == null) return null;

    // Outside the lock on purpose. Anchoring is this enrollment's own business
    // — it writes `_apsk`, not the root record — so it needs no interlock, and
    // every round trip left inside the critical section is one the ttl has to
    // cover.
    await _anchorSelf(atSign);
    return publicKey;
  }

  /// Mints, or finishes publishing a pair a crash left filed, with the mint
  /// lock held. A null `publicKey` means this client published nothing.
  ///
  /// Returns a record rather than a bare `Uint8List?` so that [MintLock]'s own
  /// null — "somebody else holds the lock" — stays distinguishable from "I
  /// held the lock and did not publish". Collapsing the two would report a
  /// lost lock as a completed mint that produced nothing, and the log would
  /// name the wrong reason on the one path where the reason is the finding.
  Future<({Uint8List? publicKey})> _mintUnderLock(
      String atSign, MintLease lease) async {
    // The absence check in [mintIfAbsent] ran BEFORE the lock was taken, so a
    // winner that published in that window is invisible to it. Re-reading here
    // is what closes it: with a mutable record, minting on a stale absence
    // overwrites the root it thought was missing, which is the one outcome the
    // interlock exists to prevent.
    final roots = await publishedRoots(atClient, atSign);
    if (roots.isNotEmpty) {
      await _reconcileAgainstPublished(atSign, roots);
      _logger.info('Not minting a signing root for $atSign: one was published '
          'between the absence check and this mint taking the lock');
      return (publicKey: null);
    }

    // Below here the record is ABSENT, so correspondence is undefined by
    // construction — there is nothing to correspond to. The question is the
    // crash-recovery one, "is there a pair I must finish publishing rather
    // than mint over", and the keyfile alone answers it.
    final AtKeys? keys = await _readKeys(atSign);
    final held = keys == null ? null : _activePrivates(keys).firstOrNull;

    if (held != null) {
      final heldPublic = keys!
          .getAtSignKey(held.keyId, CryptographicKeyType.publicVerification);
      if (heldPublic != null) {
        // The crash between filing and publishing: finish the publish with
        // the pair already filed.
        return (
          publicKey: await _publish(atSign, held.keyId,
              Uint8List.fromList(heldPublic.bytes.bytes), lease)
        );
      }
      // A private with no public half to republish predates pairs being
      // filed whole. Nothing was ever published for it, so no verifier ever
      // accepted anything against it — retiring it and minting fresh loses
      // nothing.
      await _retireSlot(atSign, held.keyId);
      _logger.warning('Retired a signing root private held for $atSign with '
          'no published record and no filed public half to republish; '
          'minting a fresh root');
    }

    final pair = await MlDsa65PureDartAlgo().generateKeyPair();

    // Durable before published, for the same reason minting an nskey is: a
    // published root whose private did not survive strands every enrollment on
    // the atSign against a key nobody holds. The record being mutable makes
    // that repairable in principle and D1 builds no rotation to repair it
    // with, so the ordering stands.
    final stored = await _storeFreshPair(atSign, pair);
    if (stored.overtaken) {
      // The mint lock serialises this atSign's ENROLLMENTS; it does not
      // serialise two tasks inside this client. `held` was read before an
      // ML-DSA keygen — and before a retire, on the orphan path — and
      // `AtClientImpl` fires the PQ start unawaited beside this, filing
      // whatever a peer conveys. The freshly minted pair is discarded rather
      // than filed: nothing was published for it, so no verifier ever saw it.
      _logger.info('Abandoned the signing root mint for $atSign: a root '
          'private arrived while this mint was generating, and it is the one '
          'a peer conveyed rather than the one this client just made');
      return (publicKey: null);
    }
    final slot = stored.slot;
    if (slot == null) {
      throw StateError(
          'could not store the signing root private for $atSign, so it is '
          'deliberately not published — a root whose private nobody holds '
          'cannot be replaced without a rotation, which is not built');
    }
    return (publicKey: await _publish(atSign, slot, pair.publicKey, lease));
  }

  /// Reconciles what this keyfile holds against a record that turned out to be
  /// published after all.
  ///
  /// An active private that corresponds to no ADVERTISED entry is the poisoned
  /// leftover of a mint that lost, and while it stays active the pull's
  /// "already holding it" check can never fire — the one heal such an
  /// enrollment has. A private matching a retired entry is not that: it is a
  /// predecessor the record still vouches for.
  Future<void> _reconcileAgainstPublished(
      String atSign, List<ApskSigningKey> roots) async {
    final keys = await _readKeys(atSign);
    if (keys != null) await _retireUnadvertised(atSign, keys, roots);
  }

  /// Publishes [publicKey] as the root record, with the mint lock held.
  /// Returns [publicKey] when it is what the record ends up advertising, and
  /// null when nothing was published.
  ///
  /// The pair under [slot] is retired whenever the record does not come back
  /// naming this client's key — the write failed, or somebody else won a race
  /// the lock was meant to settle. It is **kept** only when the record cannot
  /// be read at all, because retiring a private whose write did land cannot be
  /// undone.
  ///
  /// A spent [lease] stops the write before it is attempted. The check lives
  /// here rather than at the call sites because this is the write: everything
  /// upstream — an ML-DSA keygen, a keyfile store, a retire — can take
  /// arbitrarily long on a suspended device, and a holder that overran its ttl
  /// is publishing on top of whichever enrollment legitimately took the lock
  /// next.
  Future<Uint8List?> _publish(
      String atSign, String slot, Uint8List publicKey, MintLease lease) async {
    if (lease.isSpent) {
      // Retired for the same reason the failed-write path retires: nothing was
      // published under this pair, so no verifier ever accepted anything
      // against it, and leaving it active would stop the pull's
      // "already holding it" check from ever firing for this enrollment.
      await _retireSlot(atSign, slot);
      _logger.warning('Abandoned the signing root mint for $atSign: the mint '
          'lock expired while this client was minting, so its root is '
          'deliberately not published and the private is retired — another '
          'enrollment may already hold the lock and be publishing its own');
      return null;
    }
    try {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = keyFor(atSign)
            // The `_apsk` advertisement composer, not a shape of its own: the
            // root is an ordinary signing key, so it is advertised in the
            // vocabulary every other signing key uses — `{kid, use, alg, pub}`
            // with `status` appearing only once a key is retired. `kid` is
            // derived from the key material rather than supplied, so a writer
            // cannot address one key and name another.
            //
            // `successor` is gone. It was reserved for a rotation pointer and
            // could never have held one: it was stamped null at mint inside a
            // record nothing rewrote, so it could only be written at a moment
            // when there was nothing to point at. A rotation adds an entry
            // here instead, exactly as `_apsk` already does.
            ..value = jsonEncode(apskAdvertisement(keys: [
              ApskSigningKey.forPublicKey(
                  alg: rootKeyAlgo, pub: base64Encode(publicKey))
            ])),
          sync: true);
    } catch (e) {
      // A throw here says the call failed, NOT what the atServer did — and the
      // pair of cases this had to tell apart has CHANGED. "The atServer
      // refused a second create" is gone: the record is mutable and the write
      // went out under the mint lock. What is left is three states, and only
      // the record can say which one happened.
      //
      // Getting the landed case wrong is still the expensive one: retiring the
      // pair for a root this client DID publish leaves every enrollment on the
      // atSign chaining to a key nobody holds, and D1 builds no rotation to
      // replace it with.
      //
      // Judged against EVERY advertised entry rather than the active one:
      // "did my write land" is a question about the record naming my key at
      // all, and an active-only read would answer no for a record that had
      // already moved on — which is a lost create, not a failed write, and
      // needs the other branch.
      final List<Uint8List> published;
      try {
        published = await publishedPublicKeys(atClient, atSign);
      } catch (e2) {
        _logger.severe('Could not publish the signing root for $atSign and '
            'cannot read the record to find out whether the write landed, so '
            'the minted pair is KEPT: retiring it would brick the atSign if '
            'the write did land. A later start reconciles it against the '
            'record. ($e / $e2)');
        return null;
      }

      if (published.any((p) => _sameBytes(p, publicKey))) {
        // The write landed and the failure was in reporting it. This client
        // holds the matching private, so it is the minter.
        _logger.warning('The signing root write for $atSign reported a '
            'failure but the published record is this client\'s key, so the '
            'write landed: $e');
        return publicKey;
      }

      // Either the write failed outright, or somebody else's root is
      // published — which the mint lock was supposed to prevent, so it expired
      // under this mint or the winner does not take one. Both mean this pair
      // corresponds to nothing any verifier ever saw, and it is RETIRED.
      //
      // ⚠️ It is tempting to keep it instead, on the reasoning that a mutable
      // record has no one chance to burn and a later start could republish.
      // Nothing would: [mintIfAbsent] runs at activation and at retrofit,
      // never on a start — `PqClientBootstrap` runs the reconcile, the pull
      // and the anchor, and no mint. A kept pair would therefore be permanent,
      // and it is not inert: it satisfies [requestPrivateIfAbsent]'s cheapest
      // guard so this enrollment never asks for the real root;
      // [reconcileHeldPrivate] cannot clear it, because that heal is silent
      // while nothing is published; and the start's anchor step signs a root
      // link with it, which `PqSigningChain.publishOwnRootLink` never rewrites.
      // Retiring re-opens the pull, which is the one heal that does run every
      // start.
      try {
        await _retireSlot(atSign, slot);
      } catch (e2) {
        _logger.severe('Lost the signing root for $atSign and could not retire '
            'the losing pair; until a later start retires it, this enrollment '
            'wrongly reads as holding the root: $e2');
      }
      _logger.warning(published.isEmpty
          ? 'Did not publish a signing root for $atSign: the write failed and '
              'no root is published, so the minted pair is retired and this '
              'enrollment pulls the root from whoever mints it. $e'
          : 'Did not publish a signing root for $atSign: the record advertises '
              'a root this client did not mint, despite this mint holding the '
              'lock. $e');
      return null;
    }

    return publicKey;
  }

  /// Anchors this enrollment to the root it just published.
  ///
  /// Immediately, because the minter holds both the private and its own record
  /// at this moment — waiting for the next start would leave a freshly minted
  /// root anchoring nothing at all.
  ///
  /// Its own guard, swallowing its own failure, because a failure here must
  /// not be conflated with a lost create: the root IS published and this
  /// client's private IS filed, and reporting it as a loss would tell the
  /// caller the opposite of what happened — and, since the caller retires the
  /// pair on a loss, would destroy the key to a record that exists.
  Future<void> _anchorSelf(String atSign) async {
    try {
      await PqSigningChain(atClient).publishOwnRootLink(
          isFullyPrivileged: () async => true, keysIo: keysIo);
    } catch (e) {
      _logger.warning('Minted the signing root for $atSign but could not '
          'anchor this enrollment to it; the next start retries: $e');
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Files [private] into `AtKeys`. Returns whether **this** private is
  /// durably held and active afterwards.
  ///
  /// ⚠️ The return value is about the private that was passed in, not about
  /// whether *some* root private is held. It used to be the latter, and the
  /// difference was invisible: a conveyed successor handed to a client already
  /// holding a predecessor was dropped by the guard, and `store` reported
  /// success anyway because the update itself had completed — so [file] logged
  /// "Filed the signing root private" for a key it had discarded.
  ///
  /// [heldCorrespondence] is supplied only when [private] has been established
  /// as the root the record calls **active**, and it names, per keyId, the
  /// advertised entry each already-held active private corresponds to.
  ///
  /// Supplying it retires **every** held active private as [private] is filed,
  /// because none of them can be the active root: one that matches an entry
  /// matches a retired one, and one that matches nothing is the poisoned
  /// leftover of a lost create. Both stop being active the moment the real key
  /// is in hand, and the map is what lets the log say which it was. Leaving
  /// either active would let it go on winning the "what do I sign with"
  /// question against the key that actually signs.
  /// [public] is the corresponding public half when the caller has it — a
  /// conveyed private arrives alone, but the advertised entry it was matched
  /// against carries the public bytes. Filing it lets this client name the key
  /// it signs with (see [signingKey]) without deriving it, which ML-DSA does
  /// not permit, and without re-reading the record on every signature.
  Future<bool> store(
    String atSign,
    Uint8List private, {
    Uint8List? public,
    Map<String, ApskSigningKey>? heldCorrespondence,
  }) async {
    final io = keysIo;
    if (io == null) return false;
    if (io is! WrittenAtKeysIo) {
      _logger.severe('Filed the signing root for $atSign in memory only — '
          'this AtKeysIo cannot persist, and a root private that does not '
          'survive the process is no root at all');
      return false;
    }
    final superseded = <({String keyId, bool wasAdvertised})>[];
    try {
      // One read-mutate-write, not three steps: a client's start fires this
      // and the namespace-key seeding as sibling unawaited tasks, and two
      // read-then-flush pairs on one keyfile lose whichever addition flushes
      // first.
      await io.update(atSign.toAtsign(), (keys) {
        final active = _activePrivates(keys).toList();
        // Already filed. Not an error and not a second slot: filing the same
        // bytes twice would leave two actives that no later reader can tell
        // apart.
        if (active.any((m) => _sameBytes(m.bytes.bytes, private))) return false;

        if (heldCorrespondence == null && active.isNotEmpty) return false;

        if (heldCorrespondence != null) {
          for (final material in active) {
            keys.retireAtSignKey(material.keyId);
            superseded.add((
              keyId: material.keyId,
              wasAdvertised: heldCorrespondence.containsKey(material.keyId),
            ));
          }
        }

        final slot = _freeSlot(keys, rootKeyAlgoToken);
        final createdAt = DateTime.now().toUtc();
        keys.addKey(AtKeysMaterial(
          keyId: slot,
          keyPartType: CryptographicKeyType.privateSigning,
          keyAlgorithmType: rootKeyAlgoToken,
          bytes: AtBytes(private),
          createdAt: createdAt,
        ));
        // Filed in the SAME update, never as a follow-on write: two halves of
        // one key arriving under two locks is how a keyfile ends up holding a
        // private whose public half a crash left behind.
        if (public != null) {
          keys.addKey(AtKeysMaterial(
            keyId: slot,
            keyPartType: CryptographicKeyType.publicVerification,
            keyAlgorithmType: rootKeyAlgoToken,
            bytes: AtBytes(public),
            createdAt: createdAt,
          ));
        }
        return true;
      });
    } catch (e) {
      _logger.severe('Cannot store the signing root private for $atSign: $e');
      return false;
    }
    for (final entry in superseded) {
      final because = entry.wasAdvertised
          ? 'the record advertises it as retired'
          : 'it corresponds to no root the record advertises, so it is the '
              'leftover of a lost create';
      // Warning for the unadvertised case: a private nothing vouches for was
      // being offered to other enrollments and signing links no verifier
      // would accept, and that is worth seeing rather than inferring.
      final message = 'Retired the signing root private in ${entry.keyId} for '
          '$atSign: $because, and the private just filed corresponds to the '
          'active entry';
      entry.wasAdvertised ? _logger.info(message) : _logger.warning(message);
    }
    // Re-read rather than trusting the callback: the update may have refused
    // the addition, and "is this private held" is a question about the store.
    final keys = await _readKeys(atSign);
    return keys != null &&
        _activePrivates(keys).any((m) => _sameBytes(m.bytes.bytes, private));
  }

  /// The root private this client signs with, or null if it holds none.
  ///
  /// Every caller of this is asking the same question — what do I sign a root
  /// link with, what do I convey to a new enrollment, what do I offer a puller,
  /// and may I skip the pull because I already have it — so the answer is the
  /// one key that may sign, never merely the first one filed.
  Future<Uint8List?> privateHalf(String atSign) async =>
      (await signingKey(atSign))?.private;

  /// The root private this client signs with, together with the `kid` naming
  /// which advertised key it is — null when this client holds none.
  ///
  /// The kid comes from the **public half filed beside the private**, never
  /// from the record's notion of which entry is active. Those can legitimately
  /// disagree: a client whose record has moved on still holds the predecessor,
  /// and a link stamped with the successor's kid over the predecessor's
  /// signature would fail a strict `kid` selection — a link that names one key
  /// and is signed by another reads as tampering, which is strictly worse than
  /// naming nothing.
  ///
  /// `kid` is null for a private filed before its public half was kept, which
  /// is why the link's field is optional and its absence means "try them all"
  /// rather than "reject".
  Future<({Uint8List private, String? kid})?> signingKey(String atSign) async {
    final AtKeys? keys = await _readKeys(atSign);
    if (keys == null) return null;
    final material = await _signingPrivate(atSign, keys);
    if (material == null) return null;
    final public =
        keys.getAtSignKey(material.keyId, CryptographicKeyType.publicVerification);
    return (
      private: Uint8List.fromList(material.bytes.bytes),
      kid: public == null
          ? null
          : publicKeyKid(Uint8List.fromList(public.bytes.bytes)),
    );
  }

  /// Files a root private that arrived over the substrate, first checking it
  /// corresponds to the published root. Returns whether it was stored.
  ///
  /// Ignores anything that is not a root private, so this can be pointed at
  /// the whole arrival stream.
  ///
  /// The correspondence check is what stops a compromised or buggy holder
  /// handing this enrollment a key that signs links no verifier will ever
  /// accept — and with no rotation built, filing the wrong bytes here sticks
  /// until a holder answers the pull. A refused or unverifiable private is
  /// not filed; the keyfile stays without one, so the every-start pull asks
  /// again and a correct answer heals it.
  Future<bool> file(String atSign, Secret secret) async {
    if (secret.name != secretName) return false;
    final Uint8List private;
    try {
      private = base64Decode(secret.value);
    } catch (e) {
      _logger.warning('Discarding a malformed signing root private: $e');
      return false;
    }

    final List<ApskSigningKey> roots;
    try {
      roots = await publishedRoots(atClient, atSign);
    } catch (e) {
      _logger.info('Cannot read the published signing root for $atSign right '
          'now, so the arriving private is not filed; it is re-requested at '
          'a later start: $e');
      return false;
    }
    if (roots.isEmpty) {
      _logger.warning('Discarding a signing root private conveyed to $atSign: '
          'the atSign publishes no root for it to correspond to');
      return false;
    }
    final matched = await _correspondingRoot(private, roots);
    if (matched == null) {
      _logger.warning('Discarding a signing root private conveyed to $atSign: '
          'it corresponds to no root the record advertises');
      return false;
    }

    // A retired key signs nothing, so a private matching only a retired entry
    // is not filed AT ALL — not beside an active one, and not into an empty
    // keyfile either.
    //
    // ⚠️ The empty case is the one that bit: `store`'s guard refuses a second
    // active, so "not filed beside an active one" was the whole rule only for
    // as long as something active was there to sit beside. With nothing held,
    // the guard did not fire and `AtKeysMaterial` defaults to active — the
    // predecessor became this keyfile's sole ACTIVE private, and the
    // single-private short circuit in [_signingPrivate] then returned it
    // without reading the record. The client signed root links with a key the
    // record calls retired. Refusing here rather than in `store` keeps the
    // "may this key sign" judgement in the one place that has the record.
    if (matched.status != KeyEntryStatus.active) {
      _logger.info('Not filing a signing root private conveyed to $atSign: the '
          'record advertises it as retired, so it can sign nothing. The pull '
          'asks again and a holder of the active root can answer');
      return false;
    }

    // A private matching the ACTIVE entry supersedes everything held: that is
    // the keyfile catching up with the record, not a rotation being performed
    // here.
    final stored = await store(atSign, private,
        public: base64Decode(matched.pub),
        heldCorrespondence: await _correspondenceByKeyId(atSign, roots));
    if (stored) {
      _logger.info('Filed the signing root private for $atSign');
    }
    return stored;
  }

  /// For each active root slot this keyfile holds, the advertised entry it
  /// corresponds to — absent from the map when it corresponds to none.
  ///
  /// Read before the store update rather than inside it: correspondence is a
  /// signature probe and the update's callback is synchronous, so the verdict
  /// has to be computed first and carried in.
  Future<Map<String, ApskSigningKey>> _correspondenceByKeyId(
      String atSign, Iterable<ApskSigningKey> roots) async {
    final keys = await _readKeys(atSign);
    if (keys == null) return const {};
    final verdict = <String, ApskSigningKey>{};
    for (final material in _activePrivates(keys)) {
      final matched = await _correspondingRoot(
          Uint8List.fromList(material.bytes.bytes), roots);
      if (matched != null) verdict[material.keyId] = matched;
    }
    return verdict;
  }

  /// Asks the atSign's other enrollments for the root private, when this one
  /// is entitled to hold it and does not. Returns how many key packages were
  /// asked — 0 when nothing was needed or nobody could be asked.
  ///
  /// **This is the only route left for an enrollment that missed the
  /// approval-time conveyance.** The root is atSign-level and carries no
  /// namespace, so it is excluded from the `enroll:listns` fan-out by
  /// construction; and nothing mints a replacement, because D1 builds the
  /// root's rotatability and not the rotation. Without a pull, such an
  /// enrollment stays without it forever.
  ///
  /// **Broadcast, not a wait.** This deliberately does not block on an answer.
  /// It runs during client start, where a timeout would be paid by every
  /// launch — including the overwhelming majority that need nothing — and a
  /// holder may not be online at this instant anyway. The request persists as
  /// an envelope on the atServer, any holder that comes online answers it, and
  /// the answer arrives as an ordinary secret that [filePendingPrivate] files
  /// at this or a later start. That is what "answered by any online holder and
  /// persisting until one answers" means in practice.
  ///
  /// Two guards, and both matter. Only a **fully privileged** enrollment asks,
  /// because only that class may hold the key that vouches for every
  /// enrollment on the atSign — asking would be refused, and asking anyway
  /// would tell every holder that something unentitled is looking for it. And
  /// only an enrollment that does **not already hold** it asks, because this
  /// is a fan-out to every key package in [namespace]: firing it on each start
  /// regardless would put a broadcast on the wire per launch per device, for
  /// nothing.
  Future<int> requestPrivateIfAbsent({
    required Future<bool> Function() isFullyPrivileged,
    required PairwiseSecretSharing sharing,
    required String namespace,
  }) async {
    final atSign = atClient.getCurrentAtSign()?.toAtsign();
    if (atSign == null) return 0;

    // Cheapest check first: holding it settles the question without a round
    // trip, and that is the common case for every enrollment that was online
    // when it was approved.
    if (await privateHalf(atSign) != null) return 0;

    // A client with no enrollment id is authenticating with the atSign's own
    // keys. It cannot ask even if it wanted to — enumerating the holders goes
    // through `enroll:listns`, which the atServer refuses without APKAM
    // authentication — and it has no reason to: it is the atSign, so its route
    // to a missing root is to mint one, not to request it. Without this guard
    // every legacy PKAM client would broadcast, be refused, and log a warning
    // on each start.
    //
    // Read off the lookup rather than `sharing.enrollmentId`, which substitutes
    // the sentinel `'primary'` when there is none and so is never null — a
    // guard written against it would be dead code that always fell through.
    if (atClient.getRemoteSecondary()?.atLookUp.enrollmentId == null) return 0;

    if (!await isFullyPrivileged()) {
      _logger.info('Not requesting the signing root for $atSign: this '
          'enrollment is not fully privileged, so it is not entitled to hold '
          'it');
      return 0;
    }

    final asked = await sharing
        .requestSecretsFromNamespace(namespace, names: [secretName]);
    _logger.info(asked == 0
        ? 'Wanted the signing root private for $atSign but found no other key '
            'package in $namespace to ask; the next start retries'
        : 'Asked $asked key package(s) in $namespace for the signing root '
            'private for $atSign; the answer is filed when it arrives');
    return asked;
  }

  /// Retires **every** held root private that corresponds to no root the
  /// record advertises. Returns whether anything was retired.
  ///
  /// Every one, not the first. This used to judge a single private chosen by
  /// filed order, so a second unadvertised one stayed active and went on
  /// answering "do I hold the root" with bytes no verifier accepts — the exact
  /// state this method exists to clear, surviving the method that clears it.
  ///
  /// **The heal for a keyfile that holds the wrong key**, and it has to run
  /// on the ordinary start path rather than only inside a mint. A private
  /// that corresponds to nothing published is not inert: it satisfies
  /// [requestPrivateIfAbsent]'s cheapest guard so this enrollment never pulls
  /// the real one; [store] treats it as "already held" and silently drops a
  /// correct private conveyed to it; the chain link gets signed with it,
  /// publishing an anchor that verifies as tampering; and [hydrateStore]
  /// offers it to other enrollments, whose own correspondence check rejects
  /// the bytes *after* their broadcast is spent. Nothing about that state
  /// decays on its own, so without this it is permanent.
  ///
  /// Deliberately silent when the atSign publishes no root, or when the
  /// record cannot be read: a private held before its record is published is
  /// the ordinary crash-recovery state, and an unreadable record is no
  /// evidence at all.
  Future<bool> reconcileHeldPrivate(String atSign) async {
    final AtKeys? keys = await _readKeys(atSign);
    if (keys == null) return false;
    if (_activePrivates(keys).isEmpty) return false;

    final List<ApskSigningKey> roots;
    try {
      roots = await publishedRoots(atClient, atSign);
    } catch (e) {
      _logger.info('Cannot check the signing root private held for $atSign '
          'against the published record right now: $e');
      return false;
    }
    if (roots.isEmpty) return false;
    return await _retireUnadvertised(atSign, keys, roots);
  }

  /// Retires every active root private in [keys] corresponding to no entry in
  /// [roots]. Returns whether anything was retired.
  ///
  /// The heal both the start path and the mint path need, in one place: they
  /// had the same logic written twice and only [reconcileHeldPrivate] was ever
  /// reasoned about.
  ///
  /// Judged against the whole advertised set, retired entries included — a
  /// predecessor the record still vouches for is not a leftover, and retiring
  /// it here would take a legitimate key out of service for being superseded.
  Future<bool> _retireUnadvertised(
      String atSign, AtKeys keys, List<ApskSigningKey> roots) async {
    // Materialised before any retire: _retireSlot writes through the same store
    // this was read from, so a lazy filter on `status == active` would be
    // re-evaluated against material it had just moved.
    final held = _activePrivates(keys).toList();
    var retired = false;
    for (final material in held) {
      if (await _correspondingRoot(
              Uint8List.fromList(material.bytes.bytes), roots) !=
          null) {
        continue;
      }
      await _retireSlot(atSign, material.keyId);
      _logger.warning('Retired the signing root private in ${material.keyId} '
          'held for $atSign: it corresponds to no root the record advertises. '
          'This enrollment can now ask a holder for the real one');
      retired = true;
    }
    return retired;
  }

  /// Primes the held root private into [sharing]'s secret store under
  /// [namespace], so this client can **answer** other enrollments' pulls.
  /// Returns whether anything was primed (false when no private is held).
  ///
  /// The supply side of [requestPrivateIfAbsent], and it has to run at every
  /// start: the request is answered from the responder's in-memory secret
  /// store, which a restart empties — without this re-prime, "any holder
  /// that comes online answers" would have no holder able to answer, ever,
  /// and the pull would be a broadcast into a world of deaf holders. Under
  /// [namespace] because that is where requesters ask: the request rides the
  /// requester's own app namespace, and the serve loop lists the store by
  /// the request's namespace.
  ///
  /// Serving what this primes is gated on the requester's privilege by
  /// [PairwiseSecretSharing.perEnrollmentSecretRequestGate] — priming makes
  /// the answer possible, not indiscriminate.
  Future<bool> hydrateStore(
      PairwiseSecretSharing sharing, String namespace) async {
    final atSign = atClient.getCurrentAtSign()?.toAtsign();
    if (atSign == null) return false;
    final private = await privateHalf(atSign);
    if (private == null) return false;
    // Awaited: the in-memory map is written synchronously either way, but
    // dropping the future would turn a persistence failure into an unhandled
    // async error and let this report success without one.
    await sharing.secretStore.putIfNewer(Secret(
      namespace: namespace,
      name: secretName,
      value: base64Encode(private),
    ));
    return true;
  }

  /// Files a conveyed root private waiting in the secret store, if there is
  /// one this client does not already hold. Returns whether it filed.
  ///
  /// The private has to reach `AtKeys`, not merely the secret store: that
  /// store is a transit buffer and in-memory by design, so a restart would
  /// leave a privileged enrollment holding nothing and unable to anchor
  /// itself. A root already published is not minted again to recover — the
  /// mint stands down the moment it reads one — so the private has to survive
  /// the process or be pulled from a holder.
  ///
  /// A store check rather than a subscription, matching
  /// `PqSigningChain.publishPendingLink`: it needs no lifecycle to own and no
  /// stream to still be listening at the right moment. A private arriving
  /// after this runs is filed at the next start, which costs nothing that
  /// matters — an enrollment reads *chained but unanchored* until then.
  Future<bool> filePendingPrivate(
      String atSign, Iterable<Secret> heldSecrets) async {
    final secret = heldSecrets.where((s) => s.name == secretName).firstOrNull;
    if (secret == null) return false;
    return file(atSign, secret);
  }

  /// Whether [private] is the private half of any of [roots] — settles "is
  /// this A root private for this atSign" without trusting whoever supplied
  /// it.
  ///
  /// **Any**, not "the active one". A record mid-rotation advertises the
  /// successor beside its retired predecessor, and both are the atSign's own
  /// root keys; a client holding either is holding something real, so judging
  /// a private against the single active entry declares a legitimate key
  /// poison. Which of them may *sign* is a separate question, answered where
  /// the signing happens.
  static Future<ApskSigningKey?> _correspondingRoot(
      Uint8List private, Iterable<ApskSigningKey> roots) async {
    for (final root in roots) {
      if (await _corresponds(private, root)) return root;
    }
    return null;
  }

  /// Whether [private] signs something [root] verifies. Bytes of the wrong
  /// shape cannot be that root's private, so a throwing sign or verify is
  /// simply false.
  ///
  /// The algorithm comes from the entry, never from [rootKeyAlgo]: checking a
  /// root of one algorithm with another's verifier answers a question nobody
  /// asked, and answers it "no" — which reads exactly like poison.
  static Future<bool> _corresponds(
      Uint8List private, ApskSigningKey root) async {
    final algo = verifierFor(root.alg);
    if (algo == null) return false;
    try {
      final signature = await algo.signBytes(_probe, secretKey: private);
      return await algo.verifyBytes(_probe,
          signature: signature, publicKey: base64Decode(root.pub));
    } catch (e) {
      return false;
    }
  }

  /// The signer/verifier for [alg], or null when this build has none.
  ///
  /// The one place [verifiableRootAlgos] is turned into code, so the set and
  /// the switch cannot disagree about what is supported. ⚠️ That sentence was
  /// false when it was written: `PqSigningChain` constructed its own
  /// `MlDsa65PureDartAlgo` at both root-link verifiers, so there were three
  /// places and only this one consulted the set. Both now come here, which is
  /// what makes the claim true rather than aspirational.
  static MlDsa65PureDartAlgo? verifierFor(SigningAlgoType alg) =>
      alg == SigningAlgoType.mldsa65 ? MlDsa65PureDartAlgo() : null;

  static final Uint8List _probe =
      Uint8List.fromList(utf8.encode('pq_signing_root correspondence probe'));

  /// A root slot: [keyIdRole], any algorithm, then a generation number.
  ///
  /// Delegated to `AtKeys`, which composes every such id — one grammar with
  /// one home, rather than a parse here that has to agree with a writer there.
  static bool _isRootSlot(String id) => AtKeys.isRoleKeyId(id, keyIdRole);

  /// Every active root private this keyfile holds, in filed order.
  ///
  /// Plural because a keyfile can legitimately hold more than one: a client
  /// mid-rotation is handed the successor while it still holds the
  /// predecessor, and the predecessor is not retired until something
  /// establishes that the record has moved on. Callers that need *the* one to
  /// sign with go through [_signingPrivate].
  ///
  /// Local and synchronous, and it must stay that way: [store] asks this
  /// question inside the store's own update callback, where the answer has to
  /// be available without a round trip.
  Iterable<AtKeysMaterial> _activePrivates(AtKeys keys) =>
      keys.atSignKeys.where((m) =>
          m.keyPartType == CryptographicKeyType.privateSigning &&
          m.status == KeyPartStatus.active &&
          _isRootSlot(m.keyId));

  /// The one active root private that the record says may sign — the active
  /// private corresponding to an **active** advertised entry.
  ///
  /// **The record is consulted only when there is a choice to make.** With at
  /// most one active private the answer is that private, and nothing remote
  /// happens. That is not an optimisation for its own sake: four production
  /// call sites reach this through [privateHalf] and document it as the cheap
  /// local check taken *before* a round trip, and one of them is on the
  /// approval path. Judging a lone private against the record here would also
  /// be a second heal for a poisoned keyfile — [reconcileHeldPrivate] owns
  /// that one, on the start path, where it can be reasoned about.
  ///
  /// The record's entries are the **outer** loop, so the record's order
  /// decides and the keyfile's insertion order does not. That is the whole of
  /// "the selector stops guessing".
  ///
  /// A record that cannot be read, or that advertises no active root this
  /// build can verify, leaves the keyfile's first as the answer. An unreadable
  /// record is no evidence, and a client that stopped anchoring, stopped
  /// answering pulls, and broadcast for a key it already held every time the
  /// atServer hiccupped would be a worse failure than one that occasionally
  /// signs with a superseded key.
  Future<AtKeysMaterial?> _signingPrivate(String atSign, AtKeys keys) async {
    final held = _activePrivates(keys).toList();
    if (held.length <= 1) return held.firstOrNull;

    final List<ApskSigningKey> advertised;
    try {
      advertised = await publishedRoots(atClient, atSign);
    } catch (e) {
      _logger.warning('$atSign holds ${held.length} active signing root '
          'privates and the record cannot be read to say which one signs, so '
          'the first filed is used: $e');
      return held.first;
    }
    // Nothing to go on: no record, or nothing in it this build can verify.
    // Distinct from a record that IS readable and calls every root it
    // advertises retired — that one is evidence, and it says nothing signs.
    if (advertised.isEmpty) {
      _logger.warning('$atSign holds ${held.length} active signing root '
          'privates and the record advertises no root this build can verify; '
          'the first filed is used');
      return held.first;
    }
    final active = advertised
        .where((e) => e.status == KeyEntryStatus.active)
        .toList();

    for (final entry in active) {
      for (final material in held) {
        if (await _corresponds(
            Uint8List.fromList(material.bytes.bytes), entry)) {
          return material;
        }
      }
    }
    _logger.warning('None of the ${held.length} active signing root privates '
        '$atSign holds corresponds to an active entry on the record; this '
        'client signs nothing with the root until one does');
    return null;
  }

  /// The next free slot for a root of [algorithm] — retired remains keep their
  /// generation forever, so a new private lands beside them, never over them.
  ///
  /// Generations count per algorithm, so an ML-DSA-65 root and a root of some
  /// later algorithm are each `:1` in their own line rather than competing for
  /// one counter.
  String _freeSlot(AtKeys keys, String algorithm) =>
      '${keyIdPrefixFor(algorithm)}'
      '${keys.nextAtSignGeneration(keyIdRole, algorithm)}';

  Future<AtKeys?> _readKeys(String atSign) async {
    final io = keysIo;
    if (io == null) return null;
    try {
      return await io.read(atSign);
    } catch (e) {
      _logger.info('No signing root material readable for $atSign: $e');
      return null;
    }
  }

  /// Files both halves of a freshly minted pair under one slot, durably.
  ///
  /// Returns the slot; a null slot means the pair could not be persisted, and
  /// `overtaken` means an active root private appeared while the mint was
  /// deciding, so nothing was filed.
  ///
  /// ⚠️ **The overtaken check has to be here, not in the caller.**
  /// [mintIfAbsent] establishes that it holds no active private, then awaits
  /// three times — the record fetch, a retire, and an ML-DSA keygen — before
  /// reaching this method. Its decision is therefore taken against a snapshot
  /// that a sibling can invalidate: `AtClientImpl` fires the PQ start
  /// unawaited, and that start files whatever private a peer has conveyed. The
  /// keyfile lock spans one `update`, never a read-decide-write across it, and
  /// nothing below refuses the second active either — at_auth's
  /// single-active-per-algorithm rule is **enrollment-scoped**, and the root is
  /// atSign-scope material with a null enrollment id. So the only place the
  /// question can be asked and answered atomically is inside this update.
  Future<({String? slot, bool overtaken})> _storeFreshPair(
      String atSign, ({Uint8List publicKey, Uint8List secretKey}) pair) async {
    final io = keysIo;
    if (io == null) return (slot: null, overtaken: false);
    if (io is! WrittenAtKeysIo) {
      _logger.severe('Filed the signing root for $atSign in memory only — '
          'this AtKeysIo cannot persist, and a root private that does not '
          'survive the process is no root at all');
      return (slot: null, overtaken: false);
    }
    try {
      // The slot is chosen inside the update, under whatever the store holds
      // across it: picking it from a snapshot read outside would let a sibling
      // take the same free slot, and `addKey` refuses a duplicate keyId.
      String? slot;
      var overtaken = false;
      await io.update(atSign.toAtsign(), (keys) {
        if (_activePrivates(keys).isNotEmpty) {
          overtaken = true;
          return false;
        }
        slot = _freeSlot(keys, rootKeyAlgoToken);
        final createdAt = DateTime.now().toUtc();
        keys.addKey(AtKeysMaterial(
          keyId: slot!,
          keyPartType: CryptographicKeyType.privateSigning,
          keyAlgorithmType: rootKeyAlgoToken,
          bytes: AtBytes(pair.secretKey),
          createdAt: createdAt,
        ));
        keys.addKey(AtKeysMaterial(
          keyId: slot!,
          keyPartType: CryptographicKeyType.publicVerification,
          keyAlgorithmType: rootKeyAlgoToken,
          bytes: AtBytes(pair.publicKey),
          createdAt: createdAt,
        ));
        return true;
      });
      return (slot: slot, overtaken: overtaken);
    } catch (e) {
      _logger.severe('Cannot store the signing root pair for $atSign: $e');
      return (slot: null, overtaken: false);
    }
  }

  /// Marks every material under [slot] dead and flushes. Dead rather than
  /// retired: these bytes never protected anything, and must never be
  /// mistaken for a key that did.
  Future<void> _retireSlot(String atSign, String slot) async {
    final io = keysIo;
    if (io is! WrittenAtKeysIo) return;
    await io.update(atSign.toAtsign(), (keys) {
      keys.retireAtSignKey(slot, to: KeyPartStatus.dead);
      return true;
    });
  }
}
