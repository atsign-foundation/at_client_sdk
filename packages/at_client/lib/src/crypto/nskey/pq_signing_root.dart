import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        ApskSigningKey,
        AtKeys,
        CryptographicMaterialAlgorithm,
        AtKeysIo,
        CryptographicMaterial,
        CryptographicMaterialRole,
        CryptographicMaterialStatus,
        WrittenAtKeysIo,
        apskAdvertisement,
        apskSigningKeys,
        publicKeyKid;
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, SigningAlgoType;
import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/client/request_options.dart'
    show GetRequestOptions;
import 'package:at_client/src/crypto/nskey/mint_lock.dart'
    show MintLease, MintLock;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show
        pqSigningRootKey,
        pqSigningRootMintLockKey,
        pqSigningRootRecordName,
        signingRootMintLockTtl;
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

/// The atSign's user-owned root of trust — an ML-DSA-65 signer published at
/// `public:pq_signing_root@<atSign>` that anchors the chain vouching for
/// enrollment signing keys.
///
/// One root per atSign: only a fully privileged enrollment mints one, and a
/// short-ttl lock on `_rootlock@<atSign>` ([MintLock]) serialises them, the
/// mutable record itself refusing nothing.
@experimental
class PqSigningRoot {
  static const String recordName = pqSigningRootRecordName;

  /// The `AtKeys` role every root keypair is filed under, completed by an
  /// algorithm and a generation: `root:mldsa65:1`, then `:2`, `:3`, …
  ///
  /// ⚠️ Not the record name: [recordName] is the wire value, this is at-rest.
  static const String keyIdRole = 'root';

  /// The `AtKeys` id prefix a root of [algorithm] is filed under.
  static String keyIdPrefixFor(CryptographicMaterialAlgorithm algorithm) =>
      AtKeys.keyIdPrefix(keyIdRole, algorithm);

  /// Reserved [Secret] name the private travels under.
  ///
  /// Per-enrollment, so [PairwiseSecretSharing.shareAllSecretsWith] never
  /// forwards it to a namespace-scoped enrollment, which has no business
  /// holding the key that vouches for every enrollment on the atSign.
  static const String secretName =
      '${PairwiseSecretSharing.perEnrollmentSecretPrefix}pqSigningRoot';

  /// The published record's version, so a later shape can be told from this
  /// one rather than guessed at.
  static const int currentVersion = 1;

  /// The algorithm a root key is published under.
  ///
  /// Its `.name` is what `_apsk` advertises — the root is an ordinary signing
  /// key and says so in the same word every other signing key uses — and it
  /// matches [PqSigningChain.rootLinkAlgo], so one algorithm has one spelling
  /// across both records.
  static const SigningAlgoType rootKeyAlgo = SigningAlgoType.mldsa65;

  /// [rootKeyAlgo] in the vocabulary `AtKeys` files material under — the same
  /// word, and the one this class composes slot ids from.
  ///
  /// Derived from [rootKeyAlgo] rather than written as
  /// `CryptographicMaterialAlgorithm.mlDsa65`: an id composed from one and
  /// material filed under the other would stop matching the moment either
  /// moved, and nothing would go red on the way past.
  static CryptographicMaterialAlgorithm get rootKeyAlgoToken =>
      CryptographicMaterialAlgorithm.of(rootKeyAlgo.name);

  /// The algorithms this build can check a root signature under.
  ///
  /// An advertised entry outside this set is skipped, not refused, so a record
  /// carrying a root this build has no code for stays readable.
  static const Set<SigningAlgoType> verifiableRootAlgos = {
    SigningAlgoType.mldsa65,
  };

  final AtClient atClient;
  final AtKeysIo? keysIo;

  /// Serialises minting between this atSign's own privileged enrollments.
  ///
  /// Injectable so a test can stage contention without a live atServer; null
  /// wires the real one.
  final MintLock mintLock;

  PqSigningRoot(this.atClient,
      {this.keysIo, MintLock? mintLock, this.lockTtl = signingRootMintLockTtl})
      : mintLock = mintLock ?? MintLock(atClient);

  /// How long this client holds the root's mint lock once it has taken it.
  ///
  /// Expiry is the only thing that releases it, so this is both the cooldown
  /// before another election may be held for the root and the winner's own
  /// budget: a holder that overruns it abandons rather than publishing.
  final Duration lockTtl;

  /// The atKey the root record is published under for [atSign].
  AtKey keyFor(String atSign) => pqSigningRootKey(atSign);

  /// The active root public key the record advertises, or null when the
  /// atServer confirms there is no root; verification wants
  /// [publishedPublicKeys], which keeps the retired entries a signature made
  /// before a rotation verifies under.
  ///
  /// Throws when the record cannot be read or decoded: absent and unreadable
  /// are different answers, and a caller that mints on this must not guess.
  static Future<Uint8List?> publishedPublicKey(
          AtClient atClient, String atSign) async =>
      (await publishedPublicKeys(atClient, atSign, activeOnly: true))
          .firstOrNull;

  /// Every root public key the record advertises that this build can verify
  /// with — active first, then retired, in published order.
  ///
  /// Empty when the atServer confirms there is no root; [activeOnly] drops
  /// retired entries, which is what a signer wants.
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
  /// What [publishedPublicKeys] decodes, kept whole for callers that need the
  /// entry's algorithm rather than only its bytes: assuming one is what pins an
  /// atSign to a single algorithm.
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

  /// The root entries in [record] this build can verify, active first
  /// regardless of published order, so a caller taking the head gets the
  /// current key rather than the earliest one.
  ///
  /// Retired entries are kept: they are what verify what they signed.
  static List<ApskSigningKey> _rootsFrom(
    Map<String, dynamic> record, {
    bool activeOnly = false,
  }) =>
      apskSigningKeys(record)
          .where((e) => verifiableRootAlgos.contains(e.alg))
          .where((e) => !activeOnly || e.offeredForNewOperations)
          .toList()
        ..sort((a, b) => a.offeredForNewOperations == b.offeredForNewOperations
            ? 0
            : a.offeredForNewOperations
                ? -1
                : 1);

  /// Mints and publishes the root if this atSign has none, filing both halves
  /// of the pair first.
  ///
  /// Returns the public half, or null when this client did not mint: it is not
  /// fully privileged, a root is already published, or another of this atSign's
  /// enrollments holds the mint lock.
  Future<Uint8List?> mintIfAbsent({required bool isFullyPrivileged}) async {
    final atSign = atClient.getCurrentAtSign()?.toAtsign();
    if (atSign == null) return null;

    if (!isFullyPrivileged) {
      _logger.info('Not minting the signing root for $atSign: this enrollment '
          'is not fully privileged, so it receives the root rather than '
          'creating it');
      return null;
    }

    // NOTE: confirmed-absent or throws — an unreadable record must abort the
    // mint rather than risk a second root.
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
      _logger.info('Not minting a signing root for $atSign: the mint lock is '
          'already held, by another of this atSign\'s enrollments or by this '
          'one from a run inside the last couple of minutes');
      return null;
    }
    final publicKey = outcome.publicKey;
    if (publicKey == null) return null;

    await _anchorSelf(atSign);
    return publicKey;
  }

  /// Mints, or finishes publishing a pair a crash left filed, with the mint
  /// lock held. A null `publicKey` means this client published nothing.
  Future<({Uint8List? publicKey})> _mintUnderLock(
      String atSign, MintLease lease) async {
    // NOTE: this re-read is not redundant — [mintIfAbsent] checked absence
    // before the lock was taken, and with a mutable record, minting on a stale
    // absence overwrites a root published in that window.
    final roots = await publishedRoots(atClient, atSign);
    if (roots.isNotEmpty) {
      await _reconcileAgainstPublished(atSign, roots);
      _logger.info('Not minting a signing root for $atSign: one was published '
          'between the absence check and this mint taking the lock');
      return (publicKey: null);
    }

    final AtKeys? keys = await _readKeys(atSign);
    final held = keys == null ? null : _activePrivates(keys).firstOrNull;

    if (held != null) {
      final heldPublic = keys!.getAtSignKey(
          held.keyId, CryptographicMaterialRole.publicVerification);
      if (heldPublic != null) {
        return (
          publicKey: await _publish(atSign, held.keyId,
              Uint8List.fromList(heldPublic.bytes.bytes), lease)
        );
      }
      await _retireSlot(atSign, held.keyId);
      _logger.warning('Retired a signing root private held for $atSign with '
          'no published record and no filed public half to republish; '
          'minting a fresh root');
    }

    final pair = await MlDsa65PureDartAlgo().generateKeyPair();

    final stored = await _storeFreshPair(atSign, pair);
    if (stored.overtaken) {
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

  /// Reconciles what this keyfile holds against a record that is published
  /// after all.
  ///
  /// An active private corresponding to no vouching entry is the leftover of a
  /// mint that lost, and while it stays active the pull's "already holding it"
  /// check can never fire.
  Future<void> _reconcileAgainstPublished(
      String atSign, List<ApskSigningKey> roots) async {
    final keys = await _readKeys(atSign);
    if (keys != null) await _retireUnadvertised(atSign, keys, roots);
  }

  /// Publishes [publicKey] as the root record, with the mint lock held, and
  /// returns it when the record ends up advertising it — null when nothing was
  /// published.
  ///
  /// The pair under [slot] is retired unless the record cannot be read at all,
  /// and a spent [lease] stops the write before it is attempted.
  Future<Uint8List?> _publish(
      String atSign, String slot, Uint8List publicKey, MintLease lease) async {
    if (lease.isSpent) {
      await _retireSlot(atSign, slot);
      _logger.warning('Abandoned the signing root mint for $atSign: the mint '
          'lock expired while this client was minting, so its root is '
          'deliberately not published and the private is retired — another '
          'enrollment may already hold the lock and be publishing its own');
      return null;
    }
    try {
      await atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = keyFor(atSign)
        ..value = jsonEncode(apskAdvertisement(keys: [
          ApskSigningKey.forPublicKey(
              alg: rootKeyAlgo, pub: base64Encode(publicKey))
        ])));
    } catch (e) {
      // NOTE: a throw says the call failed, not what the atServer did, so only
      // the record can say whether the write landed — and it is judged against
      // EVERY advertised entry, since an active-only read answers no for a
      // record that has moved on, which is a different case entirely.
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
        _logger.warning('The signing root write for $atSign reported a '
            'failure but the published record is this client\'s key, so the '
            'write landed: $e');
        return publicKey;
      }

      // NOTE: the losing pair must be retired, not kept for a later start to
      // republish — [mintIfAbsent] never runs on a start, so a kept pair is
      // permanent, and it satisfies [requestPrivateIfAbsent]'s cheapest guard.
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
  /// Swallows its own failure: the root is published and the private filed, so
  /// the next start is free to retry.
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

  /// Files [private] into `AtKeys`, with [public] as its public half when the
  /// caller has one, and returns whether **this** private — not merely some
  /// root private — is durably held and active afterwards.
  ///
  /// Passing [heldCorrespondence], the advertised entry each already-held
  /// active private corresponds to, asserts [private] is the root the record
  /// calls active and retires all of them as it is filed.
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
    final superseded = <({String keyId, String? advertisedAs})>[];
    try {
      // NOTE: one read-mutate-write, not three steps — a client's start fires
      // this and the namespace-key seeding as sibling unawaited tasks, and two
      // read-then-flush pairs on one keyfile lose whichever addition flushes
      // first.
      await io.update(atSign.toAtsign(), (keys) {
        final active = _activePrivates(keys).toList();
        if (active.any((m) => _sameBytes(m.bytes.bytes, private))) return false;

        if (heldCorrespondence == null && active.isNotEmpty) return false;

        if (heldCorrespondence != null) {
          for (final material in active) {
            keys.retireAtSignKey(material.keyId);
            superseded.add((
              keyId: material.keyId,
              advertisedAs: heldCorrespondence[material.keyId]?.status,
            ));
          }
        }

        final slot = _freeSlot(keys, rootKeyAlgoToken);
        final createdAt = DateTime.now().toUtc();
        keys.addKey(CryptographicMaterial(
          keyId: slot,
          role: CryptographicMaterialRole.privateSigning,
          algorithm: rootKeyAlgoToken,
          bytes: AtBytes(private),
          createdAt: createdAt,
        ));
        if (public != null) {
          keys.addKey(CryptographicMaterial(
            keyId: slot,
            role: CryptographicMaterialRole.publicVerification,
            algorithm: rootKeyAlgoToken,
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
      final because = entry.advertisedAs != null
          ? 'the record advertises it as "${entry.advertisedAs}"'
          : 'it corresponds to no root the record advertises, so it is the '
              'leftover of a lost create';
      final message = 'Retired the signing root private in ${entry.keyId} for '
          '$atSign: $because, and the private just filed corresponds to the '
          'active entry';
      entry.advertisedAs != null
          ? _logger.info(message)
          : _logger.warning(message);
    }
    final keys = await _readKeys(atSign);
    return keys != null &&
        _activePrivates(keys).any((m) => _sameBytes(m.bytes.bytes, private));
  }

  /// The root private this client signs with — the one key the record says may
  /// sign, never merely the first filed — or null if it holds none.
  Future<Uint8List?> privateHalf(String atSign) async =>
      (await signingKey(atSign))?.private;

  /// The root private this client signs with, together with the `kid` naming
  /// which advertised key it is — null when this client holds none.
  ///
  /// A null `kid` means no public half is filed beside the private, and a
  /// reader takes its absence as "try them all" rather than "reject".
  Future<({Uint8List private, String? kid})?> signingKey(String atSign) async {
    final AtKeys? keys = await _readKeys(atSign);
    if (keys == null) return null;
    final material = await _signingPrivate(atSign, keys);
    if (material == null) return null;
    final public = keys.getAtSignKey(
        material.keyId, CryptographicMaterialRole.publicVerification);
    return (
      private: Uint8List.fromList(material.bytes.bytes),
      kid: public == null
          ? null
          : publicKeyKid(Uint8List.fromList(public.bytes.bytes)),
    );
  }

  /// Files a root private that arrived over the substrate, if it corresponds to
  /// a root the record advertises; returns whether it was stored.
  ///
  /// Ignores anything that is not a root private, so it can be pointed at the
  /// whole arrival stream, and files nothing whose correspondence it cannot
  /// establish.
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

    // NOTE: a private matching only a retired entry is not filed AT ALL — not
    // beside an active one, and not into an empty keyfile either. `store` has
    // no record to judge against and defaults a lone private to active, and the
    // single-private short circuit in [_signingPrivate] would then sign with a
    // key the record calls retired.
    if (!matched.offeredForNewOperations) {
      _logger.info('Not filing a signing root private conveyed to $atSign: the '
          'record advertises it as "${matched.status}", so it can sign '
          'nothing. The pull asks again and a holder of the active root can '
          'answer');
      return false;
    }

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
  /// Computed before the store update rather than inside it: correspondence is
  /// an async signature probe and the update's callback is synchronous.
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

  /// Asks the atSign's other enrollments for the root private when this one is
  /// entitled to hold it and does not, returning how many key packages were
  /// asked — 0 when nothing was needed or nobody could be asked.
  ///
  /// A broadcast rather than a wait: the answer arrives later as an ordinary
  /// secret that [filePendingPrivate] files at this or a later start.
  Future<int> requestPrivateIfAbsent({
    required Future<bool> Function() isFullyPrivileged,
    required PairwiseSecretSharing sharing,
    required String namespace,
  }) async {
    final atSign = atClient.getCurrentAtSign()?.toAtsign();
    if (atSign == null) return 0;

    if (await privateHalf(atSign) != null) return 0;

    // NOTE: the atSign's own credential cannot ask — enumerating the holders
    // goes through `enroll:listns`, which the atServer refuses without APKAM
    // authentication — and its route to a missing root is to mint one.
    if (isAtSignCredential(atClient.enrollmentId)) {
      return 0;
    }

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
  /// record advertises, and returns whether anything was retired.
  ///
  /// Silent when the atSign publishes no root or the record cannot be read: a
  /// private held before its record is published is the ordinary
  /// crash-recovery state, and an unreadable record is no evidence at all.
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
  /// [roots] that still vouches for what a key did, and returns whether
  /// anything was retired.
  ///
  /// Active and retired entries both vouch, while one whose status this build
  /// cannot read does not — the same judgement `PqSigningChain`'s verifier
  /// makes about the entries it checks a signature against.
  Future<bool> _retireUnadvertised(
      String atSign, AtKeys keys, List<ApskSigningKey> roots) async {
    final vouching =
        roots.where((root) => root.vouchesForPastOperations).toList();
    // NOTE: materialised before any retire — _retireSlot writes through the
    // same store this was read from, so a lazy filter on `status == active`
    // would be re-evaluated against material it had just moved.
    final held = _activePrivates(keys).toList();
    var retired = false;
    for (final material in held) {
      if (await _correspondingRoot(
              Uint8List.fromList(material.bytes.bytes), vouching) !=
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
  /// [namespace] so this client can answer other enrollments' pulls — serving
  /// it stays gated by
  /// [PairwiseSecretSharing.perEnrollmentSecretRequestGate] — and returns
  /// whether anything was primed.
  ///
  /// Has to run at every start: the secret store is in memory, and a restart
  /// empties it.
  Future<bool> hydrateStore(
      PairwiseSecretSharing sharing, String namespace) async {
    final atSign = atClient.getCurrentAtSign()?.toAtsign();
    if (atSign == null) return false;
    final private = await privateHalf(atSign);
    if (private == null) return false;
    await sharing.secretStore.putIfNewer(Secret(
      namespace: namespace,
      name: secretName,
      value: base64Encode(private),
    ));
    return true;
  }

  /// Files a conveyed root private waiting in the secret store, if there is one
  /// this client does not already hold, and returns whether it filed.
  ///
  /// A one-shot check of the store rather than a subscription, so a private
  /// arriving after this runs is filed at the next start.
  Future<bool> filePendingPrivate(
      String atSign, Iterable<Secret> heldSecrets) async {
    final secret = heldSecrets.where((s) => s.name == secretName).firstOrNull;
    if (secret == null) return false;
    return file(atSign, secret);
  }

  /// The entry in [roots] that [private] is the private half of, or null —
  /// settling whether this is a root private for this atSign without trusting
  /// whoever supplied it.
  ///
  /// Any entry, not only the active one: mid-rotation the record advertises a
  /// successor beside its retired predecessor, and both are the atSign's own.
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
  /// Every root-link verifier comes here rather than constructing its own.
  static MlDsa65PureDartAlgo? verifierFor(SigningAlgoType alg) =>
      alg == SigningAlgoType.mldsa65 ? MlDsa65PureDartAlgo() : null;

  static final Uint8List _probe =
      Uint8List.fromList(utf8.encode('pq_signing_root correspondence probe'));

  /// Whether [id] is a root slot: [keyIdRole], any algorithm, then a generation
  /// number.
  static bool _isRootSlot(String id) => AtKeys.isRoleKeyId(id, keyIdRole);

  /// Every active root private this keyfile holds, in filed order; callers that
  /// need *the* one to sign with go through [_signingPrivate].
  ///
  /// Must stay local and synchronous: [store] asks this inside the keyfile
  /// update's callback, where no round trip is possible.
  Iterable<CryptographicMaterial> _activePrivates(AtKeys keys) =>
      keys.atSignKeys.where((m) =>
          m.role == CryptographicMaterialRole.privateSigning &&
          m.status == CryptographicMaterialStatus.active &&
          _isRootSlot(m.keyId));

  /// The one active root private the record says may sign — the active private
  /// corresponding to an **active** advertised entry.
  ///
  /// The record is consulted only when the keyfile holds more than one, and an
  /// unreadable record leaves the first filed as the answer.
  Future<CryptographicMaterial?> _signingPrivate(
      String atSign, AtKeys keys) async {
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
    if (advertised.isEmpty) {
      _logger.warning('$atSign holds ${held.length} active signing root '
          'privates and the record advertises no root this build can verify; '
          'the first filed is used');
      return held.first;
    }
    final active = advertised.where((e) => e.offeredForNewOperations).toList();

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
  /// Generations count per algorithm rather than sharing one counter.
  String _freeSlot(AtKeys keys, CryptographicMaterialAlgorithm algorithm) =>
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
      // NOTE: the slot is chosen inside the update — picked from a snapshot
      // read outside, a sibling could take the same free slot, and `addKey`
      // refuses a duplicate keyId.
      String? slot;
      var overtaken = false;
      await io.update(atSign.toAtsign(), (keys) {
        if (_activePrivates(keys).isNotEmpty) {
          overtaken = true;
          return false;
        }
        slot = _freeSlot(keys, rootKeyAlgoToken);
        final createdAt = DateTime.now().toUtc();
        keys.addKey(CryptographicMaterial(
          keyId: slot!,
          role: CryptographicMaterialRole.privateSigning,
          algorithm: rootKeyAlgoToken,
          bytes: AtBytes(pair.secretKey),
          createdAt: createdAt,
        ));
        keys.addKey(CryptographicMaterial(
          keyId: slot!,
          role: CryptographicMaterialRole.publicVerification,
          algorithm: rootKeyAlgoToken,
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
      keys.retireAtSignKey(slot, to: CryptographicMaterialStatus.dead);
      return true;
    });
  }
}
