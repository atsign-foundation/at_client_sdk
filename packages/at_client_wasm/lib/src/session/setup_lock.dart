/// A named mutual-exclusion lock shared by every tab of the origin.
abstract interface class SetupLock {
  /// Runs [body] once no other holder of [name] is running, and releases
  /// [name] when [body] completes or throws.
  Future<T> run<T>(String name, Future<T> Function() body);
}

/// The lock name guarding first setup of [canonicalAtSign].
String setupLockName(String canonicalAtSign) =>
    'at_client_wasm:setup:$canonicalAtSign';

/// Thrown when the lock named [lockName] is not granted within the
/// acquisition timeout.
class SetupLockTimeoutException implements Exception {
  /// Creates the exception for [lockName].
  const SetupLockTimeoutException(this.lockName);

  /// The name of the lock that was not granted.
  final String lockName;

  @override
  String toString() => 'SetupLockTimeoutException: $lockName was not granted';
}
