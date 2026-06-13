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
/// rotating epoch keys via a [PairwiseGroup] over the secret-sharing
/// substrate (Phase 3). A thin adapter from the [CryptoProvider] contract to
/// a per-scope group, materialised lazily on first use.
///
/// Self-encryption only in v1: [encrypt] rejects a key shared with another
/// atSign (cross-atSign pair groups are Phase 4; the future pq-mls provider
/// is a separate id, e.g. `'mls'`, so the two coexist). Apps that set
/// `defaultProviderId: 'group'` govern their self keys with it and route
/// shared keys to another provider.
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

  @override
  Future<void> initialize(CryptoContext context) async {
    _atClient = context.atClient;
    _currentAtSign = context.currentAtSign.toString();
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
  Future<CryptoEncryptResult> encrypt(CryptoEncryptRequest request) async {
    final scope = _scopeOf(request.atKey);
    await _ensureRegistered(scope);
    final sealed = await _groupFor(scope)
        .seal(Uint8List.fromList(utf8.encode(request.plaintext.toString())));
    return CryptoEncryptResult(
      ciphertext: base64Encode(sealed.ciphertext),
      metadata: AppMetadata(providerId: id, additional: {
        'scope': scope,
        'epoch': sealed.epoch,
        'kid': sealed.kid,
        'enc': 'aes-256-gcm',
        'iv': base64Encode(sealed.iv),
      }),
      isEncrypted: true,
    );
  }

  @override
  Future<CryptoDecryptResult> decrypt(CryptoDecryptRequest request) async {
    final a = request.metadata.additional;
    if (a == null || a['scope'] == null) {
      throw ArgumentError(
          'group provider decrypt: missing appMetadata.additional scope/kid');
    }
    final plaintext = await _groupFor(a['scope'].toString()).open(Sealed(
      // epoch may round-trip through the wire as a string; parse defensively.
      epoch: a['epoch'] is int ? a['epoch'] as int : int.parse('${a['epoch']}'),
      kid: a['kid'].toString(),
      iv: base64Decode(a['iv'].toString()),
      ciphertext: base64Decode(request.ciphertext.toString()),
    ));
    return CryptoDecryptResult(plaintext: utf8.decode(plaintext));
  }
}
