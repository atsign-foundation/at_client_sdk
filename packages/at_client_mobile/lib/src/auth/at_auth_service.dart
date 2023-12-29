abstract class AtAuthService {
  /// Checks whether the atSign has been onboarded.
  /// Queries the keychain for the encryption public key.
  /// If the key is found, the atSign is considered onboarded, and true is returned.
  /// Otherwise, false is returned.
  Future<bool> isOnboarded(String atSign);
}
