/// A named mutual-exclusion lock shared by every tab of the origin.
abstract interface class SetupLock {
  /// Runs [body] once no other holder of [name] is running, and releases
  /// [name] when [body] completes or throws.
  Future<T> run<T>(String name, Future<T> Function() body);
}

/// The lock name guarding first setup of [canonicalAtSign].
String setupLockName(String canonicalAtSign) =>
    'at_client_wasm:setup:$canonicalAtSign';
