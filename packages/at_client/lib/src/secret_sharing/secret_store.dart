/// A named secret, scoped to an application namespace.
///
/// The namespace is the unit of authorization: a secret tagged `myapp` is
/// only ever shared with (and only ever deliverable to) enrollments
/// authorized for `myapp` — see SecretStore.namespaceAuthorizes and the
/// envelope key shape in PairwiseSecretSharing.
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
abstract class SecretStorePersistence {
  Future<List<Secret>> load();

  Future<void> save(List<Secret> secrets);
}

/// In-memory store of the secrets this client holds, keyed by
/// (namespace, name).
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

  Future<void> putSecret(Secret secret) async {
    _secrets[_key(secret.namespace, secret.name)] = secret;
    await persistence?.save(listSecrets());
  }

  /// Stores [secret] only if no secret with the same (namespace, name)
  /// exists with the same or newer [Secret.createdAt]. Returns whether it
  /// was stored. This is the conflict rule for secrets arriving from other
  /// clients.
  Future<bool> putIfNewer(Secret secret) async {
    final existing = _secrets[_key(secret.namespace, secret.name)];
    if (existing != null && !secret.createdAt.isAfter(existing.createdAt)) {
      return false;
    }
    await putSecret(secret);
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

  /// All secrets, optionally restricted to one [namespace].
  List<Secret> listSecrets({String? namespace}) => _secrets.values
      .where((s) => namespace == null || s.namespace == namespace)
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
