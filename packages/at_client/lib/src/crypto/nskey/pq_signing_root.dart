import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        AtKeysMaterial,
        CryptographicKeyType,
        KeyAlgorithmType,
        KeyPartStatus,
        WrittenAtKeysIo;
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client.dart'
    show AtClient, AtKey, AtValue, GetRequestOptions, Metadata;
import 'package:at_client/src/crypto/nskey/pq_signing_chain.dart'
    show PqSigningChain;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_builders.dart' show UpdateVerbBuilder;
import 'package:at_commons/at_commons.dart'
    show AtBytes, AtKeyNotFoundException, KeyNotFoundException;
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
/// **Create-once, and that matters more here than anywhere else.** The record
/// is written immutable, so the atServer refuses a second create and exactly
/// one root is ever published. The root never rotates, so two roots would be
/// unrecoverable rather than merely untidy — one half of the atSign's
/// enrollments would chain to a root the other half rejected, with no later
/// event able to reconcile them.
///
/// Only a **fully privileged** enrollment mints it — `rw` on `*` *and*
/// `__manage`. A namespace-restricted enrollment has no business minting the
/// key that vouches for every other enrollment, and could not convey it to the
/// privileged ones anyway.
@experimental
class PqSigningRoot {
  static const String recordName = 'pq_signing_root';

  /// The `AtKeys` id the private half is filed under. It carries no namespace
  /// — the root is atSign-level, which is exactly what distinguishes it from
  /// an nskey.
  ///
  /// Key material is never removed from `AtKeys`, only retired — so when this
  /// slot is occupied by the dead remains of a lost create, a later private
  /// files under `pq_signing_root.2` (then `.3`, …) instead. Readers go
  /// through [privateHalf], which scans the slots for the one active private.
  static const String keyId = 'pq_signing_root';

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

  final AtClient atClient;
  final AtKeysIo? keysIo;

  PqSigningRoot(this.atClient, {this.keysIo});

  AtKey keyFor(String atSign) => AtKey()
    ..key = recordName
    ..sharedBy = atSign
    ..metadata = (Metadata()
      ..isPublic = true
      ..immutable = true);

  /// The published root record's current public key.
  ///
  /// Returns null only when the atServer **confirms** no root exists. A record
  /// that cannot be read or decoded right now throws instead — absent and
  /// unreadable are different answers, and a caller that mints or retires on
  /// this answer must not be allowed to guess with an immutable record at
  /// stake.
  static Future<Uint8List?> publishedPublicKey(
      AtClient atClient, String atSign) async {
    final AtValue value;
    try {
      value = await atClient.get(
        AtKey.fromString('public:$recordName$atSign'),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } on KeyNotFoundException {
      return null;
    } on AtKeyNotFoundException {
      return null;
    }
    final record = jsonDecode(value.value as String) as Map;
    return base64Decode((record['keys'] as List).first as String);
  }

  /// Mints and publishes the root if this atSign has none, filing both halves
  /// of the pair first. Returns the public half, or null when this client did
  /// not mint (it is not privileged, one is already published, or it lost the
  /// create).
  ///
  /// Both halves are filed, not just the private: recovery from a crash
  /// between filing and publishing needs the public bytes to republish, and
  /// they cannot be derived from the private. A keyfile found holding an
  /// active pair with no record published is exactly that crash, and the held
  /// public is republished rather than a fresh pair minted — publishing a new
  /// pair would strand the filed private against a record it never matched.
  ///
  /// A loser of the create does **not** mint a second root — its just-filed
  /// pair is retired (it corresponds to nothing any verifier ever saw), so
  /// the every-start pull can be given the real private by a privileged
  /// enrollment that holds it. Left active, the losing pair would read as
  /// "already holding the root" forever and block that heal.
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
    final published = await publishedPublicKey(atClient, atSign);

    final AtKeys? keys = await _readKeys(atSign);
    final held = keys == null ? null : _activePrivate(keys);

    if (published != null) {
      // Someone already minted. Reconcile what this keyfile holds against the
      // record: an active private that does not correspond is the poisoned
      // leftover of a lost create recorded before losers retired their pair,
      // and while it stays active the pull's "already holding it" check can
      // never fire — the one heal such an enrollment has.
      if (held != null &&
          !await _corresponds(
              Uint8List.fromList(held.bytes.bytes), published)) {
        await _retireSlot(atSign, held.keyId);
        _logger.warning('Retired a signing root private held for $atSign '
            'that does not correspond to the published root; the real '
            'private is re-requested at a later start');
      }
      _logger.info(
          'Not minting a signing root for $atSign: one is already published');
      return null;
    }

    if (held != null) {
      final heldPublic =
          keys!.getKey(held.keyId, CryptographicKeyType.publicVerification);
      if (heldPublic != null) {
        // The crash between filing and publishing: finish the publish with
        // the pair already filed.
        return await _publishAndAnchor(
            atSign, held.keyId, Uint8List.fromList(heldPublic.bytes.bytes));
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
    // published root whose private did not survive can never be replaced,
    // because the record is immutable and the root does not rotate.
    final slot = await _storeFreshPair(atSign, pair);
    if (slot == null) {
      throw StateError(
          'could not store the signing root private for $atSign, so it is '
          'deliberately not published — an immutable record cannot be retried '
          'with a different key');
    }
    return await _publishAndAnchor(atSign, slot, pair.publicKey);
  }

  /// Publishes [publicKey] as the root record and anchors this enrollment to
  /// it. When the create did not land — another privileged enrollment got
  /// there first — retires the pair under [slot] and returns null.
  Future<Uint8List?> _publishAndAnchor(
      String atSign, String slot, Uint8List publicKey) async {
    try {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = keyFor(atSign)
            ..value = jsonEncode({
              'v': currentVersion,
              'keys': [base64Encode(publicKey)],
              'successor': null,
            }),
          sync: true);
    } catch (e) {
      // A throw here says the call failed, NOT what the atServer did. It is
      // usually the refusal of a second create — the create-once guarantee
      // working — but it is equally a dropped connection on a write that
      // landed. Those two need opposite handling and cannot be told apart
      // from the exception, so ask the record.
      //
      // Getting this wrong in the second case is unrecoverable: retiring the
      // pair for a root this client DID publish leaves the atSign with an
      // immutable, non-rotating record whose private nobody holds.
      final Uint8List? published;
      try {
        published = await publishedPublicKey(atClient, atSign);
      } catch (e2) {
        _logger.severe('Could not publish the signing root for $atSign and '
            'cannot read the record to find out whether the write landed, so '
            'the minted pair is KEPT: retiring it would brick the atSign if '
            'the write did land. A later start reconciles it against the '
            'record. ($e / $e2)');
        return null;
      }

      if (published != null && _sameBytes(published, publicKey)) {
        // The write landed and the failure was in reporting it. This client
        // holds the matching private, so it is the minter.
        _logger.warning('The signing root create for $atSign reported a '
            'failure but the published record is this client\'s key, so the '
            'write landed: $e');
        await _anchorSelf(atSign);
        return publicKey;
      }

      // Either somebody else's root is published, or none is and the write
      // genuinely failed. Both mean this pair corresponds to nothing any
      // verifier ever saw, so retiring it is safe — and necessary, or the
      // pull that heals this enrollment never fires.
      try {
        await _retireSlot(atSign, slot);
      } catch (e2) {
        _logger.severe('Lost the signing root create for $atSign and could '
            'not retire the losing pair; until a later start retires it, '
            'this enrollment wrongly reads as holding the root: $e2');
      }
      _logger.info('Did not publish a signing root for $atSign; one likely '
          'exists already: $e');
      return null;
    }

    await _anchorSelf(atSign);
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
      await PqSigningChain.publishOwnRootLink(atClient,
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

  /// Files [private] into `AtKeys`, leaving an existing **active** one alone.
  /// Returns whether an active private is durably held afterwards.
  Future<bool> store(String atSign, Uint8List private) async {
    final io = keysIo;
    if (io == null) return false;
    try {
      final AtKeys keys = await io.read(atSign);
      if (_activePrivate(keys) != null) {
        return true;
      }
      keys.addKey(AtKeysMaterial(
        keyId: _freeSlot(keys),
        keyPartType: CryptographicKeyType.privateSigning,
        keyAlgorithmType: KeyAlgorithmType.mlDsa65,
        bytes: AtBytes(private),
        createdAt: DateTime.now().toUtc(),
      ));
      if (io is WrittenAtKeysIo) {
        await io.flush(atSign.toAtsign(), keys);
      } else {
        _logger.severe('Filed the signing root for $atSign in memory only — '
            'this AtKeysIo cannot persist, and an immutable root cannot be '
            'minted again');
        return false;
      }
      return true;
    } catch (e) {
      _logger.severe('Cannot store the signing root private for $atSign: $e');
      return false;
    }
  }

  /// The root private this client holds, or null if it has none.
  Future<Uint8List?> privateHalf(String atSign) async {
    final AtKeys? keys = await _readKeys(atSign);
    if (keys == null) return null;
    final material = _activePrivate(keys);
    if (material == null) return null;
    return Uint8List.fromList(material.bytes.bytes);
  }

  /// Files a root private that arrived over the substrate, first checking it
  /// corresponds to the published root. Returns whether it was stored.
  ///
  /// Ignores anything that is not a root private, so this can be pointed at
  /// the whole arrival stream.
  ///
  /// The correspondence check is what stops a compromised or buggy holder
  /// handing this enrollment a key that signs links no verifier will ever
  /// accept — with the root immutable and non-rotating, filing the wrong
  /// bytes here would otherwise stick. A refused or unverifiable private is
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

    final Uint8List? published;
    try {
      published = await publishedPublicKey(atClient, atSign);
    } catch (e) {
      _logger.info('Cannot read the published signing root for $atSign right '
          'now, so the arriving private is not filed; it is re-requested at '
          'a later start: $e');
      return false;
    }
    if (published == null) {
      _logger.warning('Discarding a signing root private conveyed to $atSign: '
          'the atSign publishes no root for it to correspond to');
      return false;
    }
    if (!await _corresponds(private, published)) {
      _logger.warning('Discarding a signing root private conveyed to $atSign: '
          'it does not correspond to the published root');
      return false;
    }

    final stored = await store(atSign, private);
    if (stored) {
      _logger.info('Filed the signing root private for $atSign');
    }
    return stored;
  }

  /// Asks the atSign's other enrollments for the root private, when this one
  /// is entitled to hold it and does not. Returns how many key packages were
  /// asked — 0 when nothing was needed or nobody could be asked.
  ///
  /// **This is the only route left for an enrollment that missed the
  /// approval-time conveyance.** The root is atSign-level and carries no
  /// namespace, so it is excluded from the `enroll:listns` fan-out by
  /// construction; and it is immutable and never rotates, so no later event
  /// can mint a replacement. Without a pull, such an enrollment stays without
  /// it forever.
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

  /// Retires a held root private that does not correspond to the published
  /// root. Returns whether anything was retired.
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
  /// decays on its own, and the record is immutable, so without this it is
  /// permanent.
  ///
  /// Deliberately silent when the atSign publishes no root, or when the
  /// record cannot be read: a private held before its record is published is
  /// the ordinary crash-recovery state, and an unreadable record is no
  /// evidence at all.
  Future<bool> reconcileHeldPrivate(String atSign) async {
    final AtKeys? keys = await _readKeys(atSign);
    if (keys == null) return false;
    final held = _activePrivate(keys);
    if (held == null) return false;

    final Uint8List? published;
    try {
      published = await publishedPublicKey(atClient, atSign);
    } catch (e) {
      _logger.info('Cannot check the signing root private held for $atSign '
          'against the published record right now: $e');
      return false;
    }
    if (published == null) return false;
    if (await _corresponds(Uint8List.fromList(held.bytes.bytes), published)) {
      return false;
    }

    await _retireSlot(atSign, held.keyId);
    _logger.warning('Retired a signing root private held for $atSign that '
        'does not correspond to the published root; this enrollment can now '
        'ask a holder for the real one');
    return true;
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
  /// itself — and the root, being immutable and non-rotating, cannot be minted
  /// again to recover.
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

  /// Whether [private] signs something [published] verifies — settles "is
  /// this THE root private" without trusting whoever supplied it. Bytes of
  /// the wrong shape cannot be the root private, so a throwing sign or
  /// verify is simply false.
  static Future<bool> _corresponds(
      Uint8List private, Uint8List published) async {
    try {
      final algo = MlDsa65PureDartAlgo();
      final signature = await algo.signBytes(_probe, secretKey: private);
      return await algo.verifyBytes(_probe,
          signature: signature, publicKey: published);
    } catch (e) {
      return false;
    }
  }

  static final Uint8List _probe =
      Uint8List.fromList(utf8.encode('pq_signing_root correspondence probe'));

  /// A root-private slot: the canonical [keyId], or the `.2`/`.3`/… overflow
  /// a slot occupied by retired remains pushes a later private into.
  static bool _isRootSlot(String id) =>
      id == keyId || RegExp('^${RegExp.escape(keyId)}\\.\\d+\$').hasMatch(id);

  AtKeysMaterial? _activePrivate(AtKeys keys) => keys.keys
      .where((m) =>
          m.keyPartType == CryptographicKeyType.privateSigning &&
          m.status == KeyPartStatus.active &&
          _isRootSlot(m.keyId))
      .firstOrNull;

  /// The first root slot with no material at all — retired remains keep
  /// their slot forever, so a new private lands beside them, never over them.
  String _freeSlot(AtKeys keys) {
    if (keys.keysForKeyId(keyId).isEmpty) return keyId;
    for (var n = 2;; n++) {
      final candidate = '$keyId.$n';
      if (keys.keysForKeyId(candidate).isEmpty) return candidate;
    }
  }

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
  /// Returns the slot, or null when the pair could not be persisted.
  Future<String?> _storeFreshPair(
      String atSign, ({Uint8List publicKey, Uint8List secretKey}) pair) async {
    final io = keysIo;
    if (io == null) return null;
    try {
      final AtKeys keys = await io.read(atSign);
      final slot = _freeSlot(keys);
      final createdAt = DateTime.now().toUtc();
      keys.addKey(AtKeysMaterial(
        keyId: slot,
        keyPartType: CryptographicKeyType.privateSigning,
        keyAlgorithmType: KeyAlgorithmType.mlDsa65,
        bytes: AtBytes(pair.secretKey),
        createdAt: createdAt,
      ));
      keys.addKey(AtKeysMaterial(
        keyId: slot,
        keyPartType: CryptographicKeyType.publicVerification,
        keyAlgorithmType: KeyAlgorithmType.mlDsa65,
        bytes: AtBytes(pair.publicKey),
        createdAt: createdAt,
      ));
      if (io is! WrittenAtKeysIo) {
        _logger.severe('Filed the signing root for $atSign in memory only — '
            'this AtKeysIo cannot persist, and an immutable root cannot be '
            'minted again');
        return null;
      }
      await io.flush(atSign.toAtsign(), keys);
      return slot;
    } catch (e) {
      _logger.severe('Cannot store the signing root pair for $atSign: $e');
      return null;
    }
  }

  /// Marks every material under [slot] dead and flushes. Dead rather than
  /// retired: these bytes never protected anything, and must never be
  /// mistaken for a key that did.
  Future<void> _retireSlot(String atSign, String slot) async {
    final io = keysIo;
    if (io == null) return;
    final AtKeys keys = await io.read(atSign);
    keys.retireKey(slot, to: KeyPartStatus.dead);
    if (io is WrittenAtKeysIo) {
      await io.flush(atSign.toAtsign(), keys);
    }
  }
}
