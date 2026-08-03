import 'dart:async' show StreamSubscription;
import 'dart:convert' show base64Decode;

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

  StreamSubscription<ReceivedSecret>? _subscription;

  NskeyPrivateFiling({required this.keysIo, required String atSign})
      : atSign = atSign.toAtsign();

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

    final AtKeys keys;
    try {
      keys = await keysIo.read(atSign);
    } catch (e) {
      _logger.severe('Cannot file the nskey private for '
          '${secret.namespace}:$nskeyKid — this atSign has no readable AtKeys: '
          '$e');
      return false;
    }

    final keyId = keyIdFor(secret.namespace, nskeyKid);
    if (keys.getKey(keyId, CryptographicKeyType.privateDecapsulation) != null) {
      // Re-delivery is expected: the substrate converges by re-sending, and
      // putIfNewer already made arrival idempotent upstream.
      return false;
    }

    keys.addKey(AtKeysMaterial(
      keyId: keyId,
      keyPartType: CryptographicKeyType.privateDecapsulation,
      keyAlgorithmType: KeyAlgorithmType.xWing,
      bytes: AtBytes(base64Decode(secret.value)),
      createdAt: secret.createdAt,
    ));

    if (keysIo is WrittenAtKeysIo) {
      await (keysIo as WrittenAtKeysIo).flush(atSign.toAtsign(), keys);
    } else {
      // Read-only key storage: the private is usable for this process and
      // gone at restart, which is exactly the failure this exists to prevent.
      _logger.severe('Filed the nskey private for ${secret.namespace}:'
          '$nskeyKid in memory only — this AtKeysIo cannot persist, so a '
          'restart will lose it and every value its content keys protect '
          'becomes unreadable');
    }
    return true;
  }
}
