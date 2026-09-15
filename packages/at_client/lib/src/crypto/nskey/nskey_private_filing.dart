import 'dart:async' show StreamController;
import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysSourceAbsentException,
        AtKeysIo,
        CryptographicMaterial,
        CryptographicMaterialRole,
        WrittenAtKeysIo;
import 'package:at_client/src/crypto/crypto.dart' show FiledNskeyPrivate;
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart'
    show NskeyAdvertisement, NskeyDecapsulationKey, NskeySeed;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyKeyfileIdFor, nskeyKeyfileIdPrefix, nskeySecretNamePrefix;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

final _logger = AtSignLogger('NskeyPrivateFiling');

/// Moves an arriving nskey private out of the secret-sharing transit buffer
/// and into [AtKeys], where key material that must survive a restart belongs.
///
/// The substrate carries opaque secrets and knows nothing about keys; this is
/// the crypto layer recognising its own material on the way past. Filing it
/// here rather than leaving it in the `SecretStore` puts it under `AtKeysIo`'s
/// never-lose contract, which is what the rest of the crypto layer reads from.
///
/// ⛔ Filing is not at-rest protection. `FileAtKeysIo` encrypts nothing without
/// a passphrase, and typed post-quantum material is not among the four legacy
/// fields it self-encrypts, so with no passphrase this is written as plaintext
/// base64. Filing also leaves the secret in the `SecretStore`, which persists
/// to whatever backend an app supplied — see [SecretStorePersistence].
///
/// Losing an nskey private is not recoverable: every conveyance record sealed
/// to it becomes unopenable, and with it every value those content keys
/// protect. That is what separates it from a content key, which is only ever
/// a cache — a reader re-fetches any CK from its conveyance record.
@experimental
class NskeyPrivateFiling {
  /// How long a pull for a conveyed nskey private waits for a holder to
  /// answer.
  ///
  /// The lower bound on how long anything holding out for that key must be
  /// willing to wait: `NotificationServiceImpl.parkTtl` is asserted to exceed
  /// it, because a park that expires first drops a notification whose key is
  /// still legitimately on its way.
  static const Duration conveyanceWait = Duration(minutes: 5);

  /// The reserved [Secret] name an nskey private arrives under:
  /// `__nskey.<nskeyKid>`, in the namespace the key belongs to.
  ///
  /// The kid is in the name and the namespace is the secret's own, which
  /// together with the receiving atSign gives the
  /// `(owner, namespace, nskeyKid)` the design keys these by. The owner is
  /// implicit: the substrate only ever moves secrets between APKAM keypairs of
  /// **one** atSign, so an arriving nskey private is always this atSign's.
  static const String secretNamePrefix = nskeySecretNamePrefix;

  /// The `AtKeys` key id a filed private is stored under. The namespace is
  /// part of it deliberately — kids are truncated hashes and are not unique
  /// across namespaces, the same reason the content-key cache is never keyed
  /// by `ckKid` alone.
  static String keyIdFor(String namespace, String nskeyKid) =>
      nskeyKeyfileIdFor(namespace, nskeyKid);

  final AtKeysIo keysIo;
  final String atSign;

  /// The published generation for `(namespace, nskeyKid)`, consulted to check
  /// that an arriving seed corresponds to the key peers are sealing to —
  /// and to learn which KEM it is a seed for, since the seed arrives as bare
  /// bytes and 32 or 64 of them are valid for one KEM or the other.
  ///
  /// A secondary check, subordinate to the signature that already
  /// authenticated the envelope, and the only thing that catches a private
  /// that is genuinely from this atSign and simply wrong: the wrong
  /// generation, or a truncation. Filing that would leave the client believing
  /// it can open a namespace it cannot, and the failure would surface later,
  /// on data, as corruption rather than as a bad key.
  final Future<NskeyAdvertisement?> Function(String namespace, String nskeyKid)?
      publishedGeneration;

  NskeyPrivateFiling({
    required this.keysIo,
    required String atSign,
    this.publishedGeneration,
  }) : atSign = atSign.toAtsign();

  final StreamController<FiledNskeyPrivate> _filed =
      StreamController<FiledNskeyPrivate>.broadcast();

  /// Awaited immediately before a private is stored, so a test can hold the
  /// filing open. Null in production.
  @visibleForTesting
  Future<void> Function()? holdBeforeStore;

  /// Fires once per private filed, **after** it is stored and readable.
  ///
  /// The signal a reader that came up empty waits on. It fires at the point of
  /// filing rather than where a secret arrives, because the start-time sweep
  /// consumes secrets that were already in the inbox and a signal keyed on
  /// arrival would miss them.
  ///
  /// Broadcast, and therefore not replayed. A caller subscribes before the read
  /// it expects to fail, or it can miss the event it is waiting for.
  Stream<FiledNskeyPrivate> get privatesFiled => _filed.stream;

  /// Emitted after the material is readable, never before: a listener that
  /// re-reads on this signal must find what the signal says is there.
  void _announceFiled(String namespace, String nskeyKid) {
    if (_filed.isClosed) return;
    _filed.add((owner: atSign, namespace: namespace, nskeyKid: nskeyKid));
  }

  /// Releases the signal. A filing whose owner is gone announces to nobody.
  Future<void> close() => _filed.close();

  /// Files every conveyed nskey private waiting in the secret store. Returns
  /// how many were filed.
  ///
  /// A private that arrives after this runs is filed at the next start, and
  /// until then the namespace simply reads as one this client cannot open.
  ///
  /// The caller must have swept first. The store is in memory and its only
  /// populator is [PairwiseSecretSharing.sweepOnce], so draining it before a
  /// sweep drains nothing.
  Future<int> filePending(Iterable<Secret> heldSecrets) async {
    int filed = 0;
    for (final secret
        in heldSecrets.where((s) => s.name.startsWith(secretNamePrefix))) {
      if (await file(secret)) filed++;
    }
    return filed;
  }

  /// Files one arriving [secret] as this atSign's nskey private for its
  /// namespace. Returns whether it was stored.
  Future<bool> file(Secret secret) async {
    final nskeyKid = secret.name.substring(secretNamePrefix.length);
    if (nskeyKid.isEmpty) {
      _logger.warning('Ignoring an nskey private with no kid in its name '
          '("${secret.name}"): there would be no way to tell which generation '
          'it opens');
      return false;
    }
    final seed = NskeySeed(Uint8List.fromList(base64Decode(secret.value)));
    final advertised = await _publishedFor(secret.namespace, nskeyKid);
    // NOTE: an arriving seed carries no algorithm, so the ENTRY under this kid
    // names it — never the document's own `alg`, which answers for whichever
    // entry a sender with no preference would take and would expand the seed
    // under the wrong KEM. A generation carrying no entry under this kid still
    // falls back to that single-key answer, so the seed is compared against
    // the key peers actually seal to and refused rather than filed.
    final entry = advertised == null
        ? null
        : (advertised.entryWithKid(nskeyKid) ??
            advertised.usableFor(SecretSharingAlgos.keyAlgos));
    final keyAlgo = entry?.alg ?? SecretSharingAlgos.xWing;
    if (!await _corresponds(secret.namespace, nskeyKid, seed, keyAlgo, entry)) {
      return false;
    }

    return store(
      namespace: secret.namespace,
      nskeyKid: nskeyKid,
      seed: seed,
      keyAlgo: keyAlgo,
      createdAt: secret.createdAt,
    );
  }

  /// The published generation, or null when there is no lookup or it fails.
  Future<NskeyAdvertisement?> _publishedFor(
      String namespace, String nskeyKid) async {
    final lookup = publishedGeneration;
    if (lookup == null) return null;
    try {
      return await lookup(namespace, nskeyKid);
    } catch (e) {
      _logger.info('Could not fetch the published nskey for '
          '$namespace:$nskeyKid: $e');
      return null;
    }
  }

  /// Whether [seed] derives the public half published for
  /// `(namespace, nskeyKid)`. True when nothing was published to compare
  /// against — the check is secondary, and refusing everything for want of it
  /// would be worse than not making it.
  Future<bool> _corresponds(String namespace, String nskeyKid, NskeySeed seed,
      String keyAlgo, PackageKey? advertised) async {
    if (advertised == null) return true;

    final kem = SecretSharingAlgos.kemFor(keyAlgo);
    if (kem == null) {
      _logger.severe('Refusing the nskey seed for $namespace:$nskeyKid — it '
          'is advertised as "$keyAlgo", which this build cannot expand');
      return false;
    }

    final Uint8List derived;
    try {
      derived = (await kem.keyPairFromSeed(seed.bytes)).publicKey;
    } on ArgumentError catch (e) {
      _logger.severe('Refusing the nskey seed for $namespace:$nskeyKid — it is '
          'not a valid $keyAlgo seed: $e');
      return false;
    }
    if (_sameBytes(derived, advertised.pubBytes)) return true;

    _logger.severe('Refusing the nskey private for $namespace:$nskeyKid — it '
        'does not derive the published public half, so filing it would leave '
        'this client believing it can open a namespace it cannot, and the '
        'failure would surface later on data as corruption');
    return false;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Reads the key source, separating "nothing here yet" from "this process
  /// cannot read what is here".
  ///
  /// Null means a genuine absence — no key source has been written for this
  /// atSign — and every caller answers it as "holds nothing", which is the
  /// truth. Anything else is re-thrown after being logged at `severe`,
  /// because the material may well exist and be unreadable: a truncated or
  /// corrupt document, a passphrase that was not supplied, a validation
  /// refusal. Reporting that as "holds nothing" makes an unreadable keyfile
  /// indistinguishable from an empty one, and a parked notification then waits
  /// for a filing that can never arrive.
  ///
  /// `severe` and not `warning`: it is unactionable from here and permanent
  /// until somebody repairs the file.
  Future<AtKeys?> _readSourceOrNull(String context) async {
    try {
      return await keysIo.read(atSign);
    } on AtKeysSourceAbsentException {
      return null;
    } catch (e) {
      _logger.severe('Cannot read this atSign\'s key source while looking up '
          '$context, so no nskey private can be found — the material may be '
          'present and unreadable rather than absent: $e');
      rethrow;
    }
  }

  /// The **decapsulation key** for `(namespace, nskeyKid)`, or null if this
  /// client does not hold it — expanded from the stored seed, ready for
  /// `pqOpen`.
  ///
  /// Read from `AtKeys` rather than from memory, so it survives the restart
  /// that is the whole reason for filing it there.
  Future<NskeyDecapsulationKey?> read(String namespace, String nskeyKid) async {
    // NOTE: outside the try below, deliberately — that catch names one cause,
    // "no nskey private", and a key source this process cannot read is a
    // different one.
    final keys = await _readSourceOrNull('$namespace:$nskeyKid');
    if (keys == null) return null;
    try {
      final material = keys.getAtSignKey(keyIdFor(namespace, nskeyKid),
          CryptographicMaterialRole.privateDecapsulation);
      if (material == null) return null;
      final keyAlgo = SecretSharingAlgos.keyAlgoForMaterial(material.algorithm);
      final kem = keyAlgo == null ? null : SecretSharingAlgos.kemFor(keyAlgo);
      if (kem == null) {
        _logger.info('The nskey seed for $namespace:$nskeyKid is a '
            '"${material.algorithm}" key this build cannot expand');
        return null;
      }
      try {
        return NskeyDecapsulationKey((await kem
                .keyPairFromSeed(Uint8List.fromList(material.bytes.bytes)))
            .secretKey);
      } on ArgumentError catch (e) {
        _logger.severe('The nskey material filed for $namespace:$nskeyKid '
            'under "${material.algorithm}" is not a valid seed for it, '
            'so this namespace cannot be opened: $e');
        return null;
      }
    } catch (e) {
      _logger.finer('No nskey private for $namespace:$nskeyKid ($e)');
      return null;
    }
  }

  /// The stored **seed** for `(namespace, nskeyKid)`, or null if this client
  /// does not hold it — the form that is conveyed to other enrollments, who
  /// validate an arrival by re-deriving the published public half from it.
  /// [read] is the expanded flavour for opening; this is the durable one for
  /// conveying.
  Future<NskeySeed?> readSeed(String namespace, String nskeyKid) async {
    final keys = await _readSourceOrNull('$namespace:$nskeyKid');
    if (keys == null) return null;
    try {
      final material = keys.getAtSignKey(keyIdFor(namespace, nskeyKid),
          CryptographicMaterialRole.privateDecapsulation);
      if (material == null) return null;
      return NskeySeed(Uint8List.fromList(material.bytes.bytes));
    } catch (e) {
      _logger.finer('No nskey private for $namespace:$nskeyKid ($e)');
      return null;
    }
  }

  /// Every private this keyfile holds, grouped by namespace: `{namespace:
  /// {nskeyKid: private}}`.
  ///
  /// Reads only the keyfile — no atServer round trip and no enrollment lookup —
  /// so it can run during client construction, before the services an
  /// enrollment lookup needs exist. What a holder can *answer* with is what it
  /// holds, not what it is authorised for.
  Future<Map<String, Map<String, NskeySeed>>> readAll() async {
    const prefix = nskeyKeyfileIdPrefix;
    final AtKeys? keys;
    try {
      keys = await _readSourceOrNull('every held private');
    } catch (e) {
      // NOTE: tolerated here and nowhere else — this runs during client
      // construction, where a client that cannot be built at all is worse than
      // one that starts holding nothing, and `_readSourceOrNull` has already
      // reported the failure at `severe`.
      _logger.finer('No nskey privates held ($e)');
      return const {};
    }
    if (keys == null) return const {};
    final held = <String, Map<String, NskeySeed>>{};
    for (final material in keys.atSignKeys) {
      if (material.role != CryptographicMaterialRole.privateDecapsulation ||
          !material.keyId.startsWith(prefix)) {
        continue;
      }
      // NOTE: in `nskey.<namespace>.<kid>` the namespace may itself contain
      // dots and the kid, a truncated hash, never does — so the LAST dot is
      // the boundary.
      final rest = material.keyId.substring(prefix.length);
      final cut = rest.lastIndexOf('.');
      if (cut <= 0) continue;
      held.putIfAbsent(
              rest.substring(0, cut), () => {})[rest.substring(cut + 1)] =
          NskeySeed(Uint8List.fromList(material.bytes.bytes));
    }
    return held;
  }

  /// Every nskey private this client holds for [namespace], keyed by its
  /// `nskeyKid`.
  ///
  /// All generations, not just the current one: data written under a
  /// superseded key is still readable, and only its own private opens it. A
  /// client given the current generation alone could read nothing written
  /// before the last rotation.
  Future<Map<String, NskeySeed>> readAllFor(String namespace) async {
    final prefix = keyIdFor(namespace, '');
    final keys = await _readSourceOrNull(namespace);
    if (keys == null) return const {};
    try {
      return {
        for (final material in keys.atSignKeys)
          if (material.role == CryptographicMaterialRole.privateDecapsulation &&
              material.keyId.startsWith(prefix))
            material.keyId.substring(prefix.length):
                NskeySeed(Uint8List.fromList(material.bytes.bytes))
      };
    } catch (e) {
      _logger.finer('No nskey privates for $namespace ($e)');
      return const {};
    }
  }

  /// Stores an nskey **seed** this client either minted or was conveyed.
  ///
  /// The seed, not the decapsulation key: they are the same bytes for X-Wing
  /// but not for ML-KEM, whose decapsulation key is expanded and cannot be
  /// turned back into a public half. [read] expands it again on the way out.
  ///
  /// [keyAlgo] is stored with it because the bytes alone do not identify a
  /// KEM — 32 and 64 bytes are both valid seeds for one of them.
  ///
  /// The minting path calls this **before publishing the public half**: a
  /// published key whose private did not survive leaves every sender sealing
  /// to something nobody can open, and no later repair recovers the data
  /// written in between.
  Future<bool> store({
    required String namespace,
    required String nskeyKid,
    required NskeySeed seed,
    String keyAlgo = SecretSharingAlgos.xWing,
    DateTime? createdAt,
  }) async {
    final hold = holdBeforeStore;
    if (hold != null) await hold();

    final materialAlgo = SecretSharingAlgos.materialAlgoFor(keyAlgo);
    if (materialAlgo == null) {
      _logger.severe('Refusing to file an nskey seed for $namespace:$nskeyKid '
          'under unknown algorithm "$keyAlgo" — it could not be expanded back '
          'into a usable key');
      return false;
    }

    final keyId = keyIdFor(namespace, nskeyKid);
    final io = keysIo;
    if (io is! WrittenAtKeysIo) {
      _logger.severe('Filed the nskey private for $namespace:$nskeyKid in '
          'memory only — this AtKeysIo cannot persist, so a restart will lose '
          'it and every value its content keys protect becomes unreadable');
      _announceFiled(namespace, nskeyKid);
      return true;
    }

    // NOTE: one read-mutate-write. Read-then-flush loses whichever of this and
    // the signing-root filing writes first — a client's start runs both as
    // sibling unawaited tasks.
    var filed = false;
    try {
      await io.update(atSign.toAtsign(), (keys) {
        if (keys.getAtSignKey(
                keyId, CryptographicMaterialRole.privateDecapsulation) !=
            null) {
          return false;
        }
        keys.addKey(CryptographicMaterial(
          keyId: keyId,
          role: CryptographicMaterialRole.privateDecapsulation,
          algorithm: materialAlgo,
          bytes: AtBytes(seed.bytes),
          createdAt: createdAt ?? DateTime.now().toUtc(),
        ));
        filed = true;
        return true;
      });
    } catch (e) {
      _logger.severe('Cannot file the nskey private for '
          '$namespace:$nskeyKid — this atSign has no writable AtKeys: $e');
      return false;
    }
    if (filed) _announceFiled(namespace, nskeyKid);
    return filed;
  }
}
