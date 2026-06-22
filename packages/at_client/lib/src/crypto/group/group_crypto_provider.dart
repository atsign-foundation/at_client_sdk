import 'dart:convert' show base64Decode, base64Encode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart';
import 'package:at_client/src/secret_sharing/pairwise_group.dart';
import 'package:at_client/src/secret_sharing/secure_group.dart';
import 'package:at_commons/at_commons.dart' show AppMetadata, AtKey;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

/// `id = 'group'`. Encrypts **self** keys under per-(atSign, namespace)
/// rotating epoch keys via a [PairwiseGroup] over the secret-sharing channel.
/// A thin adapter from the [CryptoProvider] contract to a per-scope group,
/// materialised lazily on first use.
///
/// Self-encryption only in v1: [encrypt] rejects a key shared with another
/// atSign (cross-atSign pair groups are not yet supported; a future pq-mls
/// provider would be a separate id, e.g. `'mls'`, so the two coexist). Apps
/// that set `defaultProviderId: 'group'` govern their self keys with it and
/// route shared keys to another provider.
@experimental
class GroupCryptoProvider extends CryptoProvider {
  static const String providerId = 'group';

  late final AtClient _atClient;
  late final AtClientSecretSharing _sharing;
  late final String _currentAtSign;

  final RotationPolicy rotationPolicy;
  final Map<String, PairwiseGroup> _groups = {};
  final Set<String> _registered = {};

  GroupCryptoProvider({this.rotationPolicy = const RotationPolicy()});

  @override
  String get id => providerId;

  // The slim CryptoProvider contract has no lifecycle hook, so one-time setup
  // (substrate wiring + listener) runs lazily on first encrypt/decrypt. Cached
  // as a Future so concurrent first calls share a single run rather than racing
  // two client registrations / two listeners.
  Future<void>? _initialization;

  Future<void> _ensureInitialized(CryptoContext context) =>
      _initialization ??= _initialize(context);

  Future<void> _initialize(CryptoContext context) async {
    _atClient = context.atClient;
    _currentAtSign = _atClient.getCurrentAtSign() ?? '';
    // Obtain the substrate through the shared instance — never construct our
    // own, which would mint a second client identity for this AtClient.
    _sharing = AtClientSecretSharing.forClient(_atClient);
    // Establish the base client identity if the app hasn't already — the
    // listener and the per-scope namespace registrations both need it.
    // Idempotent: a no-op when the app already called registerClient().
    if (!_sharing.isRegistered) {
      await _sharing.registerClient();
    }
    await _sharing.startListening();
  }

  @visibleForTesting
  PairwiseGroup groupFor(String namespace) => _groupFor(namespace);

  PairwiseGroup _groupFor(String namespace) => _groups.putIfAbsent(
        namespace,
        () => PairwiseGroup(
          sharing: _sharing,
          atSign: _currentAtSign,
          namespace: namespace,
          rotationPolicy: rotationPolicy,
        ),
      );

  Future<void> _ensureRegistered(String namespace) async {
    if (_registered.contains(namespace)) return;
    // Additive: registers this client for the scope so peers discover it.
    await _sharing.registerClient(namespaces: [namespace]);
    _registered.add(namespace);
  }

  /// The (atSign, namespace) scope for [atKey], asserting it is a self key.
  String _scopeOf(AtKey atKey) {
    final ns = atKey.namespace;
    if (ns == null || ns.isEmpty) {
      throw ArgumentError(
          'group provider requires a namespaced key; "$atKey" has none');
    }
    final sharedWith = atKey.sharedWith;
    if (sharedWith != null && sharedWith != _currentAtSign) {
      throw StateError(
          'group provider (v1) encrypts self keys only; "$atKey" is shared '
          'with $sharedWith — route shared keys to another provider');
    }
    return ns;
  }

  @override
  Future<String> encrypt(
      CryptoContext context, AtKey atKey, String plaintext) async {
    await _ensureInitialized(context);
    final scope = _scopeOf(atKey);
    await _ensureRegistered(scope);
    final sealed =
        await _groupFor(scope).seal(Uint8List.fromList(utf8.encode(plaintext)));
    // The provider contributes only appMetadata.additional; the runtime stamps
    // providerId + isEncrypted after this returns.
    atKey.metadata.appMetadata = AppMetadata(providerId: id, additional: {
      'scope': scope,
      'epoch': sealed.epoch,
      'kid': sealed.kid,
      'enc': 'aes-256-gcm',
      'iv': base64Encode(sealed.iv),
    });
    return base64Encode(sealed.ciphertext);
  }

  @override
  Future<String> decrypt(
      CryptoContext context, AtKey atKey, String ciphertext) async {
    await _ensureInitialized(context);
    final a = atKey.metadata.appMetadata?.additional;
    if (a == null || a['scope'] == null) {
      throw ArgumentError(
          'group provider decrypt: missing appMetadata.additional scope/kid');
    }
    final plaintext = await _groupFor(a['scope'].toString()).open(Sealed(
      // epoch may round-trip through the wire as a string; parse defensively.
      epoch: a['epoch'] is int ? a['epoch'] as int : int.parse('${a['epoch']}'),
      kid: a['kid'].toString(),
      iv: base64Decode(a['iv'].toString()),
      ciphertext: base64Decode(ciphertext),
    ));
    return utf8.decode(plaintext);
  }
}
