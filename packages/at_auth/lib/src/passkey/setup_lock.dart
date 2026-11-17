/// A named mutual-exclusion lock shared by every tab of the origin.
abstract class SetupLock {
  /// Runs [body] once no other holder of [name] is running, and releases
  /// [name] when [body] completes or throws.
  Future<T> run<T>(String name, Future<T> Function() body);
}

/// The lock name guarding first setup of [canonicalAtSign], under the
/// caller's [prefix]: `<prefix>:<canonicalAtSign>`.
///
/// Every tab of an origin must use the same [prefix] for the same atSign to
/// share one lock.
String setupLockName(String prefix, String canonicalAtSign) =>
    '$prefix:$canonicalAtSign';
