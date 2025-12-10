import 'package:at_client/at_client.dart';
import 'package:at_chops/at_chops.dart';
import 'package:mocktail/mocktail.dart';
import 'dart:math';

/// Mock implementations
class MockAtClient extends Mock implements AtClient {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockNotificationService extends Mock implements NotificationService {}

class MockSyncService extends Mock implements SyncService {}

/// Fake implementations for fallback values
class FakeAtKey extends Fake implements AtKey {}

class FakeMetadata extends Fake implements Metadata {}

class FakeAtClientPreference extends Fake implements AtClientPreference {}

/// Test data generators
class TestDataGenerator {
  static final Random _random = Random();

  /// Generate random alphanumeric string
  static String randomString(int length) {
    const chars =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(_random.nextInt(chars.length))));
  }

  /// Create test AtChops instance with generated keys
  static Future<AtChops> createTestAtChops() async {
    final encryptionKeyPair = AtChopsUtil.generateAtEncryptionKeyPair();
    final pkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    final atChopsKeys = AtChopsKeys.create(encryptionKeyPair, pkamKeyPair);
    atChopsKeys.selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    return AtChopsImpl(atChopsKeys);
  }

  /// Create test AtKey with customizable fields
  static AtKey createTestAtKey({
    String? key,
    String? sharedWith,
    String? sharedBy,
    String? namespace,
    bool isLocal = false,
    Metadata? metadata,
  }) {
    final atKey = AtKey()
      ..key = key ?? 'test_${randomString(8)}'
      ..sharedWith = sharedWith
      ..sharedBy = sharedBy ?? '@alice'
      ..namespace = namespace ?? 'test'
      ..isLocal = isLocal
      ..metadata = metadata ?? Metadata();
    return atKey;
  }

  /// Create test Metadata with customizable fields
  static Metadata createTestMetadata({
    int? ttl,
    int? ttb,
    int? ttr,
    bool? ccd,
    bool isPublic = false,
    bool isHidden = false,
  }) {
    return Metadata()
      ..ttl = ttl
      ..ttb = ttb
      ..ttr = ttr
      ..ccd = ccd
      ..isPublic = isPublic
      ..isHidden = isHidden;
  }
}

/// Register all fake fallback values for mocktail
void registerFallbackValues() {
  registerFallbackValue(FakeAtKey());
  registerFallbackValue(FakeMetadata());
  registerFallbackValue(FakeAtClientPreference());
}
