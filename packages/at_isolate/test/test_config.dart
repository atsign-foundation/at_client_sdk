import 'dart:io';

/// Configuration for tests that need real atSign credentials
class TestConfig {
  static String? get testAtSign => Platform.environment['TEST_ATSIGN'];
  static String? get testKeysPath => Platform.environment['TEST_KEYS_PATH'];
  static String? get testRootDomain => Platform.environment['TEST_ROOT_DOMAIN'];

  static bool get hasCredentials => testAtSign != null && testKeysPath != null;

  static String get skipMessage =>
      'Skipped: Set TEST_ATSIGN and TEST_KEYS_PATH environment variables to run this test';
}
