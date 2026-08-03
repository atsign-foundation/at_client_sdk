import 'dart:async' show StreamSubscription;
import 'dart:convert' show base64Decode;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart' show XWingPureDartAlgo;
import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        AtKeysMaterial,
        CryptographicKeyType,
        KeyAlgorithmType,
        WrittenAtKeysIo;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show ReceivedSecret;
import 'package:at_client/src/secret_sharing/secret_store.dart' show Secret;
import 'package:at_commons/at_commons.dart' show AtBytes;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('NskeyPrivateFiling');

/// Moves an arriving nskey private out of the secret-sharing transit buffer
/// and into [AtKeys], where key material that must survive a restart belongs.
///
/// The substrate carries opaque secrets and knows nothing about keys; this is
/// the crypto layer recognising its own material on the way past. Two things
/// follow from filing it here rather than leaving it in the `SecretStore`:
/// it lands under `AtKeysIo`'s never-lose contract with the at-rest protection
/// those implementations already provide, and no app-supplied persistence
/// backend ever ends up holding this atSign's namespace private keys.
///
/// Losing an nskey private is not recoverable: every conveyance record sealed
/// to it becomes unopenable, and with it every value those content keys
/// protect. That is what separates it from a content key, which is only ever
/// a cache — a reader re-fetches any CK from its conveyance record.
@experimental
class NskeyPrivateFiling {
  /// The reserved [Secret] name an nskey private arrives under:
  /// `__nskey.<nskeyKid>`, in the namespace the key belongs to.
  ///
  /// The kid is in the name and the namespace is the secret's own, which
  /// together with the receiving atSign gives the
  /// `(owner, namespace, nskeyKid)` the design keys these by. The owner is
  /// implicit: the substrate only ever moves secrets between APKAM keypairs of
  /// **one** atSign, so an arriving nskey private is always this atSign's.
  static const String secretNamePrefix = '__nskey.';

  /// The `AtKeys` key id a filed private is stored under. The namespace is
  /// part of it deliberately — kids are truncated hashes and are not unique
  /// across namespaces, the same reason the content-key cache is never keyed
  /// by `ckKid` alone.
  static String keyIdFor(String namespace, String nskeyKid) =>
      'nskey.$namespace.$nskeyKid';

  final AtKeysIo keysIo;
  final String atSign;

  /// The published public half for `(namespace, nskeyKid)`, used to check that
  /// an arriving private actually corresponds to the key peers are sealing to.
  ///
  /// A secondary check, subordinate to the signature that already
  /// authenticated the envelope — but a cheap one, and the only thing that
  /// catches a private that is genuinely from this atSign and simply wrong:
  /// the wrong generation, or a truncation. Filing that would leave the client
  /// believing it can open a namespace it cannot, and the failure would
  /// surface later, on data, as corruption rather than as a bad key.
  final Future<Uint8List?> Function(String namespace, String nskeyKid)?
      publishedPublicKey;

  StreamSubscription<ReceivedSecret>? _subscription;

  NskeyPrivateFiling({
    required this.keysIo,
    required String atSign,
    this.publishedPublicKey,
  }) : atSign = atSign.toAtsign();

  /// Files every nskey private arriving on [receivedSecrets].
  ///
  /// Subscribe before the substrate starts listening: the stream is a
  /// broadcast and does not replay what it emitted before subscription, so a
  /// private conveyed in the gap would be filed nowhere.
  void start(Stream<ReceivedSecret> receivedSecrets) {
    _subscription ??= receivedSecrets.listen((received) {
      if (!received.secret.name.startsWith(secretNamePrefix)) return;
      file(received.secret);
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
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
    final private = Uint8List.fromList(base64Decode(secret.value));
    if (!await _corresponds(secret.namespace, nskeyKid, private)) return false;

    return store(
      namespace: secret.namespace,
      nskeyKid: nskeyKid,
      private: private,
      createdAt: secret.createdAt,
    );
  }

  /// Whether [private] derives the public half published for
  /// `(namespace, nskeyKid)`. True when no lookup was supplied — the check is
  /// secondary, and refusing everything for want of it would be worse than
  /// not making it.
  Future<bool> _corresponds(
      String namespace, String nskeyKid, Uint8List private) async {
    final lookup = publishedPublicKey;
    if (lookup == null) return true;

    final Uint8List? published;
    try {
      published = await lookup(namespace, nskeyKid);
    } catch (e) {
      _logger.info('Could not fetch the published nskey for '
          '$namespace:$nskeyKid to check correspondence, so filing on the '
          'signature alone: $e');
      return true;
    }
    if (published == null) return true;

    // An X-Wing secret key IS its seed, so the public half derives from it
    // exactly.
    final derived =
        (await XWingPureDartAlgo.instance.generateKeyPair(private)).publicKey;
    if (_sameBytes(derived, published)) return true;

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

  /// The nskey private for `(namespace, nskeyKid)`, or null if this client
  /// does not hold it.
  ///
  /// Read from `AtKeys` rather than from memory, so it survives the restart
  /// that is the whole reason for filing it there.
  Future<Uint8List?> read(String namespace, String nskeyKid) async {
    try {
      final keys = await keysIo.read(atSign);
      final material = keys.getKey(keyIdFor(namespace, nskeyKid),
          CryptographicKeyType.privateDecapsulation);
      if (material == null) return null;
      return Uint8List.fromList(material.bytes.bytes);
    } catch (e) {
      _logger.finer('No nskey private for $namespace:$nskeyKid ($e)');
      return null;
    }
  }

  /// Stores an nskey private this client either minted or was conveyed.
  ///
  /// The minting path calls this **before publishing the public half**: a
  /// published key whose private did not survive leaves every sender sealing
  /// to something nobody can open, and no later repair recovers the data
  /// written in between.
  Future<bool> store({
    required String namespace,
    required String nskeyKid,
    required Uint8List private,
    DateTime? createdAt,
  }) async {
    final AtKeys keys;
    try {
      keys = await keysIo.read(atSign);
    } catch (e) {
      _logger.severe('Cannot file the nskey private for '
          '$namespace:$nskeyKid — this atSign has no readable AtKeys: $e');
      return false;
    }

    final keyId = keyIdFor(namespace, nskeyKid);
    if (keys.getKey(keyId, CryptographicKeyType.privateDecapsulation) != null) {
      // Re-delivery is expected: the substrate converges by re-sending, and
      // putIfNewer already made arrival idempotent upstream.
      return false;
    }

    keys.addKey(AtKeysMaterial(
      keyId: keyId,
      keyPartType: CryptographicKeyType.privateDecapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(private),
      createdAt: createdAt ?? DateTime.now().toUtc(),
    ));

    if (keysIo is WrittenAtKeysIo) {
      await (keysIo as WrittenAtKeysIo).flush(atSign.toAtsign(), keys);
    } else {
      // Read-only key storage: the private is usable for this process and
      // gone at restart, which is exactly the failure this exists to prevent.
      _logger.severe('Filed the nskey private for $namespace:$nskeyKid in '
          'memory only — this AtKeysIo cannot persist, so a restart will lose '
          'it and every value its content keys protect becomes unreadable');
    }
    return true;
  }
}
