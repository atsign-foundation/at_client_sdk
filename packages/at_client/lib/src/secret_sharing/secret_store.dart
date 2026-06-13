import 'package:meta/meta.dart' show experimental;

/// A named secret, scoped to an application namespace.
///
/// The namespace is the unit of authorization: a secret tagged `myapp` is
/// only ever shared with (and only ever deliverable to) enrollments
/// authorized for `myapp` — see SecretStore.namespaceAuthorizes and the
/// envelope key shape in PairwiseSecretSharing.
@experimental
class Secret {
  final String namespace;
  final String name;
  final String value;
  final DateTime createdAt;

  Secret({
    required this.namespace,
    required this.name,
    required this.value,
    DateTime? createdAt,
  }) : createdAt = (createdAt ?? DateTime.now()).toUtc();

  Map<String, Object?> toJson() => {
        'namespace': namespace,
        'name': name,
        'value': value,
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
    return Secret(
      namespace: json['namespace'],
      name: json['name'],
      value: json['value'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

/// Supplied by the app to persist the [SecretStore] beyond the process
/// lifetime (platform keystore, biometric storage, etc. — the app's
/// concern). Without one, the store is in-memory only.
@experimental
abstract class SecretStorePersistence {
  Future<List<Secret>> load();

  Future<void> save(List<Secret> secrets);
}

/// In-memory store of the secrets this client holds, keyed by
/// (namespace, name).
@experimental
class SecretStore {
  final Map<String, Secret> _secrets = {};

  SecretStorePersistence? persistence;

  SecretStore({this.persistence});

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
    await persistence?.save(listSecrets());
  }

  /// Stores [secret] only if no secret with the same (namespace, name)
  /// exists with the same or newer [Secret.createdAt]. Returns whether it
  /// was stored. This is the conflict rule for secrets arriving from other
  /// clients — and as the arrival/merge path it accepts reserved (`__`)
  /// names: system secrets must flow between clients.
  Future<bool> putIfNewer(Secret secret) async {
    final existing = _secrets[_key(secret.namespace, secret.name)];
    if (existing != null && !secret.createdAt.isAfter(existing.createdAt)) {
      return false;
    }
    await putSecret(secret, allowReservedName: true);
    return true;
  }

  Secret? getSecret(String namespace, String name) =>
      _secrets[_key(namespace, name)];

  Future<bool> removeSecret(String namespace, String name) async {
    final removed = _secrets.remove(_key(namespace, name)) != null;
    if (removed) {
      await persistence?.save(listSecrets());
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
