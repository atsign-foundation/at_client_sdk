import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('SecretStore');

/// A named secret, scoped to an application namespace.
///
/// The namespace is the unit of authorization: a secret tagged `myapp` is
/// only ever shared with (and only ever deliverable to) enrollments
/// authorized for `myapp` — see SecretStore.namespaceAuthorizes and the
/// envelope key shape in PairwiseSecretSharing.
///
/// [version] is a monotonic ordering counter for *rotations of the same
/// logical secret*: when set, [SecretStore.putIfNewer] orders on it (higher
/// wins) so the merge is deterministic regardless of any client's wall clock.
/// [createdAt] is only a tiebreak. Leave [version] null for secrets that are
/// never rotated.
@experimental
class Secret {
  final String namespace;
  final String name;
  final String value;
  final int? version;
  final DateTime createdAt;

  Secret({
    required this.namespace,
    required this.name,
    required this.value,
    this.version,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc();

  Map<String, Object?> toJson() => {
        'namespace': namespace,
        'name': name,
        'value': value,
        if (version != null) 'version': version,
        'createdAt': createdAt.toIso8601String(),
      };

  static Secret fromJson(Object? json) {
    if (json is! Map ||
        json['namespace'] is! String ||
        json['name'] is! String ||
        json['value'] is! String ||
        json['createdAt'] is! String) {
      throw FormatException('Secret: malformed json $json');
    }
    final version = json['version'];
    return Secret(
      namespace: json['namespace'],
      name: json['name'],
      value: json['value'],
      version: version is int ? version : null,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

/// Supplied by the app to persist the [SecretStore] beyond the process
/// lifetime (platform keystore, biometric storage, etc. — the app's
/// concern). Without one, the store is in-memory only.
///
/// The SDK deliberately ships no implementation. Key material the SDK itself
/// needs to survive a restart — an APKAM keypair, a key package's X-Wing
/// private half, an nskey private — is filed into `AtKeys` instead, where the
/// `AtKeysIo` implementations already handle at-rest protection. That keeps
/// this store free of anything whose loss would be unrecoverable, and keeps
/// the atSign's private keys out of whatever backend an app happens to supply.
///
/// [save] receives the complete secret list and replaces whatever was stored.
/// It is never called concurrently: [SecretStore] serialises saves, because a
/// backend that completed them out of order would persist an older snapshot
/// over a newer one and silently lose a secret.
@experimental
abstract class SecretStorePersistence {
  Future<List<Secret>> load();

  Future<void> save(List<Secret> secrets);
}

/// In-memory store of the secrets this atSign's APKAM keypair holds, keyed by
/// (namespace, name).
@experimental
class SecretStore {
  final Map<String, Secret> _secrets = {};

  SecretStorePersistence? persistence;

  SecretStore({this.persistence});

  /// Serialises calls into [SecretStorePersistence.save].
  ///
  /// Every mutation persists the whole list, and the mutation itself is
  /// synchronous while the save is not — so without this, two puts could each
  /// snapshot and then land in either order, leaving an older snapshot on top
  /// of a newer one. Chaining them means the last save to *start* is also the
  /// last to finish, and it always carries the newest state.
  Future<void> _saves = Future.value();

  Future<void> _persist() {
    final persistence = this.persistence;
    if (persistence == null) return Future.value();
    // Snapshot now, on the caller's turn, so the queued save cannot pick up a
    // later mutation and reorder relative to its own trigger.
    final snapshot = listSecrets();
    _saves = _saves.then((_) => persistence.save(snapshot)).catchError((e, st) {
      _logger.severe('Persisting the secret store failed: $e, $st');
    });
    return _saves;
  }

  String _key(String namespace, String name) => '$namespace:$name';

  /// Loads previously persisted secrets, if [persistence] is set.
  Future<void> init() async {
    final loaded = await persistence?.load();
    if (loaded == null) {
      return;
    }
    for (final secret in loaded) {
      _secrets[_key(secret.namespace, secret.name)] = secret;
    }
  }

  /// Stores [secret], overwriting any existing `(namespace, name)` entry.
  ///
  /// Names beginning `__` are **reserved for system use** (e.g. a crypto
  /// provider's key material such as `__rk.<epoch>.<kid>`) and are rejected
  /// with [ArgumentError] unless [allowReservedName] is set — which only
  /// system-level callers should do. This keeps app secrets and system
  /// secrets collision-free within a namespace.
  Future<void> putSecret(Secret secret,
      {bool allowReservedName = false}) async {
    if (!allowReservedName && secret.name.startsWith('__')) {
      throw ArgumentError.value(secret.name, 'secret.name',
          'Secret names beginning "__" are reserved for system use');
    }
    _secrets[_key(secret.namespace, secret.name)] = secret;
    await _persist();
  }

  /// Stores [secret] only if it is newer than any existing `(namespace, name)`
  /// entry. Returns whether it was stored. This is the conflict rule for
  /// secrets arriving from other clients — and as the arrival/merge path it
  /// accepts reserved (`__`) names: system secrets must flow between clients.
  ///
  /// "Newer" is decided on [Secret.version] when both carry one (higher wins —
  /// deterministic regardless of any client's clock); otherwise on
  /// [Secret.createdAt]. A same-version arrival is treated as not-newer (the
  /// existing copy is kept) unless its [createdAt] is strictly later.
  Future<bool> putIfNewer(Secret secret) async {
    final existing = _secrets[_key(secret.namespace, secret.name)];
    if (!_isNewer(secret, existing)) {
      return false;
    }
    await putSecret(secret, allowReservedName: true);
    return true;
  }

  static bool _isNewer(Secret candidate, Secret? existing) {
    if (existing == null) {
      return true;
    }
    final cv = candidate.version;
    final ev = existing.version;
    if (cv != null && ev != null && cv != ev) {
      return cv > ev;
    }
    // no versions, or equal versions: fall back to wall-clock tiebreak
    return candidate.createdAt.isAfter(existing.createdAt);
  }

  Secret? getSecret(String namespace, String name) =>
      _secrets[_key(namespace, name)];

  Future<bool> removeSecret(String namespace, String name) async {
    final removed = _secrets.remove(_key(namespace, name)) != null;
    if (removed) {
      await _persist();
    }
    return removed;
  }

  /// All secrets, optionally restricted to one [namespace] and/or to names
  /// beginning with [namePrefix]. The prefix filter lets a system caller
  /// enumerate a family of reserved secrets within a scope — e.g. the group
  /// provider listing `__rk.*` epoch keys for one (atSign, namespace) to
  /// resolve the current key or prune old epochs.
  List<Secret> listSecrets({String? namespace, String? namePrefix}) =>
      _secrets.values
          .where((s) =>
              (namespace == null || s.namespace == namespace) &&
              (namePrefix == null || s.name.startsWith(namePrefix)))
          .toList();

  /// Whether an enrollment approved for [approvedNamespaces] (a map of
  /// namespace -> access, as carried by an enrollment record) is authorized
  /// for [namespace].
  ///
  /// Mirrors the atServer's rule: authorized when an approved namespace is
  /// `*`, equals [namespace], or is a dot-suffix of it (an enrollment
  /// approved for `myapp` may access `data.myapp`).
  static bool namespaceAuthorizes(
      Map<String, dynamic> approvedNamespaces, String namespace) {
    for (final approved in approvedNamespaces.keys) {
      if (approved == '*' ||
          approved == namespace ||
          namespace.endsWith('.$approved')) {
        return true;
      }
    }
    return false;
  }
}
